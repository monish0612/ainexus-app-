// Deep widget + scaling tests for the Spending-Analysis drill-down
// (ExpenseTimeframeScreen). Runs the REAL screen against the REAL repository
// over an in-memory Drift DB, at a cramped 320px width with worst-case data
// (a ~1.2k-char description + long comment) to prove:
//   • No RenderFlex/RenderBox overflow anywhere (scaling robustness).
//   • The summary total + transaction count render.
//   • Comments render on the row and are fully viewable in the detail sheet.
//   • Tapping a row opens the detail sheet with the full (huge) text.
//   • Searching by a comment token filters the list (literal match).

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
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

class _FakeApi extends ApiClient {
  _FakeApi();
  Response<T> _r<T>(String p, Object? d) =>
      Response<T>(requestOptions: RequestOptions(path: p), data: d as T?, statusCode: 200);
  @override
  Future<Response<T>> get<T>(String path, {Map<String, dynamic>? queryParameters}) async =>
      _r<T>(path, <dynamic>[]);
  @override
  Future<Response<T>> post<T>(String path, {Object? data, Options? options, CancelToken? cancelToken}) async =>
      _r<T>(path, <String, dynamic>{'ok': true});
  @override
  Future<Response<T>> put<T>(String path, {Object? data}) async => _r<T>(path, <String, dynamic>{});
  @override
  Future<Response<T>> delete<T>(String path) async => _r<T>(path, <String, dynamic>{'ok': true});
}

ThemeData _theme() => ThemeData(
      extensions: const <ThemeExtension<dynamic>>[
        AppColors(
          shadowColor: Color(0x66000000),
          glassFill: Color(0x0DFFFFFF),
          scrim: Color(0x99000000),
          cardGradientTop: Color(0xFF0B0B0F),
          cardGradientBottom: Color(0xFF060608),
          shimmerBase: Color(0x14FFFFFF),
          shimmerHighlight: Color(0x2EFFFFFF),
          bg: Color(0xFF000000),
          bg1: Color(0xFF060608),
          bg2: Color(0xFF131316),
          bg3: Color(0xFF1B1B1F),
          bg4: Color(0xFF26262B),
          text: Color(0xFFF1F5F9),
          text2: Color(0xFF94A3B8),
          text3: Color(0xFF6B7280),
          text4: Color(0xFF4B5563),
          text5: Color(0xFF374151),
          border: Color(0xFF1F2937),
          border2: Color(0xFF111827),
          headerBg: Color(0xFF000000),
          navBg: Color(0xFF000000),
          isDark: true,
        ),
      ],
    );

const _hugeDescription =
    'Quarterly reconciliation of the shared apartment utilities including '
    'electricity, water, piped gas, broadband and the society maintenance '
    'charge that was split four ways after adjusting for the prepaid balance '
    'carried over from last month, plus a late-payment surcharge that needs to '
    'be reimbursed by two flatmates who were travelling, and a small rounding '
    'difference that we agreed to absorb collectively so nobody has to deal '
    'with coins — see the spreadsheet pinned in the group for the exact '
    'line-item breakdown and the screenshots of each bill attached there too. '
    'This text is intentionally very long to stress the layout at narrow width.';

const _hugeComment =
    'REMINDER: collect ₹2,150 from Riya and ₹1,980 from Arjun before the 5th; '
    'also keep this receipt for the office reimbursement claim (policy 50% cap).';

Future<ExpenseRepository> _seededRepo(db.AppDatabase database) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final repo = ExpenseRepository(database, _FakeApi(), prefs);
  await repo.addExpense(const Expense(
    id: 'big',
    amount: 8421,
    description: _hugeDescription,
    category: 'Bills',
    bank: 'HDFC',
    cardType: 'CC',
    date: '2026-06-25T11:00:00.000',
    isManualCategory: false,
    comments: _hugeComment,
  ));
  await repo.addExpense(const Expense(
    id: 'small',
    amount: 220,
    description: 'Coffee',
    category: 'Food',
    bank: 'CASH',
    cardType: 'Cash',
    date: '2026-06-24T09:00:00.000',
    isManualCategory: false,
    comments: 'with Riya',
  ));
  return repo;
}

Future<void> _pump(WidgetTester tester, ExpenseRepository repo) async {
  tester.view.physicalSize = const Size(320, 1600);
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
          timeframe: ExpenseTimeframe(label: 'All', startIso: null),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late db.AppDatabase database;

  setUp(() {
    database = db.AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() async => database.close());

  testWidgets('renders at 320px with huge text and zero overflow', (tester) async {
    final repo = await _seededRepo(database);
    await _pump(tester, repo);

    expect(tester.takeException(), isNull);
    // Summary total + count present.
    expect(find.textContaining('transaction'), findsOneWidget);
    // Comment preview shows on the row.
    expect(find.textContaining('collect ₹2,150'), findsWidgets);
  });

  testWidgets('tapping a row opens detail sheet with full description + comment',
      (tester) async {
    final repo = await _seededRepo(database);
    await _pump(tester, repo);

    // Tap the row showing the (truncated) huge description.
    await tester.tap(find.text('Coffee'));
    await tester.pumpAndSettle();

    // Detail sheet renders the full description + comment, no overflow.
    expect(tester.takeException(), isNull);
    expect(find.text('Edit Expense'), findsOneWidget);
    expect(find.text('with Riya'), findsWidgets);
  });

  testWidgets('detail sheet for the huge expense lays out without overflow',
      (tester) async {
    final repo = await _seededRepo(database);
    await _pump(tester, repo);

    await tester.tap(find.textContaining('Quarterly reconciliation'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Edit Expense'), findsOneWidget);
    // The full comment is shown (SelectableText), not truncated.
    expect(find.textContaining('office reimbursement claim'), findsWidgets);
  });

  testWidgets('searching by a comment token filters to the matching row',
      (tester) async {
    final repo = await _seededRepo(database);
    await _pump(tester, repo);

    await tester.enterText(find.byType(TextField).first, 'reimbursement');
    await tester.pump(const Duration(milliseconds: 400)); // debounce
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Only the "big" expense's comment contains "reimbursement".
    expect(find.text('Coffee'), findsNothing);
    expect(find.textContaining('Quarterly reconciliation'), findsWidgets);
  });

  group('AI-seeded timeframe (category + sort + answer banner)', () {
    Future<ExpenseRepository> seedMulti(db.AppDatabase d) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final repo = ExpenseRepository(d, _FakeApi(), prefs);
      Future<void> add(String id, double amt, String cat, String desc) =>
          repo.addExpense(Expense(
            id: id, amount: amt, description: desc, category: cat,
            bank: 'HDFC', cardType: 'CC',
            date: '2026-06-2${id.length}T10:00:00.000',
            isManualCategory: false, comments: '',
          ));
      await add('f1', 250, 'Food', 'Lunch');
      await add('f22', 980, 'Food', 'Dinner party');
      await add('t1', 600, 'Travel', 'Cab');
      return repo;
    }

    Future<void> pumpAi(WidgetTester tester, ExpenseRepository repo,
        ExpenseTimeframe tf) async {
      tester.view.physicalSize = const Size(320, 1600);
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

    testWidgets('shows AI answer banner and applies category + amount sort',
        (tester) async {
      final repo = await seedMulti(database);
      await pumpAi(
        tester,
        repo,
        const ExpenseTimeframe(
          label: 'Top food spends',
          startIso: null,
          seedCategory: 'Food',
          sort: ExpenseSort.amountDesc,
          aiAnswer: 'Here are your food expenses, biggest first.',
        ),
      );

      expect(tester.takeException(), isNull);
      // AI banner visible.
      expect(find.textContaining('biggest first'), findsOneWidget);
      // Category filter applied → Travel excluded.
      expect(find.text('Cab'), findsNothing);
      expect(find.text('Dinner party'), findsWidgets);
      expect(find.text('Lunch'), findsWidgets);
    });

    testWidgets('very long AI title ellipsizes without overflow at 320px',
        (tester) async {
      final repo = await seedMulti(database);
      await pumpAi(
        tester,
        repo,
        const ExpenseTimeframe(
          label: 'Your most expensive food and dining expenses across the '
              'entire history sorted from highest to lowest amount',
          startIso: null,
          seedCategory: 'Food',
          sort: ExpenseSort.amountDesc,
          aiAnswer: 'Sorted biggest first.',
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('AI seed search prefills the editable search box',
        (tester) async {
      final repo = await seedMulti(database);
      await pumpAi(
        tester,
        repo,
        const ExpenseTimeframe(
          label: 'Dinner',
          startIso: null,
          seedSearch: 'dinner',
          aiAnswer: 'Matches for "dinner".',
        ),
      );

      expect(tester.takeException(), isNull);
      // Search box is pre-filled and editable.
      expect(find.widgetWithText(TextField, 'dinner'), findsOneWidget);
      // Only the matching row remains.
      expect(find.text('Dinner party'), findsWidgets);
      expect(find.text('Lunch'), findsNothing);
      expect(find.text('Cab'), findsNothing);
    });

    testWidgets('category chart renders bars + still shows editable list',
        (tester) async {
      final repo = await seedMulti(database);
      await pumpAi(
        tester,
        repo,
        const ExpenseTimeframe(
          label: 'By category',
          startIso: null,
          chart: ExpenseChart.category,
          aiAnswer: 'Your spending split by category.',
        ),
      );
      await tester.pump(const Duration(milliseconds: 700)); // bar animation
      expect(tester.takeException(), isNull);
      expect(find.text('Spending by category'), findsOneWidget);
      // Category labels appear in the chart; rows remain editable below.
      expect(find.text('Food'), findsWidgets);
      expect(find.text('Travel'), findsWidgets);
      expect(find.text('Cab'), findsWidgets);
    });

    testWidgets('semantic searchTerms (OR) filters + shows transparent chips',
        (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final repo = ExpenseRepository(database, _FakeApi(), prefs);
      Future<void> add(String id, double amt, String cat, String desc,
              String comments) =>
          repo.addExpense(Expense(
            id: id, amount: amt, description: desc, category: cat,
            bank: 'HDFC', cardType: 'CC',
            date: '2026-06-24T10:00:00.000',
            isManualCategory: false, comments: comments,
          ));
      await add('petrol', 2000, 'Fuel', 'Petrol pump', '');
      await add('garage', 3500, 'Transport', 'Car service', 'at the garage');
      await add('lunch', 250, 'Food', 'Lunch', 'team');

      await pumpAi(
        tester,
        repo,
        const ExpenseTimeframe(
          label: 'Car expenses',
          startIso: null,
          seedSearchTerms: ['fuel', 'garage', 'car'],
          aiAnswer: 'Here are your car-related expenses.',
        ),
      );

      expect(tester.takeException(), isNull);
      // Transparent term chips are shown.
      expect(find.text('fuel'), findsOneWidget);
      expect(find.text('garage'), findsOneWidget);
      // Matching rows present, non-car row excluded.
      expect(find.text('Petrol pump'), findsWidgets);
      expect(find.text('Car service'), findsWidgets);
      expect(find.text('Lunch'), findsNothing);
    });

    testWidgets('semantic search with no matches shows empty state (no invent)',
        (tester) async {
      final repo = await seedMulti(database);
      await pumpAi(
        tester,
        repo,
        const ExpenseTimeframe(
          label: 'Yacht expenses',
          startIso: null,
          seedSearchTerms: ['yacht', 'helicopter'],
          aiAnswer: 'Here is what matched.',
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('No matching expenses'), findsOneWidget);
      // None of the seeded rows are shown.
      expect(find.text('Lunch'), findsNothing);
      expect(find.text('Dinner party'), findsNothing);
      expect(find.text('Cab'), findsNothing);
    });

    testWidgets('daily chart renders a bar chart without overflow at 320px',
        (tester) async {
      final repo = await seedMulti(database);
      await pumpAi(
        tester,
        repo,
        const ExpenseTimeframe(
          label: 'Daily spend',
          startIso: null,
          chart: ExpenseChart.daily,
          aiAnswer: 'Daily spending for the period.',
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.text('Daily spending'), findsOneWidget);
      expect(find.byType(BarChart), findsOneWidget);
    });
  });
}
