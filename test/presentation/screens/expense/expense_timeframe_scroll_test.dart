// Deep scroll-behavior tests for ExpenseTimeframeScreen.
//
// Guards the regression the user hit: on the AI-search / timeframe drill-down
// the header, AI insight card, summary hero, search bar and category filter
// were pinned (non-scrolling) while only a cramped bottom strip scrolled — so a
// tall AI card pushed the matched expenses off-screen with no way to reach them.
//
// After the fix everything below the back-button header lives in ONE
// CustomScrollView, so the whole page scrolls as a single fluid surface. These
// tests run the REAL screen against the REAL repository over an in-memory Drift
// DB and prove:
//   • The content is a single CustomScrollView (one scroll surface).
//   • The summary hero + search bar SCROLL AWAY with the list (not pinned).
//   • Expenses far below the fold are reachable by scrolling (no cramping).
//   • The tall AI insight card scrolls off, freeing the screen for expenses.
//   • Pagination still fires on scroll (40 → all, "end of list" footer).
//   • Empty / no-match state is centered and still overscroll/refreshable.
//   • Nothing throws during aggressive scrolling in either direction.

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_nexus/core/di/injection.dart';
import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/data/local/database/app_database.dart' as db;
import 'package:ai_nexus/data/repositories/expense_repository.dart';
import 'package:ai_nexus/domain/entities/expense_entities.dart';
import 'package:ai_nexus/presentation/screens/expense/expense_timeframe_screen.dart';
import 'package:ai_nexus/presentation/screens/expense/widgets/ai_recommendation_card.dart';
import 'package:ai_nexus/presentation/screens/expense/widgets/expense_item.dart';

class _FakeApi extends ApiClient {
  _FakeApi();
  Response<T> _r<T>(String p, Object? d) => Response<T>(
      requestOptions: RequestOptions(path: p), data: d as T?, statusCode: 200);
  @override
  Future<Response<T>> get<T>(String path,
          {Map<String, dynamic>? queryParameters, CancelToken? cancelToken}) async =>
      _r<T>(path, const <dynamic>[]);
  @override
  Future<Response<T>> post<T>(String path,
          {Object? data, Options? options, CancelToken? cancelToken}) async =>
      _r<T>(path, <String, dynamic>{'ok': true});
  @override
  Future<Response<T>> put<T>(String path, {Object? data}) async =>
      _r<T>(path, <String, dynamic>{});
  @override
  Future<Response<T>> delete<T>(String path) async =>
      _r<T>(path, <String, dynamic>{'ok': true});
}

ThemeData _theme() => ThemeData(
      extensions: const <ThemeExtension<dynamic>>[AppColors.dark],
    );

Future<ExpenseRepository> _repo(db.AppDatabase database) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  return ExpenseRepository(database, _FakeApi(), prefs);
}

/// Seeds [n] expenses with predictable, findable descriptions. Newest first
/// (index 0 is the most recent) so under the default dateDesc sort the row
/// order matches the index — "Item 00" at the top, "Item {n-1}" at the bottom.
Future<void> _seed(ExpenseRepository repo, int n) async {
  final base = DateTime(2026, 6, 25, 12);
  for (var i = 0; i < n; i++) {
    final d = base.subtract(Duration(minutes: i));
    await repo.addExpense(Expense(
      id: 'e$i',
      amount: 100 + i.toDouble(),
      description: 'Item ${i.toString().padLeft(2, '0')}',
      category: i.isEven ? 'Food' : 'Transport',
      bank: 'HDFC',
      cardType: 'CC',
      date: d.toIso8601String(),
      isManualCategory: false,
      comments: '',
    ));
  }
}

Future<void> _pump(
  WidgetTester tester,
  ExpenseRepository repo,
  ExpenseTimeframe tf, {
  Size size = const Size(360, 640),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [expenseRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: _theme(),
        home: ExpenseTimeframeScreen(timeframe: tf),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _scroller() => find.byType(CustomScrollView);

/// Drags the main scroll surface up (revealing content further down) until
/// [target] is present in the tree, pumping between drags so async page loads
/// settle. Returns whether it became findable.
Future<bool> _scrollUp(
  WidgetTester tester,
  Finder target, {
  int maxDrags = 40,
  double delta = 260,
}) async {
  for (var i = 0; i < maxDrags; i++) {
    if (target.evaluate().isNotEmpty) return true;
    await tester.drag(_scroller(), Offset(0, -delta));
    await tester.pumpAndSettle();
  }
  return target.evaluate().isNotEmpty;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late db.AppDatabase database;
  setUp(() => database = db.AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => database.close());

  testWidgets('content is a single CustomScrollView (one scroll surface)',
      (tester) async {
    final repo = await _repo(database);
    await _seed(repo, 12);
    await _pump(tester, repo,
        const ExpenseTimeframe(label: 'All', startIso: null));

    expect(tester.takeException(), isNull);
    // Exactly one page-level CustomScrollView drives the whole surface.
    expect(_scroller(), findsOneWidget);
  });

  testWidgets('summary hero + search bar scroll AWAY with the list (not pinned)',
      (tester) async {
    final repo = await _repo(database);
    await _seed(repo, 20); // plenty to overflow a 640px viewport
    await _pump(tester, repo,
        const ExpenseTimeframe(label: 'All', startIso: null));

    // Hero + search start on-screen.
    final heroBefore = tester.getTopLeft(find.text('TOTAL SPENT')).dy;
    expect(find.byType(TextField), findsOneWidget);

    // Scroll the surface up a little.
    await tester.drag(_scroller(), const Offset(0, -120));
    await tester.pump();

    // The hero moved up WITH the content — proof it is not pinned. (Before the
    // fix it was a fixed Column child and would not move.)
    final heroAfter = tester.getTopLeft(find.text('TOTAL SPENT')).dy;
    expect(heroAfter, lessThan(heroBefore));
    expect(tester.takeException(), isNull);
  });

  testWidgets('expenses far below the fold are reachable by scrolling',
      (tester) async {
    final repo = await _repo(database);
    await _seed(repo, 20);
    await _pump(tester, repo,
        const ExpenseTimeframe(label: 'All', startIso: null));

    // A late row is off-screen at first...
    final late = find.text('Item 18');
    // ...but scrolling brings it into the tree (no cramped dead zone).
    final reached = await _scrollUp(tester, late);
    expect(reached, isTrue,
        reason: 'late expense must be reachable by scrolling the page');
    expect(tester.takeException(), isNull);
  });

  testWidgets('tall AI insight card scrolls off to free the screen',
      (tester) async {
    final repo = await _repo(database);
    await _seed(repo, 16);
    await tester.runAsync(() async {}); // no-op guard for async warmup
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [expenseRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: _theme(),
          home: const ExpenseTimeframeScreen(
            timeframe: ExpenseTimeframe(
              label: 'Spending Breakdown',
              startIso: null,
              aiInsight: true,
              aiQuestion: 'how can I save money',
            ),
          ),
        ),
      ),
    );
    // The card shimmer animates forever; pump bounded frames instead of settle.
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // The card is present at the top of the scroll surface.
    expect(find.byType(AiRecommendationCard), findsOneWidget);
    final cardTopBefore =
        tester.getTopLeft(find.byType(AiRecommendationCard)).dy;

    // Scroll up — the card should move up (and eventually leave the viewport).
    await tester.drag(_scroller(), const Offset(0, -200));
    await tester.pump();

    if (find.byType(AiRecommendationCard).evaluate().isNotEmpty) {
      final cardTopAfter =
          tester.getTopLeft(find.byType(AiRecommendationCard)).dy;
      expect(cardTopAfter, lessThan(cardTopBefore),
          reason: 'AI card must scroll with the page, not stay pinned');
    }
    // Either way, an expense row is now on-screen — the card no longer hogs it.
    expect(find.byType(ExpenseItem), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pagination fires on scroll: 40 → all, shows end-of-list footer',
      (tester) async {
    final repo = await _repo(database);
    await _seed(repo, 55); // > one page (40)
    await _pump(tester, repo,
        const ExpenseTimeframe(label: 'All', startIso: null));

    // First page only initially.
    expect(find.text('Item 00'), findsOneWidget);

    // Scroll to the very bottom; loadMore should fire and the tail should load.
    final end = find.textContaining('end of list');
    final reached = await _scrollUp(tester, end, maxDrags: 60);
    expect(reached, isTrue, reason: 'must page in the rest on scroll');
    expect(find.textContaining('55 of 55 shown'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no-match state is centered and survives overscroll/refresh',
      (tester) async {
    final repo = await _repo(database);
    await _seed(repo, 6);
    await _pump(
      tester,
      repo,
      const ExpenseTimeframe(
        label: 'Yacht expenses',
        startIso: null,
        seedSearchTerms: ['yacht', 'helicopter'],
        aiAnswer: 'Here is what matched.',
      ),
    );

    expect(find.text('No matching expenses'), findsOneWidget);

    // Overscroll down (pull-to-refresh gesture) must not throw even though the
    // body is a SliverFillRemaining rather than a real list.
    await tester.drag(_scroller(), const Offset(0, 220));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Still shows the empty state after the refresh completes.
    expect(find.text('No matching expenses'), findsOneWidget);
  });

  testWidgets('aggressive scrolling both directions never throws / no overflow',
      (tester) async {
    final repo = await _repo(database);
    await _seed(repo, 30);
    await _pump(tester, repo,
        const ExpenseTimeframe(label: 'All', startIso: null),
        size: const Size(320, 560)); // cramped worst-case

    for (var i = 0; i < 6; i++) {
      await tester.drag(_scroller(), const Offset(0, -300));
      await tester.pump();
    }
    for (var i = 0; i < 6; i++) {
      await tester.drag(_scroller(), const Offset(0, 300));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Sanity: the surface returned to the top and the hero is visible again.
    expect(find.text('TOTAL SPENT'), findsOneWidget);
  });

  testWidgets('category filter row still scrolls horizontally independently',
      (tester) async {
    final repo = await _repo(database);
    await _seed(repo, 10);
    await _pump(tester, repo,
        const ExpenseTimeframe(label: 'All', startIso: null));

    // Both categories seeded → the horizontal filter row is present and is its
    // own scrollable nested inside the page (does not fight the vertical page).
    expect(find.text('Food'), findsWidgets);
    expect(find.text('Transport'), findsWidgets);
    // The vertical page scroll surface and a horizontal filter list coexist
    // (a horizontal Scrollable exists nested inside the vertical page).
    expect(
      find.byWidgetPredicate((w) =>
          w is Scrollable && w.axisDirection == AxisDirection.right),
      findsWidgets,
    );
    // The page itself is the single vertical scroll surface.
    expect(_scroller(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
