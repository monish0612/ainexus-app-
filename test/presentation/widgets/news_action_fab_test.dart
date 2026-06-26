// Widget tests for [NewsActionFab].
//
// Specifically guards the new `clearOnly` mode that was added for the
// Movies / General chips — those chips show a single Clear-All action
// instead of the regular Summarize + Clear-All speed-dial. The contract
// these tests enforce is:
//
//   • clearOnly=true  →  Summarize row HIDDEN, scope-toggle HIDDEN,
//                        the FAB icon is the red eraser (not sparkles),
//                        and `onAction` ALWAYS fires with
//                        NewsFabScope.currentCategory even though the
//                        widget's internal `_scope` default is .all.
//   • clearOnly=false →  Existing speed-dial layout: both Summarize +
//                        Clear-All actions, scope toggle visible iff
//                        activeCategory != 'All'.
//   • FAB visibility   →  clearOnly uses `unreadCountInCategory`, the
//                        regular flow uses `unreadCount`. Either way:
//                        zero → hide.
//   • Badge / sheet copy stays category-aware so the user can never see
//     "Mark 17 as read" when only 3 General articles actually exist.
//
// Tests are pure-widget — no Riverpod, no Drift, no network. They use a
// tiny harness that pumps the FAB inside a MaterialApp with the
// production AppColors theme extension wired up.

import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/presentation/widgets/news_action_fab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';

ThemeData _testTheme() {
  return ThemeData(
    extensions: const <ThemeExtension<dynamic>>[
      AppColors(
        shadowColor: Color(0x66000000),
        glassFill: Color(0x0DFFFFFF),
        scrim: Color(0x99000000),
        cardGradientTop: Color(0xFF0B0B0F),
        cardGradientBottom: Color(0xFF060608),
        shimmerBase: Color(0x14FFFFFF),
        shimmerHighlight: Color(0x2EFFFFFF),
        bg: Color(0xFFFFFFFF),
        bg1: Color(0xFFF8F9FB),
        bg2: Color(0xFFEEF1F5),
        bg3: Color(0xFFE5E9EF),
        bg4: Color(0xFFDDE2EA),
        text: Color(0xFF101828),
        text2: Color(0xFF1F2937),
        text3: Color(0xFF374151),
        text4: Color(0xFF6B7280),
        text5: Color(0xFF94A3B8),
        border: Color(0xFFE2E8F0),
        border2: Color(0xFFCBD5E1),
        headerBg: Color(0xFFFFFFFF),
        navBg: Color(0xFFFFFFFF),
        isDark: false,
      ),
    ],
  );
}

class _Fired {
  NewsFabAction? action;
  NewsFabScope? scope;
  int count = 0;
}

Future<_Fired> _pumpFab(
  WidgetTester tester, {
  required String activeCategory,
  required int unreadCount,
  required int unreadCountInCategory,
  bool clearOnly = false,
}) async {
  final fired = _Fired();
  final colors = Theme.of(_DummyBuildContext()).extension<AppColors>() ??
      // Fallback constructor (not reachable via context — kept so a
      // stray import refactor never breaks the helper signature):
      const AppColors(
        shadowColor: Color(0x66000000),
        glassFill: Color(0x0DFFFFFF),
        scrim: Color(0x99000000),
        cardGradientTop: Color(0xFF0B0B0F),
        cardGradientBottom: Color(0xFF060608),
        shimmerBase: Color(0x14FFFFFF),
        shimmerHighlight: Color(0x2EFFFFFF),
        bg: Color(0xFFFFFFFF),
        bg1: Color(0xFFF8F9FB),
        bg2: Color(0xFFEEF1F5),
        bg3: Color(0xFFE5E9EF),
        bg4: Color(0xFFDDE2EA),
        text: Color(0xFF101828),
        text2: Color(0xFF1F2937),
        text3: Color(0xFF374151),
        text4: Color(0xFF6B7280),
        text5: Color(0xFF94A3B8),
        border: Color(0xFFE2E8F0),
        border2: Color(0xFFCBD5E1),
        headerBg: Color(0xFFFFFFFF),
        navBg: Color(0xFFFFFFFF),
        isDark: false,
      );

  await tester.pumpWidget(
    MaterialApp(
      theme: _testTheme(),
      home: Scaffold(
        body: SizedBox.expand(
          child: NewsActionFab(
            colors: colors,
            unreadCount: unreadCount,
            unreadCountInCategory: unreadCountInCategory,
            activeCategory: activeCategory,
            clearOnly: clearOnly,
            onAction: (action, scope) {
              fired.action = action;
              fired.scope = scope;
              fired.count++;
            },
          ),
        ),
      ),
    ),
  );
  // Two pumps — one for layout, one for the pulse animation tick that
  // the FAB starts in initState. pumpAndSettle would loop forever
  // because the pulse animation is `repeat(reverse: true)`.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return fired;
}

// Helper used only by `_pumpFab` to keep the helper signature compact.
// We never actually use it for context lookups — see comment above.
class _DummyBuildContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

/// Opens the speed-dial sheet by tapping the FAB and waits for the
/// expansion animation (~280 ms) to finish.
Future<void> _openSheet(WidgetTester tester) async {
  // The FAB pulse runs forever so we cannot use pumpAndSettle. Tap the
  // FAB and pump enough frames to cover the 280 ms expansion animation.
  await tester.tap(find.byIcon(LucideIcons.sparkles).hitTestable().first);
  // Multiple pumps to drive the expand animation past 1.0 deterministically.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _openClearOnlySheet(WidgetTester tester) async {
  await tester.tap(find.byIcon(LucideIcons.eraser).hitTestable().first);
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NewsActionFab — visibility', () {
    testWidgets('hides when unreadCount == 0 (regular mode)',
        (tester) async {
      await _pumpFab(
        tester,
        activeCategory: 'All',
        unreadCount: 0,
        unreadCountInCategory: 0,
      );
      expect(find.byIcon(LucideIcons.sparkles), findsNothing);
      expect(find.byIcon(LucideIcons.eraser), findsNothing);
    });

    testWidgets(
        'hides when unreadCountInCategory == 0 (clearOnly mode), '
        'EVEN IF unreadCount > 0 cross-category', (tester) async {
      // The bug guard: All-pile excludes Movies/General, so an outer
      // unreadCount of 12 (from Finance/AI News) MUST NOT keep the
      // FAB visible on an empty Movies feed.
      await _pumpFab(
        tester,
        activeCategory: 'Movies',
        unreadCount: 12,
        unreadCountInCategory: 0,
        clearOnly: true,
      );
      expect(find.byIcon(LucideIcons.sparkles), findsNothing);
      expect(find.byIcon(LucideIcons.eraser), findsNothing);
    });

    testWidgets(
        'shows clearOnly FAB when unreadCountInCategory > 0 even if '
        'unreadCount (cross-category) is 0', (tester) async {
      // Inverse of the above: All-pile is empty, but Movies has 3.
      // The Movies chip MUST show its red eraser FAB.
      await _pumpFab(
        tester,
        activeCategory: 'Movies',
        unreadCount: 0,
        unreadCountInCategory: 3,
        clearOnly: true,
      );
      expect(find.byIcon(LucideIcons.eraser), findsOneWidget);
      expect(find.byIcon(LucideIcons.sparkles), findsNothing);
    });

    testWidgets('shows regular sparkles FAB when unreadCount > 0',
        (tester) async {
      await _pumpFab(
        tester,
        activeCategory: 'All',
        unreadCount: 5,
        unreadCountInCategory: 5,
      );
      expect(find.byIcon(LucideIcons.sparkles), findsOneWidget);
      expect(find.byIcon(LucideIcons.eraser), findsNothing);
    });
  });

  group('NewsActionFab — clearOnly sheet contents', () {
    testWidgets('Movies clearOnly: shows ONLY Clear All (no Summarize)',
        (tester) async {
      await _pumpFab(
        tester,
        activeCategory: 'Movies',
        unreadCount: 0,
        unreadCountInCategory: 3,
        clearOnly: true,
      );
      await _openClearOnlySheet(tester);

      // Clear All visible
      expect(find.text('Clear All'), findsOneWidget);
      // Summarize is HIDDEN
      expect(find.text('Summarize'), findsNothing);
    });

    testWidgets('General clearOnly: shows ONLY Clear All (no Summarize)',
        (tester) async {
      await _pumpFab(
        tester,
        activeCategory: 'General',
        unreadCount: 0,
        unreadCountInCategory: 7,
        clearOnly: true,
      );
      await _openClearOnlySheet(tester);

      expect(find.text('Clear All'), findsOneWidget);
      expect(find.text('Summarize'), findsNothing);
    });

    testWidgets('clearOnly: scope toggle is HIDDEN', (tester) async {
      await _pumpFab(
        tester,
        activeCategory: 'Movies',
        unreadCount: 0,
        unreadCountInCategory: 3,
        clearOnly: true,
      );
      await _openClearOnlySheet(tester);

      // The "All categories" segment of the scope toggle MUST NOT appear.
      expect(find.text('All categories'), findsNothing);
    });

    testWidgets('clearOnly subtitle is category-aware', (tester) async {
      await _pumpFab(
        tester,
        activeCategory: 'Movies',
        unreadCount: 0,
        unreadCountInCategory: 4,
        clearOnly: true,
      );
      await _openClearOnlySheet(tester);

      expect(find.text('Remove 4 articles from Movies'), findsOneWidget);
    });

    testWidgets('clearOnly subtitle handles singular vs plural',
        (tester) async {
      await _pumpFab(
        tester,
        activeCategory: 'General',
        unreadCount: 0,
        unreadCountInCategory: 1,
        clearOnly: true,
      );
      await _openClearOnlySheet(tester);

      expect(find.text('Remove 1 article from General'), findsOneWidget);
    });

    testWidgets('clearOnly footer tip mentions swipe-to-delete',
        (tester) async {
      await _pumpFab(
        tester,
        activeCategory: 'Movies',
        unreadCount: 0,
        unreadCountInCategory: 2,
        clearOnly: true,
      );
      await _openClearOnlySheet(tester);

      // The footer tip must educate the user that the swipe affordance
      // exists — without this, users who want to keep some articles
      // would think Clear All is their only option.
      expect(
        find.textContaining('swipe a card left or right'),
        findsOneWidget,
      );
      // The regular-mode tip is NOT shown in clearOnly mode.
      expect(find.text('Saved articles are never touched'), findsNothing);
    });
  });

  group('NewsActionFab — regular (non-clearOnly) sheet contents', () {
    testWidgets('All chip: shows BOTH Summarize and Clear All',
        (tester) async {
      await _pumpFab(
        tester,
        activeCategory: 'All',
        unreadCount: 8,
        unreadCountInCategory: 8,
      );
      await _openSheet(tester);

      expect(find.text('Summarize'), findsOneWidget);
      expect(find.text('Clear All'), findsOneWidget);
    });

    testWidgets('All chip: scope toggle is HIDDEN (no category selected)',
        (tester) async {
      await _pumpFab(
        tester,
        activeCategory: 'All',
        unreadCount: 8,
        unreadCountInCategory: 8,
      );
      await _openSheet(tester);

      expect(find.text('All categories'), findsNothing);
    });

    testWidgets('Finance chip: scope toggle IS visible', (tester) async {
      await _pumpFab(
        tester,
        activeCategory: 'Finance',
        unreadCount: 8,
        unreadCountInCategory: 3,
      );
      await _openSheet(tester);

      // Both segments of the toggle render.
      expect(find.text('All categories'), findsOneWidget);
      expect(find.text('Finance'), findsOneWidget);
    });

    testWidgets('AI News chip: scope toggle IS visible', (tester) async {
      await _pumpFab(
        tester,
        activeCategory: 'AI News',
        unreadCount: 8,
        unreadCountInCategory: 3,
      );
      await _openSheet(tester);

      expect(find.text('All categories'), findsOneWidget);
      expect(find.text('AI News'), findsOneWidget);
    });

    testWidgets('regular subtitle reads "Mark N as read"', (tester) async {
      await _pumpFab(
        tester,
        activeCategory: 'All',
        unreadCount: 5,
        unreadCountInCategory: 5,
      );
      await _openSheet(tester);

      // The regular-mode Clear-All subtitle is "Mark N as read", NOT the
      // category-scoped "Remove N article(s) from <Category>" wording.
      expect(find.text('Mark 5 as read'), findsOneWidget);
    });

    testWidgets('regular footer reminds about saved articles', (tester) async {
      await _pumpFab(
        tester,
        activeCategory: 'All',
        unreadCount: 5,
        unreadCountInCategory: 5,
      );
      await _openSheet(tester);

      expect(find.text('Saved articles are never touched'), findsOneWidget);
    });
  });

  group('NewsActionFab — onAction scope contract', () {
    testWidgets(
        'clearOnly: Clear-All fires with scope=currentCategory '
        '(ignoring _scope default)', (tester) async {
      final fired = await _pumpFab(
        tester,
        activeCategory: 'Movies',
        unreadCount: 0,
        unreadCountInCategory: 3,
        clearOnly: true,
      );
      await _openClearOnlySheet(tester);
      await tester.tap(find.text('Clear All'));
      // 220 ms close-animation delay before the action fires.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(fired.count, 1);
      expect(fired.action, NewsFabAction.clearAll);
      expect(fired.scope, NewsFabScope.currentCategory);
    });

    testWidgets(
        'regular All chip: Clear-All fires with scope=all (default)',
        (tester) async {
      final fired = await _pumpFab(
        tester,
        activeCategory: 'All',
        unreadCount: 4,
        unreadCountInCategory: 4,
      );
      await _openSheet(tester);
      await tester.tap(find.text('Clear All'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(fired.count, 1);
      expect(fired.action, NewsFabAction.clearAll);
      expect(fired.scope, NewsFabScope.all);
    });

    testWidgets(
        'regular Finance chip with user-picked currentCategory scope '
        'fires with .currentCategory', (tester) async {
      final fired = await _pumpFab(
        tester,
        activeCategory: 'Finance',
        unreadCount: 6,
        unreadCountInCategory: 2,
      );
      await _openSheet(tester);
      // Pick the "Finance" segment of the scope toggle to flip the
      // internal _scope from .all → .currentCategory.
      await tester.tap(find.text('Finance'));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('Clear All'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(fired.count, 1);
      expect(fired.scope, NewsFabScope.currentCategory);
    });
  });

  group('NewsActionFab — _scopeCount math', () {
    testWidgets(
        'clearOnly: subtitle count uses unreadCountInCategory, '
        'NEVER the cross-category unreadCount', (tester) async {
      // Regression guard for the original bug: Movies chip with 3 local
      // articles must show "Remove 3", NOT "Remove 17" from the global
      // pile.
      await _pumpFab(
        tester,
        activeCategory: 'Movies',
        unreadCount: 17,
        unreadCountInCategory: 3,
        clearOnly: true,
      );
      await _openClearOnlySheet(tester);

      expect(find.text('Remove 3 articles from Movies'), findsOneWidget);
      expect(find.textContaining('17'), findsNothing);
    });
  });
}
