import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/presentation/widgets/app_shell.dart';

/// Unit tests for [resolveShortcutRoute] — the pure routing decision behind
/// the home-screen search widget (Expense ⇄ Web toggle), app shortcuts, and
/// the legacy search widget. No widgets are pumped; this locks the logic.
void main() {
  group('resolveShortcutRoute — search widget (Expense mode)', () {
    test('opens Expense Ask AI on tab 0, no web focus', () {
      final r = resolveShortcutRoute({
        'tab': '0',
        'widget_search_mode': 'expense',
      })!;
      expect(r.tab, 0);
      expect(r.openExpenseSearch, isTrue);
      expect(r.focusWebSearch, isFalse);
      expect(r.subtab, isNull);
    });

    test('expense mode wins even if widget_launch is also set', () {
      // Guards against a stale/extra flag double-triggering both searches.
      final r = resolveShortcutRoute({
        'tab': '0',
        'widget_search_mode': 'expense',
        'widget_launch': 'true',
      })!;
      expect(r.openExpenseSearch, isTrue);
      expect(r.focusWebSearch, isFalse);
    });
  });

  group('resolveShortcutRoute — Expense widget "Add" pill', () {
    test('opens the Add-expense sheet on tab 0, no search focus', () {
      final r = resolveShortcutRoute({
        'tab': '0',
        'expense_action': 'add',
      })!;
      expect(r.tab, 0);
      expect(r.openExpenseAdd, isTrue);
      expect(r.openExpenseSearch, isFalse);
      expect(r.focusWebSearch, isFalse);
    });

    test('add wins over a stray widget_launch flag (no double-trigger)', () {
      final r = resolveShortcutRoute({
        'tab': '0',
        'expense_action': 'add',
        'widget_launch': 'true',
      })!;
      expect(r.openExpenseAdd, isTrue);
      expect(r.focusWebSearch, isFalse);
    });

    test('non-"add" expense_action does not open the Add sheet', () {
      final r = resolveShortcutRoute({
        'tab': '0',
        'expense_action': 'edit',
      })!;
      expect(r.openExpenseAdd, isFalse);
    });
  });

  group('resolveShortcutRoute — search widget (Web mode)', () {
    test('focuses online search on Tutor tab + Summarizer subtab', () {
      final r = resolveShortcutRoute({
        'tab': '2',
        'subtab': '0',
        'widget_launch': 'true',
        'widget_search_mode': 'web',
      })!;
      expect(r.tab, 2);
      expect(r.subtab, 0);
      expect(r.openExpenseSearch, isFalse);
      expect(r.focusWebSearch, isTrue);
    });

    test('web mode without widget_launch does not focus search', () {
      final r = resolveShortcutRoute({
        'tab': '2',
        'subtab': '0',
        'widget_search_mode': 'web',
      })!;
      expect(r.openExpenseSearch, isFalse);
      expect(r.focusWebSearch, isFalse);
    });
  });

  group('resolveShortcutRoute — legacy search widget (no mode key)', () {
    test('still focuses web search via widget_launch (backward compatible)', () {
      final r = resolveShortcutRoute({
        'tab': '2',
        'subtab': '0',
        'widget_launch': 'true',
      })!;
      expect(r.tab, 2);
      expect(r.subtab, 0);
      expect(r.openExpenseSearch, isFalse);
      expect(r.focusWebSearch, isTrue);
    });
  });

  group('resolveShortcutRoute — plain app shortcuts (no widget keys)', () {
    test('navigates to a tab without triggering any search', () {
      final r = resolveShortcutRoute({'tab': '1'})!;
      expect(r.tab, 1);
      expect(r.subtab, isNull);
      expect(r.openExpenseSearch, isFalse);
      expect(r.focusWebSearch, isFalse);
    });

    test('forwards a tutor subtab', () {
      final r = resolveShortcutRoute({'tab': '2', 'subtab': '3'})!;
      expect(r.tab, 2);
      expect(r.subtab, 3);
    });
  });

  group('resolveShortcutRoute — invalid / edge cases (return null)', () {
    test('missing tab', () {
      expect(resolveShortcutRoute({'widget_search_mode': 'expense'}), isNull);
    });

    test('empty tab', () {
      expect(resolveShortcutRoute({'tab': ''}), isNull);
    });

    test('non-numeric tab', () {
      expect(resolveShortcutRoute({'tab': 'abc'}), isNull);
    });

    test('negative tab', () {
      expect(resolveShortcutRoute({'tab': '-1'}), isNull);
    });

    test('out-of-range tab', () {
      expect(resolveShortcutRoute({'tab': '4'}), isNull);
      expect(resolveShortcutRoute({'tab': '99'}), isNull);
    });

    test('all four valid tabs resolve', () {
      for (var i = 0; i <= 3; i++) {
        expect(resolveShortcutRoute({'tab': '$i'})?.tab, i);
      }
    });
  });

  group('resolveShortcutRoute — malformed sub-values are tolerated', () {
    test('garbage subtab parses to null (ignored)', () {
      final r = resolveShortcutRoute({'tab': '2', 'subtab': 'xyz'})!;
      expect(r.subtab, isNull);
    });

    test('mode values other than expense are treated as non-expense', () {
      expect(
        resolveShortcutRoute({'tab': '0', 'widget_search_mode': 'EXPENSE'})!
            .openExpenseSearch,
        isFalse,
      );
      expect(
        resolveShortcutRoute({'tab': '0', 'widget_search_mode': 'garbage'})!
            .openExpenseSearch,
        isFalse,
      );
    });

    test('widget_launch only counts for the exact string "true"', () {
      expect(
        resolveShortcutRoute({'tab': '2', 'widget_launch': 'TRUE'})!
            .focusWebSearch,
        isFalse,
      );
      expect(
        resolveShortcutRoute({'tab': '2', 'widget_launch': '1'})!
            .focusWebSearch,
        isFalse,
      );
    });
  });
}
