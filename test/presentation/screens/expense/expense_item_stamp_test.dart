import 'dart:io';

import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/presentation/screens/expense/widgets/expense_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

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

ExpenseData _row({
  required String date,
  String comments = '',
}) =>
    ExpenseData(
      id: '1',
      amount: 2399,
      description: 'Anthropic Claude Sub',
      category: 'Subscription',
      bank: 'SCAPIA',
      cardType: 'CC',
      date: date,
      comments: comments,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('en_IN');
  });

  test('tracker rows format the stamp, never dummy formatTime noon', () {
    final src = File('lib/presentation/screens/expense/widgets/expense_item.dart')
        .readAsStringSync();
    expect(src, contains('formatExpenseStamp(e.date, comments: e.comments)'));
    expect(src, isNot(contains('formatTime(e.date)')));
  });

  Future<void> pumpRow(WidgetTester tester, ExpenseData e) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme(),
        home: Scaffold(
          body: ExpenseItem(
            expense: e,
            onEdit: () {},
            onDelete: () {},
          ),
        ),
      ),
    );
  }

  testWidgets('SMS noon row shows the Auto Detected logged clock',
      (tester) async {
    await pumpRow(
      tester,
      _row(
        date: DateTime(2026, 9, 13, 12).toIso8601String(),
        comments: 'Auto Detected · 13 Sep 2026, 3:14 PM',
      ),
    );
    expect(find.text('3:14 pm'), findsOneWidget);
    expect(find.textContaining('12:00'), findsNothing);
  });

  testWidgets('edited day with leftover stamp shows the edited date',
      (tester) async {
    await pumpRow(
      tester,
      _row(
        date: DateTime(2026, 9, 12, 12).toIso8601String(),
        comments: 'Auto Detected · 13 Sep 2026, 3:14 PM',
      ),
    );
    expect(find.textContaining('12 Sep'), findsOneWidget);
    expect(find.textContaining('12:00'), findsNothing);
  });

  testWidgets('live clock is shown even when comments have a different stamp',
      (tester) async {
    await pumpRow(
      tester,
      _row(
        date: DateTime(2026, 9, 13, 8, 20, 33, 12).toIso8601String(),
        comments: 'Auto Detected · 13 Sep 2026, 3:14 PM',
      ),
    );
    expect(find.text('8:20 am'), findsOneWidget);
    expect(find.text('3:14 pm'), findsNothing);
  });
}
