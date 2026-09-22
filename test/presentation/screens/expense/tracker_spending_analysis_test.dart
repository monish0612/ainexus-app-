import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/core/utils/currency_formatter.dart';
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
  required double amount,
  required String category,
  required DateTime date,
  String description = 'SMS spend',
  bool? manual,
}) =>
    ExpenseData(
      id: id,
      amount: amount,
      description: description,
      category: category,
      bank: 'HDFC',
      cardType: 'DB',
      date: date.toIso8601String(),
      isManualCategory: manual ?? category != 'Others',
    );

Finder _pieLabel(String label) => find.descendant(
      of: find.byType(PageView),
      matching: find.text(label),
    );

Future<void> _pumpTracker(
  WidgetTester tester,
  List<ExpenseData> expenses, {
  void Function(int index, String category)? onOpenCategory,
  DateTime? clock,
}) async {
  tester.view.physicalSize = const Size(400, 1800);
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
            onOpenCategory: onOpenCategory,
            clock: clock,
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

  testWidgets(
      'SMS Others on the Today ring stays Others, not overflow Other',
      (tester) async {
    final now = DateTime.now();
    await _pumpTracker(tester, [
      _row(id: 'food', amount: 9000, category: 'Food', date: now),
      _row(
        id: 'sms',
        amount: 200,
        category: 'Others',
        date: now,
        description: 'Q227400652@ybl',
      ),
    ]);

    expect(find.text('Spending Analysis'), findsOneWidget);
    expect(_pieLabel('Food'), findsOneWidget);
    expect(_pieLabel('Others'), findsOneWidget);
    expect(_pieLabel('Other'), findsNothing);
    expect(_pieLabel('Medical'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'editing an SMS Others row to Medical updates the ring and legend',
      (tester) async {
    final now = DateTime.now();
    await _pumpTracker(tester, [
      _row(id: 'food', amount: 9000, category: 'Food', date: now),
      _row(
        id: 'sms',
        amount: 200,
        category: 'Others',
        date: now,
        description: 'Sundaram Medical',
      ),
    ]);
    expect(_pieLabel('Others'), findsOneWidget);
    expect(_pieLabel('Medical'), findsNothing);

    await _pumpTracker(tester, [
      _row(id: 'food', amount: 9000, category: 'Food', date: now),
      _row(
        id: 'sms',
        amount: 200,
        category: 'Medical',
        date: now,
        description: 'Sundaram Medical',
        manual: true,
      ),
    ]);

    expect(find.text('Spending Analysis'), findsOneWidget);
    expect(_pieLabel('Medical'), findsOneWidget);
    expect(_pieLabel('Food'), findsOneWidget);
    expect(_pieLabel('Other'), findsNothing);
    expect(_pieLabel('Others'), findsNothing);

    await tester.tap(_pieLabel('Medical'));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(PageView),
        matching: find.text(formatCurrency(200)),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('yesterday Medical is on 7D, not on Today', (tester) async {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    await _pumpTracker(tester, [
      _row(
        id: 'sms',
        amount: 200,
        category: 'Medical',
        date: yesterday,
        description: 'Sundaram Medical',
        manual: true,
      ),
    ]);

    expect(_pieLabel('Medical'), findsNothing);
    expect(find.textContaining('No expenses for today'), findsOneWidget);

    await tester.tap(find.text('7D'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(_pieLabel('Medical'), findsOneWidget);
    expect(_pieLabel('Other'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Investment does not appear on the spending-analysis ring',
      (tester) async {
    final now = DateTime.now();
    await _pumpTracker(tester, [
      _row(id: 'food', amount: 500, category: 'Food', date: now),
      _row(id: 'sip', amount: 10000, category: 'Investment', date: now),
      _row(id: 'emi', amount: 8000, category: 'Loan', date: now),
    ]);

    expect(_pieLabel('Food'), findsOneWidget);
    expect(_pieLabel('Investment'), findsNothing);
    expect(_pieLabel('Loan'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty period shows the empty analysis copy, not Other',
      (tester) async {
    await _pumpTracker(tester, const []);
    expect(find.text('Spending Analysis'), findsOneWidget);
    expect(find.textContaining('No expenses for today'), findsOneWidget);
    expect(_pieLabel('Other'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'yesterday afternoon SMS is not TODAY\'S SPENDING after midnight',
      (tester) async {
    final clock = DateTime(2026, 9, 17, 13, 29);
    await _pumpTracker(
      tester,
      [
        _row(
          id: 'pos',
          amount: 2890,
          category: 'Others',
          date: DateTime(2026, 9, 16, 13, 37),
          description: 'ibkpos',
        ),
        _row(
          id: 'prajin',
          amount: 75,
          category: 'Personal',
          date: DateTime(2026, 9, 16, 12, 31),
          description: 'Prajin M',
        ),
      ],
      clock: clock,
    );

    expect(find.text('no expenses yet today'), findsOneWidget);
    expect(find.text('2 transactions today'), findsNothing);
    expect(find.text('YESTERDAY'), findsOneWidget);
    expect(find.text('ibkpos'), findsOneWidget);
    expect(find.text('Prajin M'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
