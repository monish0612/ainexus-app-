// Widget + scaling tests for the standout SalaryScreen. Renders the REAL screen
// at a cramped 320px width with the salary stats/trend providers overridden, to
// prove: no overflow, the in-hand salary + savings/budget stats render, the
// hike chip shows month-over-month change, and the monthly history (with hike
// chips) lays out. Also covers the empty (no salary) state.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/domain/entities/salary_entities.dart';
import 'package:ai_nexus/presentation/providers/salary_providers.dart';
import 'package:ai_nexus/presentation/screens/expense/salary_screen.dart';

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
}) async {
  tester.view.physicalSize = const Size(320, 2200);
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
      ],
      child: MaterialApp(
        theme: _theme(),
        home: SalaryScreen(aiAnswer: aiAnswer),
      ),
    ),
  );
  await tester.pumpAndSettle();
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

  testWidgets('empty state prompts to enter salary, no overflow',
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
  });
}
