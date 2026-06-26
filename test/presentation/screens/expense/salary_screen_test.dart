// Widget + scaling tests for the standout SalaryScreen. Renders the REAL screen
// at a cramped 320px width with the salary stats/trend providers overridden, to
// prove: no overflow, the in-hand salary + savings/budget stats render, the
// hike chip shows month-over-month change, and the monthly history (with hike
// chips) lays out. Also covers the empty (no salary) state.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/core/di/injection.dart';
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

  const ccStats = SalaryStats(
    month: '2026-06',
    salary: 100000,
    budget: 60000,
    spent: 40000,
    previousSalary: 90000,
    totalRecorded: 280000,
    monthsRecorded: 3,
    highestSalary: 100000,
    averageSalary: 93333,
    cumulativeSaved: 135000,
    avgSavingsRatePct: 48,
    avgMonthlySpend: 52500,
    dayOfMonth: 15,
    daysInMonth: 30,
    ccSpentThisMonth: 25000, // charged this month → due next month
    ccDueThisMonth: 18000, // last month's bill being repaid now
  );

  testWidgets('renders the credit-card forecast card with the reduced take-home',
      (tester) async {
    await _pump(tester, stats: ccStats, trend: trend);
    expect(tester.takeException(), isNull);
    expect(find.text('Credit card forecast'), findsOneWidget);
    expect(find.text('Due next month'), findsOneWidget);
    expect(find.text('Charged this month'), findsOneWidget);
    expect(find.text('Repay next month'), findsOneWidget);
    // Forecast = 100k - 25k = 75k take-home next month.
    expect(find.textContaining('75,000'), findsWidgets);
    // The "salary − card bill" breakdown line.
    expect(find.textContaining('card bill'), findsWidgets);
    // Last month's bill due-now note → real take-home 100k - 18k = 82k.
    expect(find.textContaining('82,000'), findsWidgets);
  });

  testWidgets('credit-card card is hidden when there is no CC activity',
      (tester) async {
    await _pump(tester, stats: filledStats, trend: trend);
    expect(find.text('Credit card forecast'), findsNothing);
  });

  testWidgets('credit-card card scales on a 280px screen without overflow',
      (tester) async {
    await _pump(
      tester,
      stats: ccStats,
      trend: trend,
      size: const Size(280, 4000),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Credit card forecast'), findsOneWidget);
  });

  testWidgets('credit-card card shows only the due-now note when nothing '
      'charged this month', (tester) async {
    const dueOnly = SalaryStats(
      month: '2026-06',
      salary: 100000,
      budget: 0,
      spent: 10000,
      previousSalary: null,
      totalRecorded: 100000,
      monthsRecorded: 1,
      highestSalary: 100000,
      averageSalary: 100000,
      dayOfMonth: 8,
      daysInMonth: 30,
      ccSpentThisMonth: 0, // no new charges → no forecast block
      ccDueThisMonth: 22000, // last month's bill due now
    );
    await _pump(tester, stats: dueOnly, trend: const []);
    expect(tester.takeException(), isNull);
    expect(find.text('Credit card forecast'), findsOneWidget);
    // No "forecast take-home" block (nothing charged this month).
    expect(find.text('Charged this month'), findsNothing);
    // Real take-home this month = 100k - 22k = 78k shown in the due-now note.
    expect(find.textContaining('78,000'), findsWidgets);
  });

  testWidgets('credit-card card handles a crore-scale bill at 280px',
      (tester) async {
    const huge = SalaryStats(
      month: '2026-06',
      salary: 5000000, // ₹50 lakh
      budget: 0,
      spent: 100000,
      previousSalary: null,
      totalRecorded: 5000000,
      monthsRecorded: 1,
      highestSalary: 5000000,
      averageSalary: 5000000,
      avgMonthlySpend: 3000000,
      dayOfMonth: 12,
      daysInMonth: 31,
      ccSpentThisMonth: 9999999, // ~₹1 crore charged
      ccDueThisMonth: 8888888,
    );
    await _pump(
      tester,
      stats: huge,
      trend: const [],
      size: const Size(280, 4200),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Credit card forecast'), findsOneWidget);
  });

  testWidgets('credit-card bill larger than salary renders a negative forecast',
      (tester) async {
    const overCc = SalaryStats(
      month: '2026-06',
      salary: 50000,
      budget: 0,
      spent: 5000,
      previousSalary: null,
      totalRecorded: 50000,
      monthsRecorded: 1,
      highestSalary: 50000,
      averageSalary: 50000,
      dayOfMonth: 10,
      daysInMonth: 30,
      ccSpentThisMonth: 70000, // bill exceeds the whole salary
    );
    await _pump(tester, stats: overCc, trend: const []);
    expect(tester.takeException(), isNull);
    expect(find.text('Credit card forecast'), findsOneWidget);
    // Forecast take-home = 50k - 70k = -20k, shown negative.
    expect(find.textContaining('-'), findsWidgets);
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
