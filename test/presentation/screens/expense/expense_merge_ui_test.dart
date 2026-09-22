import 'package:ai_nexus/core/services/expense_merge.dart';
import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/core/utils/currency_formatter.dart';
import 'package:ai_nexus/data/services/user_preferences_service.dart';
import 'package:ai_nexus/domain/entities/expense_entities.dart';
import 'package:ai_nexus/presentation/screens/expense/modals/merge_expenses_modal.dart';
import 'package:ai_nexus/presentation/screens/expense/widgets/expense_item.dart';
import 'package:ai_nexus/presentation/screens/expense/widgets/expense_merge_bar.dart';
import 'package:ai_nexus/presentation/screens/expense/widgets/tracker_tab.dart';
import 'package:ai_nexus/presentation/screens/settings/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeRemote implements UserPreferencesService {
  @override
  Future<Map<String, String>?> fetchAll() async => null;
  @override
  Future<bool> pushBatch(Map<String, String> entries) async => true;
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
          modeLite: Color(0xFF22D3EE),
          modeDeep: Color(0xFF8B5CF6),
          modeThinking: Color(0xFFF5B62C),
          providerXgrok: Color(0xFF94A3B8),
          accentText: Color(0xFF5B8CFF),
          danger: Color(0xFFEF4444),
          warning: Color(0xFFF59E0B),
          success: Color(0xFF34D399),
          isDark: true,
        ),
      ],
    );

ExpenseData _row({
  required String id,
  required String description,
  required double amount,
  required DateTime date,
}) =>
    ExpenseData(
      id: id,
      amount: amount,
      description: description,
      category: 'Others',
      bank: 'HDFC',
      cardType: 'CC',
      date: date.toIso8601String(),
      comments: 'Auto Detected · 19 Sep 2026, 11:18 AM',
    );

Future<void> _pumpTracker(
  WidgetTester tester,
  List<ExpenseData> expenses, {
  void Function(List<ExpenseData> selected)? onMerge,
}) async {
  tester.view.physicalSize = const Size(400, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsController(prefs, _FakeRemote());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [settingsProvider.overrideWith((ref) => settings)],
      child: MaterialApp(
        theme: _theme(),
        home: Scaffold(
          body: TrackerTab(
            expenses: expenses,
            budget: 50000,
            budgetHistory: const [],
            learnings: const {},
            onAddExpense: () {},
            onDeleteExpense: (_) {},
            onUpdateExpense: (_) {},
            onSetBudget: () {},
            onUpdateLearnings: () {},
            onEditExpense: (_) {},
            onShowBudgetHistory: () {},
            onOpenTimeframe: (_) {},
            onMergeExpenses: onMerge,
            clock: DateTime(2026, 9, 19, 12, 41),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 1200));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('en_IN');
  });

  testWidgets('merge button is hidden for one selected row', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme(),
        home: const Scaffold(
          body: ExpenseMergeActionBar(
            selectedCount: 1,
            total: 60,
            onMerge: _noop,
            onCancel: _noop,
          ),
        ),
      ),
    );
    expect(find.byKey(kExpenseMergeBarKey), findsOneWidget);
    expect(find.byKey(kExpenseMergeSubmitKey), findsNothing);
    expect(find.text('Select one more to merge'), findsOneWidget);
    expect(find.text('Merge'), findsNothing);
  });

  testWidgets('merge button appears only when 2+ rows are selected',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme(),
        home: Scaffold(
          body: ExpenseMergeActionBar(
            selectedCount: 2,
            total: 97,
            onMerge: _noop,
            onCancel: _noop,
          ),
        ),
      ),
    );
    expect(find.byKey(kExpenseMergeSubmitKey), findsOneWidget);
    expect(find.text('Merge'), findsOneWidget);
    expect(find.textContaining(formatCurrency(97)), findsOneWidget);
  });

  testWidgets('long-press enters checkbox select; one row has no Merge',
      (tester) async {
    final now = DateTime(2026, 9, 19, 11, 18);
    await _pumpTracker(tester, [
      _row(
        id: 'a',
        description: 'paytmqr16ii90sd2y@paytm',
        amount: 60,
        date: now,
      ),
      _row(
        id: 'b',
        description: '99440213809@okbizaxis',
        amount: 37,
        date: now.subtract(const Duration(minutes: 1)),
      ),
    ], onMerge: (_) {});

    expect(find.byKey(kExpenseMergeBarKey), findsNothing);
    expect(find.textContaining('swipe to edit'), findsOneWidget);

    await tester.ensureVisible(find.text('paytmqr16ii90sd2y@paytm'));
    await tester.longPress(find.text('paytmqr16ii90sd2y@paytm'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(kExpenseMergeBarKey), findsOneWidget);
    expect(find.byKey(kExpenseMergeSubmitKey), findsNothing);
    expect(find.byKey(const ValueKey('merge-check-a')), findsOneWidget);
    expect(find.text('Select one more to merge'), findsOneWidget);
    expect(find.textContaining('tap to select'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('second tap enables Merge and reports both rows', (tester) async {
    final now = DateTime(2026, 9, 19, 11, 18);
    List<ExpenseData>? captured;
    await _pumpTracker(
      tester,
      [
        _row(
          id: 'a',
          description: 'paytmqr16ii90sd2y@paytm',
          amount: 60,
          date: now,
        ),
        _row(
          id: 'b',
          description: '99440213809@okbizaxis',
          amount: 37,
          date: now.subtract(const Duration(minutes: 1)),
        ),
      ],
      onMerge: (rows) => captured = rows,
    );

    await tester.ensureVisible(find.text('paytmqr16ii90sd2y@paytm'));
    await tester.longPress(find.text('paytmqr16ii90sd2y@paytm'));
    await tester.pump();
    await tester.drag(find.byKey(const ValueKey('tracker-main-scroll')), const Offset(0, -220));
    await tester.pump();
    await tester.tap(find.text('99440213809@okbizaxis'));
    await tester.pump();

    expect(find.byKey(kExpenseMergeSubmitKey), findsOneWidget);
    expect(find.text('2 selected'), findsOneWidget);
    await tester.tap(find.byKey(kExpenseMergeSubmitKey));
    await tester.pump();
    expect(captured, isNotNull);
    expect(captured!.map((e) => e.id).toSet(), {'a', 'b'});
    expect(
      captured!.fold<double>(0, (s, e) => s + e.amount),
      97,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel exits selection and restores swipe rows', (tester) async {
    final now = DateTime(2026, 9, 19, 11, 18);
    await _pumpTracker(tester, [
      _row(
        id: 'a',
        description: 'Paytm',
        amount: 30,
        date: now,
      ),
      _row(
        id: 'b',
        description: 'gpay-12198000736@okbizaxi',
        amount: 80,
        date: now,
      ),
    ], onMerge: (_) {});

    await tester.ensureVisible(find.text('Paytm'));
    await tester.longPress(find.text('Paytm'));
    await tester.pump();
    expect(find.byKey(kExpenseMergeBarKey), findsOneWidget);

    await tester.tap(find.byTooltip('Cancel'));
    await tester.pump();
    expect(find.byKey(kExpenseMergeBarKey), findsNothing);
    expect(find.byKey(const ValueKey('merge-check-a')), findsNothing);
    expect(find.textContaining('swipe to edit'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without a merge callback, long-press does not select',
      (tester) async {
    final now = DateTime(2026, 9, 19, 11, 18);
    await _pumpTracker(tester, [
      _row(id: 'a', description: 'Coffee', amount: 20, date: now),
      _row(id: 'b', description: 'Lunch', amount: 40, date: now),
    ]);

    await tester.ensureVisible(find.text('Coffee'));
    await tester.longPress(find.text('Coffee'));
    await tester.pump();
    expect(find.byKey(kExpenseMergeBarKey), findsNothing);
    expect(find.byKey(const ValueKey('merge-check-a')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('merge sheet shows the summed total and saves a composed row',
      (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final plan = planExpenseMerge([
      Expense(
        id: 'a',
        amount: 60,
        description: 'paytmqr16ii90sd2y@paytm',
        category: 'Others',
        bank: 'HDFC',
        cardType: 'CC',
        date: '2026-09-19T11:18:00.000',
        isManualCategory: false,
      ),
      Expense(
        id: 'b',
        amount: 37,
        description: '99440213809@okbizaxis',
        category: 'Others',
        bank: 'HDFC',
        cardType: 'CC',
        date: '2026-09-19T10:18:00.000',
        isManualCategory: false,
      ),
    ]);

    Expense? saved;
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                saved = await showMergeExpensesModal(
                  context,
                  plan: plan,
                  mergedId: 'merged-1',
                );
              },
              child: const Text('open-merge'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open-merge'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('MERGE EXPENSES'), findsOneWidget);
    expect(find.byKey(const ValueKey('expense_merge_total')), findsOneWidget);
    expect(find.textContaining(formatCurrency(97)), findsWidgets);
    expect(find.text('2 transactions combined'), findsOneWidget);
    expect(find.text('BANK'), findsOneWidget);
    expect(find.text('PAYMENT TYPE'), findsOneWidget);
    expect(find.text('COMMENTS'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Danalashmi Flower Shop');
    await tester.ensureVisible(find.byKey(kExpenseMergeSaveKey));
    await tester.tap(find.byKey(kExpenseMergeSaveKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(saved, isNotNull);
    expect(saved!.id, 'merged-1');
    expect(saved!.amount, 97);
    expect(saved!.description, 'Danalashmi Flower Shop');
    expect(saved!.bank, 'HDFC');
    expect(saved!.cardType, 'CC');
    expect(saved!.comments, isEmpty);
    expect(saved!.isManualCategory, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('system back / swipe-back leaves checkbox mode', (tester) async {
    var canceled = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme(),
        home: ExpenseSelectionScope(
          active: true,
          onCancel: () => canceled = true,
          child: const Scaffold(body: Text('selecting')),
        ),
      ),
    );
    expect(find.text('selecting'), findsOneWidget);
    final nav = Navigator.of(tester.element(find.text('selecting')));
    // Flutter returns true for a handled back even when the route does not pop.
    expect(await nav.maybePop(), isTrue);
    expect(canceled, isTrue);
    expect(find.text('selecting'), findsOneWidget);
  });

  testWidgets('swipe-right on a selected row exits checkbox mode',
      (tester) async {
    var exited = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme(),
        home: Scaffold(
          body: ExpenseItem(
            key: const ValueKey('expense-row-a'),
            expense: _row(
              id: 'a',
              description: 'Paytm',
              amount: 30,
              date: DateTime(2026, 9, 19, 11, 18),
            ),
            onEdit: _noop,
            onDelete: _noop,
            selectionMode: true,
            selected: true,
            onToggleSelect: _noop,
            onExitSelection: () => exited = true,
          ),
        ),
      ),
    );
    await tester.drag(
      find.byKey(const ValueKey('expense-row-a')),
      const Offset(90, 0),
    );
    await tester.pump();
    expect(exited, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unchecking the last row exits checkbox mode', (tester) async {
    final now = DateTime(2026, 9, 19, 11, 18);
    await _pumpTracker(tester, [
      _row(id: 'a', description: 'Paytm', amount: 30, date: now),
      _row(id: 'b', description: 'gpay-row', amount: 80, date: now),
    ], onMerge: (_) {});

    await tester.ensureVisible(find.text('Paytm'));
    await tester.longPress(find.text('Paytm'));
    await tester.pump();
    expect(find.byKey(kExpenseMergeBarKey), findsOneWidget);

    await tester.tap(find.text('Paytm'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byKey(kExpenseMergeBarKey), findsNothing);
    expect(find.byKey(const ValueKey('merge-check-a')), findsNothing);
    expect(find.textContaining('swipe to edit'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tracker swipe-back while selecting restores swipe rows',
      (tester) async {
    final now = DateTime(2026, 9, 19, 11, 18);
    await _pumpTracker(tester, [
      _row(id: 'a', description: 'Paytm', amount: 30, date: now),
      _row(id: 'b', description: 'gpay-row', amount: 80, date: now),
    ], onMerge: (_) {});

    await tester.ensureVisible(find.text('Paytm'));
    await tester.longPress(find.text('Paytm'));
    await tester.pump();
    expect(find.byKey(kExpenseMergeBarKey), findsOneWidget);
    expect(find.textContaining('swipe back to exit'), findsOneWidget);

    final nav = Navigator.of(tester.element(find.byType(TrackerTab)));
    expect(await nav.maybePop(), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byKey(kExpenseMergeBarKey), findsNothing);
    expect(find.byKey(const ValueKey('merge-check-a')), findsNothing);
    expect(find.textContaining('swipe to edit'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('zero selected has no Merge; three selected shows the full total',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme(),
        home: const Scaffold(
          body: ExpenseMergeActionBar(
            selectedCount: 0,
            total: 0,
            onMerge: _noop,
            onCancel: _noop,
          ),
        ),
      ),
    );
    expect(find.byKey(kExpenseMergeSubmitKey), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        theme: _theme(),
        home: Scaffold(
          body: ExpenseMergeActionBar(
            selectedCount: 6,
            total: 267,
            onMerge: _noop,
            onCancel: _noop,
          ),
        ),
      ),
    );
    expect(find.byKey(kExpenseMergeSubmitKey), findsOneWidget);
    expect(find.text('6 selected'), findsOneWidget);
    expect(find.textContaining(formatCurrency(267)), findsOneWidget);
  });

  testWidgets('swipe left in checkbox mode does not exit', (tester) async {
    var exited = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme(),
        home: Scaffold(
          body: ExpenseItem(
            key: const ValueKey('expense-row-a'),
            expense: _row(
              id: 'a',
              description: 'Paytm',
              amount: 30,
              date: DateTime(2026, 9, 19, 11, 18),
            ),
            onEdit: _noop,
            onDelete: _noop,
            selectionMode: true,
            selected: true,
            onToggleSelect: _noop,
            onExitSelection: () => exited = true,
          ),
        ),
      ),
    );
    await tester.drag(
      find.byKey(const ValueKey('expense-row-a')),
      const Offset(-90, 0),
    );
    await tester.pump();
    expect(exited, isFalse);
    expect(find.byKey(const ValueKey('merge-check-a')), findsOneWidget);
  });

  testWidgets('a tiny swipe right does not exit checkbox mode', (tester) async {
    var exited = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme(),
        home: Scaffold(
          body: ExpenseItem(
            key: const ValueKey('expense-row-a'),
            expense: _row(
              id: 'a',
              description: 'Paytm',
              amount: 30,
              date: DateTime(2026, 9, 19, 11, 18),
            ),
            onEdit: _noop,
            onDelete: _noop,
            selectionMode: true,
            selected: true,
            onToggleSelect: _noop,
            onExitSelection: () => exited = true,
          ),
        ),
      ),
    );
    await tester.timedDrag(
      find.byKey(const ValueKey('expense-row-a')),
      const Offset(18, 0),
      const Duration(milliseconds: 700),
    );
    await tester.pump();
    expect(exited, isFalse);
  });

  testWidgets('selection mode hides swipe edit/delete chrome', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme(),
        home: Scaffold(
          body: ExpenseItem(
            expense: _row(
              id: 'a',
              description: 'Paytm',
              amount: 30,
              date: DateTime(2026, 9, 19, 11, 18),
            ),
            onEdit: _noop,
            onDelete: _noop,
            selectionMode: true,
            selected: true,
            onToggleSelect: _noop,
            onExitSelection: _noop,
          ),
        ),
      ),
    );
    expect(find.text('EDIT'), findsNothing);
    expect(find.text('DELETE'), findsNothing);
    expect(find.byKey(const ValueKey('merge-check-a')), findsOneWidget);
  });

  testWidgets('inactive selection scope does not steal system back',
      (tester) async {
    var canceled = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ExpenseSelectionScope(
                      active: false,
                      onCancel: () => canceled = true,
                      child: const Scaffold(body: Text('child-page')),
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('child-page'), findsOneWidget);

    final nav = Navigator.of(tester.element(find.text('child-page')));
    expect(await nav.maybePop(), isTrue);
    await tester.pumpAndSettle();

    expect(canceled, isFalse);
    expect(find.text('open'), findsOneWidget);
    expect(find.text('child-page'), findsNothing);
  });

  testWidgets('empty merge description stays on the sheet', (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final plan = planExpenseMerge([
      Expense(
        id: 'a',
        amount: 10,
        description: 'a',
        category: 'Others',
        bank: 'HDFC',
        cardType: 'CC',
        date: '2026-09-19T11:18:00.000',
        isManualCategory: false,
      ),
      Expense(
        id: 'b',
        amount: 10,
        description: 'b',
        category: 'Others',
        bank: 'HDFC',
        cardType: 'CC',
        date: '2026-09-19T10:18:00.000',
        isManualCategory: false,
      ),
    ]);
    Expense? saved;
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                saved = await showMergeExpensesModal(
                  context,
                  plan: plan,
                  mergedId: 'merged-1',
                );
              },
              child: const Text('open-merge'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open-merge'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.byKey(kExpenseMergeSaveKey));
    await tester.tap(find.byKey(kExpenseMergeSaveKey));
    await tester.pump();
    expect(saved, isNull);
    expect(find.text('Enter a description'), findsOneWidget);
    expect(find.text('MERGE EXPENSES'), findsOneWidget);
  });

  testWidgets('handlePopRoute while selecting does not pop Tracker',
      (tester) async {
    final now = DateTime(2026, 9, 19, 11, 18);
    await _pumpTracker(tester, [
      _row(id: 'a', description: 'Paytm', amount: 30, date: now),
      _row(id: 'b', description: 'gpay-row', amount: 80, date: now),
    ], onMerge: (_) {});

    await tester.ensureVisible(find.text('Paytm'));
    await tester.longPress(find.text('Paytm'));
    await tester.pump();
    expect(find.byKey(kExpenseMergeBarKey), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(TrackerTab), findsOneWidget);
    expect(find.byKey(kExpenseMergeBarKey), findsNothing);
    expect(find.text('Paytm'), findsOneWidget);
    expect(find.textContaining('swipe to edit'), findsOneWidget);
  });

  testWidgets('GoRouter system back exits checkbox mode without popping',
      (tester) async {
    tester.view.physicalSize = const Size(400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsController(prefs, _FakeRemote());
    final now = DateTime(2026, 9, 19, 11, 18);
    final expenses = [
      _row(id: 'a', description: 'Paytm', amount: 30, date: now),
      _row(id: 'b', description: 'gpay-row', amount: 80, date: now),
    ];
    final router = GoRouter(
      initialLocation: '/tracker',
      routes: [
        GoRoute(
          path: '/tracker',
          builder: (context, state) => Scaffold(
            body: TrackerTab(
              expenses: expenses,
              budget: 50000,
              budgetHistory: const [],
              learnings: const {},
              onAddExpense: () {},
              onDeleteExpense: (_) {},
              onUpdateExpense: (_) {},
              onSetBudget: () {},
              onUpdateLearnings: () {},
              onEditExpense: (_) {},
              onShowBudgetHistory: () {},
              onOpenTimeframe: (_) {},
              onMergeExpenses: (_) {},
              clock: DateTime(2026, 9, 19, 12, 41),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsProvider.overrideWith((ref) => settings)],
        child: MaterialApp.router(
          theme: _theme(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump();

    await tester.ensureVisible(find.text('Paytm'));
    await tester.longPress(find.text('Paytm'));
    await tester.pump();
    expect(find.byKey(kExpenseMergeBarKey), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/tracker');

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(TrackerTab), findsOneWidget);
    expect(find.byKey(kExpenseMergeBarKey), findsNothing);
    expect(find.text('Paytm'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/tracker');
    expect(tester.takeException(), isNull);
  });

  testWidgets('removing merged sources from the list exits checkbox mode',
      (tester) async {
    tester.view.physicalSize = const Size(400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsController(prefs, _FakeRemote());
    final now = DateTime(2026, 9, 19, 11, 18);
    var expenses = [
      _row(id: 'a', description: 'Paytm', amount: 30, date: now),
      _row(id: 'b', description: 'gpay-row', amount: 80, date: now),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsProvider.overrideWith((ref) => settings)],
        child: MaterialApp(
          theme: _theme(),
          home: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                body: TrackerTab(
                  expenses: expenses,
                  budget: 50000,
                  budgetHistory: const [],
                  learnings: const {},
                  onAddExpense: () {},
                  onDeleteExpense: (_) {},
                  onUpdateExpense: (_) {},
                  onSetBudget: () {},
                  onUpdateLearnings: () {},
                  onEditExpense: (_) {},
                  onShowBudgetHistory: () {},
                  onOpenTimeframe: (_) {},
                  onMergeExpenses: (_) {
                    setState(() {
                      expenses = [
                        _row(
                          id: 'm',
                          description: 'Flower shop',
                          amount: 110,
                          date: now,
                        ),
                      ];
                    });
                  },
                  clock: DateTime(2026, 9, 19, 12, 41),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump();

    await tester.ensureVisible(find.text('Paytm'));
    await tester.longPress(find.text('Paytm'));
    await tester.pump();
    await tester.drag(find.byKey(const ValueKey('tracker-main-scroll')), const Offset(0, -220));
    await tester.pump();
    await tester.tap(find.text('gpay-row'));
    await tester.pump();
    expect(find.byKey(kExpenseMergeSubmitKey), findsOneWidget);

    await tester.tap(find.byKey(kExpenseMergeSubmitKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Paytm'), findsNothing);
    expect(find.text('gpay-row'), findsNothing);
    expect(find.text('Flower shop'), findsOneWidget);
    expect(find.byKey(kExpenseMergeBarKey), findsNothing);
    expect(find.byKey(const ValueKey('merge-check-a')), findsNothing);
    expect(find.textContaining('swipe to edit'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long-press keeps the list scrolled on the pressed row',
      (tester) async {
    tester.view.physicalSize = const Size(400, 680);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsController(prefs, _FakeRemote());
    final now = DateTime(2026, 9, 19, 12, 0);
    final expenses = [
      for (var i = 0; i < 12; i++)
        _row(
          id: 'r$i',
          description: i == 11 ? 'Paytm-bottom' : 'UPI-$i',
          amount: 10.0 + i,
          date: now.subtract(Duration(minutes: i)),
        ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsProvider.overrideWith((ref) => settings)],
        child: MaterialApp(
          theme: _theme(),
          home: Scaffold(
            body: TrackerTab(
              expenses: expenses,
              budget: 50000,
              budgetHistory: const [],
              learnings: const {},
              onAddExpense: () {},
              onDeleteExpense: (_) {},
              onUpdateExpense: (_) {},
              onSetBudget: () {},
              onUpdateLearnings: () {},
              onEditExpense: (_) {},
              onShowBudgetHistory: () {},
              onOpenTimeframe: (_) {},
              onMergeExpenses: (_) {},
              clock: DateTime(2026, 9, 19, 12, 41),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump();

    final scrollView = tester.widget<SingleChildScrollView>(
      find.byKey(const ValueKey('tracker-main-scroll')),
    );
    final ctrl = scrollView.controller!;
    ctrl.jumpTo(ctrl.position.maxScrollExtent);
    await tester.pump();
    final before = ctrl.offset;
    expect(before, greaterThan(80));

    await tester.longPress(find.text('Paytm-bottom'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(ctrl.offset, closeTo(before, 24));
    expect(find.byKey(kExpenseMergeBarKey), findsOneWidget);
    expect(find.text('Paytm-bottom'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('merge sheet saves bank, card, and comments', (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final plan = planExpenseMerge([
      Expense(
        id: 'a',
        amount: 60,
        description: 'a',
        category: 'Others',
        bank: 'HDFC',
        cardType: 'CC',
        date: '2026-09-19T11:18:00.000',
        isManualCategory: false,
      ),
      Expense(
        id: 'b',
        amount: 37,
        description: 'b',
        category: 'Others',
        bank: 'HDFC',
        cardType: 'CC',
        date: '2026-09-19T10:18:00.000',
        isManualCategory: false,
      ),
    ]);

    Expense? saved;
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                saved = await showMergeExpensesModal(
                  context,
                  plan: plan,
                  mergedId: 'merged-1',
                );
              },
              child: const Text('open-merge'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open-merge'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byType(TextField).first, 'Flower shop');
    await tester.ensureVisible(find.text('AXIS'));
    await tester.tap(find.text('AXIS'));
    await tester.pump();
    await tester.ensureVisible(find.text('🏦 DB'));
    await tester.tap(find.text('🏦 DB'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), 'split with Riya');
    await tester.ensureVisible(find.byKey(kExpenseMergeSaveKey));
    await tester.tap(find.byKey(kExpenseMergeSaveKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(saved, isNotNull);
    expect(saved!.description, 'Flower shop');
    expect(saved!.bank, 'AXIS');
    expect(saved!.cardType, 'DB');
    expect(saved!.comments, 'split with Riya');
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}
