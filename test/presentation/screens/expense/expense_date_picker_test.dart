// Deep coverage for the fluid ExpenseDatePicker:
//  - defaults to today, editable via quick chips and the inline calendar,
//  - lets the user pick past/current/future days (last-month, next-month),
//  - navigates months, and
//  - renders without overflow on both a narrow (Android) and a wide (web)
//    surface — no scaling issues in either target.

import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/presentation/screens/expense/widgets/expense_date_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

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

class _Harness extends StatefulWidget {
  const _Harness({required this.initial, required this.onChanged});
  final DateTime initial;
  final ValueChanged<DateTime> onChanged;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late DateTime _date = widget.initial;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: _theme(),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ExpenseDatePicker(
            selectedDate: _date,
            onChanged: (d) {
              setState(() => _date = d);
              widget.onChanged(d);
            },
          ),
        ),
      ),
    );
  }
}

Future<void> _pump(
  WidgetTester tester,
  DateTime initial,
  List<DateTime> log, {
  Size size = const Size(400, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    _Harness(initial: initial, onChanged: log.add),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('en_IN');
  });

  testWidgets('defaults to the given (today) date and shows quick chips',
      (tester) async {
    final today = DateTime(2026, 7, 3);
    final log = <DateTime>[];
    await _pump(tester, today, log);

    // The pill shows the full selected date.
    expect(
      find.text(DateFormat('EEE, d MMM yyyy').format(today)),
      findsOneWidget,
    );
    // Quick chips present.
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Today'), findsWidgets);
    expect(find.text('Tomorrow'), findsOneWidget);
    // No callback fired just by rendering.
    expect(log, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quick chips log yesterday / tomorrow (relative to real today)',
      (tester) async {
    // The Yesterday/Today/Tomorrow chips are anchored to the REAL current
    // date (DateTime.now()), not to the selected date — "Yesterday" always
    // means the day before today, regardless of which day is selected. So we
    // derive the expectations from now() the same way the widget does, which
    // keeps this test correct on every calendar day (the old version hard-
    // coded 2026-07-02/04 and only passed on 2026-07-03).
    final today = dateOnly(DateTime.now());
    final log = <DateTime>[];
    await _pump(tester, today, log);

    await tester.tap(find.text('Yesterday'));
    await tester.pumpAndSettle();
    expect(log.last, today.subtract(const Duration(days: 1)));

    await tester.tap(find.text('Tomorrow'));
    await tester.pumpAndSettle();
    expect(log.last, today.add(const Duration(days: 1)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens the calendar and picks a day in the current month',
      (tester) async {
    final today = DateTime(2026, 7, 10);
    final log = <DateTime>[];
    await _pump(tester, today, log);

    // Open the inline calendar.
    await tester.tap(find.byIcon(LucideIcons.chevronDown));
    await tester.pumpAndSettle();
    expect(find.text('July 2026'), findsOneWidget);

    // Pick the 15th.
    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();
    expect(log.last, DateTime(2026, 7, 15));
    expect(tester.takeException(), isNull);
  });

  testWidgets('navigates to the next month and picks a future day', (tester) async {
    final today = DateTime(2026, 7, 10);
    final log = <DateTime>[];
    await _pump(tester, today, log);

    await tester.tap(find.byIcon(LucideIcons.chevronDown));
    await tester.pumpAndSettle();

    // Forward one month → August 2026.
    await tester.tap(find.byIcon(LucideIcons.chevronRight));
    await tester.pumpAndSettle();
    expect(find.text('August 2026'), findsOneWidget);

    await tester.tap(find.text('20'));
    await tester.pumpAndSettle();
    expect(log.last, DateTime(2026, 8, 20));
    expect(tester.takeException(), isNull);
  });

  testWidgets('navigates to the previous month (last-month) and picks a day',
      (tester) async {
    final today = DateTime(2026, 7, 10);
    final log = <DateTime>[];
    await _pump(tester, today, log);

    await tester.tap(find.byIcon(LucideIcons.chevronDown));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.chevronLeft));
    await tester.pumpAndSettle();
    expect(find.text('June 2026'), findsOneWidget);

    await tester.tap(find.text('12'));
    await tester.pumpAndSettle();
    expect(log.last, DateTime(2026, 6, 12));
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders without overflow on a narrow Android surface',
      (tester) async {
    final log = <DateTime>[];
    await _pump(tester, DateTime(2026, 7, 10), log,
        size: const Size(320, 780));
    await tester.tap(find.byIcon(LucideIcons.chevronDown));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders without overflow on a wide web surface', (tester) async {
    final log = <DateTime>[];
    await _pump(tester, DateTime(2026, 7, 10), log,
        size: const Size(1280, 900));
    await tester.tap(find.byIcon(LucideIcons.chevronDown));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  // The real scaling guarantee: at EVERY resolution the full 6-week grid must
  // be laid out, so the *last* day of a 31-day month (July) has to be both
  // visible and tappable. A clipped bottom row (the old fixed-height bug) or a
  // circle that overflowed a tiny cell would make this fail.
  final sizes = <String, Size>{
    'tiny phone (320×568)': const Size(320, 568),
    'small phone (360×640)': const Size(360, 640),
    'typical phone (412×915)': const Size(412, 915),
    'short/landscape (720×420)': const Size(720, 420),
    'tablet (768×1024)': const Size(768, 1024),
    'large web (1440×900)': const Size(1440, 900),
  };

  sizes.forEach((name, size) {
    testWidgets('last day (31) stays visible & tappable on $name',
        (tester) async {
      final log = <DateTime>[];
      await _pump(tester, DateTime(2026, 7, 10), log, size: size);

      await tester.tap(find.byIcon(LucideIcons.chevronDown));
      await tester.pumpAndSettle();
      expect(find.text('July 2026'), findsOneWidget);

      // "31" must be laid out (not clipped off the 6-week grid). On short
      // viewports the sheet legitimately scrolls, so bring it into view first
      // — exactly what the real scrollable modal does.
      final lastDay = find.text('31');
      expect(lastDay, findsOneWidget, reason: 'day 31 clipped on $name');
      await tester.ensureVisible(lastDay);
      await tester.pumpAndSettle();
      await tester.tap(lastDay);
      await tester.pumpAndSettle();

      expect(log.last, DateTime(2026, 7, 31), reason: 'pick failed on $name');
      expect(tester.takeException(), isNull, reason: 'overflow on $name');
    });
  });
}
