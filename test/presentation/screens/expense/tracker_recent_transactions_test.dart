// Verifies the reworked "Most Recent Transactions" list: entries logged for
// any date the picker can produce (yesterday, last month, next month) all show
// up here immediately, sorted newest-first by their chosen date, while the
// header badge counts every transaction. This is the behaviour that makes a
// backdated / forward-dated expense feel "tracked".

import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/data/services/user_preferences_service.dart';
import 'package:ai_nexus/presentation/screens/expense/widgets/expense_item.dart';
import 'package:ai_nexus/presentation/screens/expense/widgets/tracker_tab.dart';
import 'package:ai_nexus/presentation/screens/settings/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
          isDark: true,
        ),
      ],
    );

ExpenseData _e(String id, String desc, DateTime date) => ExpenseData(
      id: id,
      amount: 100,
      description: desc,
      category: 'Food',
      bank: 'HDFC',
      cardType: 'DB',
      date: date.toIso8601String(),
    );

Future<void> _pumpTracker(WidgetTester tester, List<ExpenseData> expenses) async {
  tester.view.physicalSize = const Size(400, 1600);
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
          budget: 10000,
          budgetHistory: const [],
          learnings: const {},
          onAddExpense: () {},
          onDeleteExpense: (_) {},
          onUpdateExpense: (_) {},
          onSetBudget: () {},
          onUpdateLearnings: () {},
          onEditExpense: (_) {},
          onShowTrend: () {},
          onShowBudgetHistory: () {},
          onOpenTimeframe: (_) {},
        ),
      ),
      ),
    ),
  );
  // Let the budget-ring one-shot animation finish.
  await tester.pump(const Duration(milliseconds: 1200));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('en_IN');
  });

  testWidgets('backdated and future-dated entries all appear in the recent list',
      (tester) async {
    final now = DateTime.now();
    final expenses = <ExpenseData>[
      _e('1', 'Coffee today', now),
      _e('2', 'Bus yesterday', now.subtract(const Duration(days: 1))),
      _e('3', 'Last month rent', DateTime(now.year, now.month - 1, 12, 12)),
      _e('4', 'Next month bill', DateTime(now.year, now.month + 1, 1, 12)),
    ];
    await _pumpTracker(tester, expenses);

    expect(find.text('Most Recent Transactions'), findsOneWidget);
    // Every transaction — regardless of its date — is present.
    expect(find.text('Coffee today'), findsOneWidget);
    expect(find.text('Bus yesterday'), findsOneWidget);
    expect(find.text('Last month rent'), findsOneWidget);
    expect(find.text('Next month bill'), findsOneWidget);
    // Header badge counts all four.
    expect(find.text('4 txns'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recent list is sorted newest-first by the chosen date',
      (tester) async {
    final now = DateTime.now();
    final expenses = <ExpenseData>[
      _e('old', 'Older entry', now.subtract(const Duration(days: 5))),
      _e('new', 'Newer entry', now),
    ];
    await _pumpTracker(tester, expenses);

    final newerY = tester.getTopLeft(find.text('Newer entry')).dy;
    final olderY = tester.getTopLeft(find.text('Older entry')).dy;
    expect(newerY, lessThan(olderY));
    expect(tester.takeException(), isNull);
  });

  testWidgets('investments are excluded from the spending recent list',
      (tester) async {
    final now = DateTime.now();
    final expenses = <ExpenseData>[
      _e('1', 'Groceries', now),
      ExpenseData(
        id: 'inv',
        amount: 5000,
        description: 'Mutual Funds',
        category: 'Investment',
        bank: 'HDFC',
        cardType: 'CC',
        date: now.toIso8601String(),
      ),
    ];
    await _pumpTracker(tester, expenses);

    expect(find.text('Groceries'), findsOneWidget);
    // Investment is wealth-building, not a spend — it must not appear in the
    // spending transaction list, and the badge counts spend only.
    expect(find.text('Mutual Funds'), findsNothing);
    expect(find.text('1 txn'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
