// Widget + scaling tests for the standout SalaryScreen. Renders the REAL screen
// at a cramped 320px width with the salary stats/trend providers overridden, to
// prove: no overflow, the in-hand salary + savings/budget stats render, the
// hike chip shows month-over-month change, and the monthly history (with hike
// chips) lays out. Also covers the empty (no salary) state.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/core/di/injection.dart';
import 'package:ai_nexus/core/services/credit_card_forecast_engine.dart';
import 'package:ai_nexus/core/services/salary_insight_engine.dart';
import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/domain/entities/expense_insight.dart';
import 'package:ai_nexus/domain/entities/salary_entities.dart';
import 'package:ai_nexus/presentation/providers/salary_providers.dart';
import 'package:ai_nexus/presentation/screens/expense/salary_screen.dart';

const _rec = GroundedRecommendation(
  greeting: 'Hey Monish,',
  headline: 'You saved ₹60,000 (60%) of your ₹1,00,000 salary so far.',
  tip: 'At this pace you\'re on track to save ₹55,000 this month.',
  tone: InsightTone.positive,
  chips: ['How can I save more?', 'Did I get a hike?'],
  isTemplate: false,
);

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

SalaryEntry _e(String month, double amt) =>
    SalaryEntry(id: month, month: month, amount: amt, setAt: '');

Future<void> _pump(
  WidgetTester tester, {
  required SalaryStats stats,
  required List<SalaryTrendItem> trend,
  String? aiAnswer,
  GroundedRecommendation? recommendation = _rec,
  CreditCardForecast forecast = CreditCardForecast.empty,
  Size size = const Size(320, 3200),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        salaryStatsProvider.overrideWithValue(stats),
        salaryTrendProvider.overrideWithValue(trend),
        userFirstNameProvider.overrideWithValue('Monish'),
        creditCardForecastProvider.overrideWithValue(forecast),
        // Feed a ready recommendation so the AI card renders without network.
        salaryRecommendationProvider.overrideWith(
          (ref) async => recommendation ?? _rec,
        ),
      ],
      child: MaterialApp(
        theme: _theme(),
        home: SalaryScreen(aiAnswer: aiAnswer),
      ),
    ),
  );
  // The recommendation resolves via a (sync) Future; pump a couple of frames
  // instead of pumpAndSettle (the shimmer stops once content arrives, but we
  // avoid relying on settle to keep the test fast + robust).
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const filledStats = SalaryStats(
    month: '2026-06',
    salary: 100000,
    budget: 60000,
    spent: 40000,
    previousSalary: 90000, // +11.1% hike
    totalRecorded: 280000,
    monthsRecorded: 3,
    highestSalary: 100000,
    averageSalary: 93333,
    cumulativeSaved: 135000,
    avgSavingsRatePct: 48,
    avgMonthlySpend: 52500,
    dayOfMonth: 15,
    daysInMonth: 30,
  );

  final trend = <SalaryTrendItem>[
    SalaryTrendItem(entry: _e('2026-06', 100000), previousAmount: 90000),
    SalaryTrendItem(entry: _e('2026-05', 90000), previousAmount: 90000),
    SalaryTrendItem(entry: _e('2026-04', 90000), previousAmount: null),
  ];

  testWidgets('renders filled salary stats at 320px with no overflow',
      (tester) async {
    await _pump(tester, stats: filledStats, trend: trend);

    expect(tester.takeException(), isNull);
    expect(find.text('Salary & Income'), findsOneWidget);
    // In-hand amount.
    expect(find.textContaining('1,00,000'), findsWidgets);
    // Key stats labels.
    expect(find.text('Savings rate'), findsOneWidget);
    expect(find.text('Budget used'), findsOneWidget);
    expect(find.text('Health score'), findsOneWidget);
    // Month-over-month hike chip (+11.1%).
    expect(find.textContaining('+11.1%'), findsWidgets);
    // History section + month label.
    expect(find.text('Monthly history'), findsOneWidget);
    expect(find.text('June 2026'), findsWidgets);
  });

  testWidgets('renders the new pace + lifetime cards', (tester) async {
    await _pump(tester, stats: filledStats, trend: trend);
    expect(tester.takeException(), isNull);
    // Projection card.
    expect(find.text("This month's pace"), findsOneWidget);
    expect(find.text('Projected spend'), findsOneWidget);
    expect(find.text('Safe / day'), findsOneWidget);
    expect(find.textContaining('Day 15/30'), findsOneWidget);
    // Lifetime card.
    expect(find.text('Lifetime'), findsOneWidget);
    expect(find.text('Avg savings rate'), findsOneWidget);
    expect(find.text('Runway'), findsOneWidget);
    // Cumulative saved ₹1,35,000 shown.
    expect(find.textContaining('1,35,000'), findsWidgets);
  });

  // Per-bank forecast fixtures, built from the real engine so the widget test
  // exercises the same data the app produces.
  CreditCardForecast ccForecast({
    double charge = 25000,
    double salary = 100000,
  }) {
    return computeCreditCardForecast(
      ccBanks: const [BankBillingConfig(name: 'HDFC', statementDay: 18, dueDay: 9)],
      ccExpenses: [
        CardExpense(bank: 'HDFC', amount: charge, date: DateTime(2026, 6, 10)),
      ],
      salaryByMonth: {'2026-07': salary},
      now: DateTime(2026, 6, 15),
    );
  }

  testWidgets('renders the per-bank forecast: open statement + salary timeline',
      (tester) async {
    await _pump(tester, stats: filledStats, trend: trend, forecast: ccForecast());
    expect(tester.takeException(), isNull);
    expect(find.text('Credit card forecast'), findsOneWidget);
    expect(find.text('OPEN STATEMENTS'), findsOneWidget);
    expect(find.text('SALARY VS CARD BILLS'), findsOneWidget);
    // Which salary repays the bill.
    expect(find.textContaining('Repaid from your July 2026 salary'), findsWidgets);
    // Projected in-hand for July = 100k - 25k = 75k.
    expect(find.text('Projected in-hand'), findsWidgets);
    expect(find.textContaining('75,000'), findsWidgets);
    // The bank name is shown.
    expect(find.textContaining('HDFC'), findsWidgets);
  });

  testWidgets('credit-card card is hidden when there is no CC activity',
      (tester) async {
    await _pump(tester, stats: filledStats, trend: trend);
    expect(find.text('Credit card forecast'), findsNothing);
  });

  testWidgets('credit-card forecast scales on a 280px screen without overflow',
      (tester) async {
    await _pump(
      tester,
      stats: filledStats,
      trend: trend,
      forecast: ccForecast(),
      size: const Size(280, 4000),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Credit card forecast'), findsOneWidget);
  });

  testWidgets('credit-card forecast handles a crore-scale bill at 280px',
      (tester) async {
    await _pump(
      tester,
      stats: filledStats,
      trend: trend,
      forecast: ccForecast(charge: 9999999, salary: 5000000),
      size: const Size(280, 4200),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Credit card forecast'), findsOneWidget);
  });

  testWidgets('bills larger than the salary render a negative, flagged in-hand',
      (tester) async {
    await _pump(
      tester,
      stats: filledStats,
      trend: const [],
      forecast: ccForecast(charge: 70000, salary: 50000),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Credit card forecast'), findsOneWidget);
    // In-hand = 50k - 70k = -20k.
    expect(find.textContaining('20,000'), findsWidgets);
    expect(
      find.textContaining('Card bills exceed this salary'),
      findsOneWidget,
    );
  });

  testWidgets('credit-card forecast shows even without a recorded salary',
      (tester) async {
    // The forecast block is no longer gated behind having a salary entered.
    await _pump(
      tester,
      stats: SalaryStats.empty,
      trend: const [],
      forecast: computeCreditCardForecast(
        ccBanks: const [BankBillingConfig(name: 'HDFC', statementDay: 18, dueDay: 9)],
        ccExpenses: [
          CardExpense(bank: 'HDFC', amount: 5000, date: DateTime(2026, 6, 10)),
        ],
        salaryByMonth: const {},
        now: DateTime(2026, 6, 15),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Credit card forecast'), findsOneWidget);
  });

  testWidgets(
      'un-recorded salary month shows bills due + a nudge, not a misleading '
      'negative in-hand', (tester) async {
    await _pump(
      tester,
      stats: SalaryStats.empty,
      trend: const [],
      forecast: computeCreditCardForecast(
        ccBanks: const [BankBillingConfig(name: 'HDFC', statementDay: 18, dueDay: 9)],
        ccExpenses: [
          CardExpense(bank: 'HDFC', amount: 5000, date: DateTime(2026, 6, 10)),
        ],
        salaryByMonth: const {},
        now: DateTime(2026, 6, 15),
      ),
    );
    expect(tester.takeException(), isNull);
    // The July bill lands on a month with no recorded salary → surface the
    // bill, not a "-₹5,000" projected in-hand.
    expect(find.text('Card bills due'), findsOneWidget);
    expect(
      find.textContaining('Add this month\'s salary'),
      findsOneWidget,
    );
    expect(find.text('Projected in-hand'), findsNothing);
  });

  testWidgets('tapping an open statement reveals its line items',
      (tester) async {
    await _pump(
      tester,
      stats: filledStats,
      trend: trend,
      forecast: computeCreditCardForecast(
        ccBanks: const [BankBillingConfig(name: 'HDFC', statementDay: 18, dueDay: 9)],
        ccExpenses: [
          CardExpense(
            bank: 'HDFC',
            amount: 1234,
            date: DateTime(2026, 6, 10),
            description: 'Amazon order',
            category: 'Shopping',
          ),
        ],
        salaryByMonth: {'2026-07': 100000},
        now: DateTime(2026, 6, 15),
      ),
    );
    expect(tester.takeException(), isNull);
    // Collapsed by default: the individual charge label is not in the tree.
    expect(find.text('Amazon order'), findsNothing);
    // Tap the open-statement card (its bank name is exactly 'HDFC').
    await tester.tap(find.text('HDFC'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.text('Amazon order'), findsWidgets);
  });

  testWidgets('renders the personalized, grounded AI insight card',
      (tester) async {
    await _pump(tester, stats: filledStats, trend: trend);
    expect(tester.takeException(), isNull);
    expect(find.text('Hey Monish,'), findsOneWidget);
    expect(
      find.textContaining('saved ₹60,000'),
      findsOneWidget,
    );
    // A follow-up chip is tappable.
    expect(find.text('How can I save more?'), findsOneWidget);
  });

  testWidgets('personalizes the hero subtitle with the name', (tester) async {
    // No hike → the friendly, name-led subtitle is used.
    const noHike = SalaryStats(
      month: '2026-06',
      salary: 80000,
      budget: 0,
      spent: 10000,
      previousSalary: null,
      totalRecorded: 80000,
      monthsRecorded: 1,
      highestSalary: 80000,
      averageSalary: 80000,
      dayOfMonth: 5,
      daysInMonth: 30,
    );
    await _pump(tester, stats: noHike, trend: const []);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Monish'), findsWidgets);
  });

  testWidgets('shows AI banner when provided', (tester) async {
    await _pump(
      tester,
      stats: filledStats,
      trend: trend,
      aiAnswer: "Here's your salary overview.",
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining('salary overview'), findsOneWidget);
  });

  testWidgets('empty state prompts to enter salary, no overflow + no AI card',
      (tester) async {
    await _pump(
      tester,
      stats: SalaryStats.empty,
      trend: const [],
      aiAnswer: null,
    );
    expect(tester.takeException(), isNull);
    // Hero CTA when no salary.
    expect(find.text('Enter salary'), findsOneWidget);
    expect(find.textContaining('No salary recorded'), findsOneWidget);
    // AI insight + pace cards are gated behind having a salary.
    expect(find.text("This month's pace"), findsNothing);
    expect(find.text('Hey Monish,'), findsNothing);
  });

  testWidgets('extreme values (crore salary, deep overspend) do not overflow',
      (tester) async {
    const extreme = SalaryStats(
      month: '2026-06',
      salary: 99999999, // ~₹10 crore
      budget: 5000000,
      spent: 120000000, // overspent past salary
      previousSalary: 1000, // huge hike %
      totalRecorded: 999999999,
      monthsRecorded: 48,
      highestSalary: 99999999,
      averageSalary: 50000000,
      cumulativeSaved: -45000000, // net shortfall
      avgSavingsRatePct: -250,
      avgMonthlySpend: 80000000,
      dayOfMonth: 1, // day 1 → projection extrapolates hugely
      daysInMonth: 31,
    );
    await _pump(tester, stats: extreme, trend: trend);
    // The key assertion: no RenderFlex overflow / layout exception anywhere.
    expect(tester.takeException(), isNull);
    expect(find.text('Lifetime'), findsOneWidget);
    expect(find.text("This month's pace"), findsOneWidget);
  });

  testWidgets('renders without overflow on a very narrow 280px screen',
      (tester) async {
    await _pump(
      tester,
      stats: filledStats,
      trend: trend,
      size: const Size(280, 3600),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Salary & Income'), findsOneWidget);
  });

  testWidgets('template fallback (offline composer) still renders personalized',
      (tester) async {
    final template = SalaryInsightEngine.template(filledStats, 'Monish');
    await _pump(
      tester,
      stats: filledStats,
      trend: trend,
      recommendation: template,
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Hey Monish,'), findsOneWidget);
  });
}
