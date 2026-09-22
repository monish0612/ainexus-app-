// Regression tests for the expense amount field accepting letters.
//
// Before the fix the amount TextFields in add_expense_modal /
// edit_expense_modal declared `TextInputType.numberWithOptions(decimal:
// true)` and NO `inputFormatters`. `TextInputType` is only a hint to the
// IME — hardware keyboards, swipe input, voice input and plenty of
// third-party IMEs happily deliver letters, which then made
// `double.tryParse(text.replaceAll(',', ''))` return null and the amount
// silently read as 0.
//
// The parse contract these tests lock down is the app's `en_IN` locale:
// `.` is the decimal point, `,` is a thousands group that the parsers
// strip.

import 'package:ai_nexus/core/utils/amount_input_formatter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _fmt = AmountInputFormatter();

TextEditingValue _v(String text) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );

/// Mirrors the parse used by both expense modals.
double? _parseLikeTheModal(String text) =>
    double.tryParse(text.replaceAll(',', ''));

void main() {
  group('AmountInputFormatter.sanitize', () {
    test('drops letters typed between digits', () {
      expect(_fmt.sanitize('12abc34'), equals('1234'));
    });

    test('rejects a purely alphabetic amount outright', () {
      expect(_fmt.sanitize('hello'), isEmpty);
    });

    test('keeps one decimal point and drops the rest', () {
      expect(_fmt.sanitize('12.34'), equals('12.34'));
      expect(_fmt.sanitize('12.3.4'), equals('12.34'));
    });

    test('caps the fraction at two digits', () {
      expect(_fmt.sanitize('12.3456'), equals('12.34'));
    });

    test('keeps thousands groups before the decimal point', () {
      expect(_fmt.sanitize('1,234.50'), equals('1,234.50'));
    });

    test('drops a group separator after the decimal point', () {
      // '12.3,4' would survive replaceAll(',', '') as 12.34 — a silent
      // digit shift. Reject the comma instead.
      expect(_fmt.sanitize('12.3,4'), equals('12.34'));
    });

    test('strips currency symbols, signs, spaces and exponents from a paste',
        () {
      expect(_fmt.sanitize('₹1,234.50 at Cafe'), equals('1,234.50'));
      expect(_fmt.sanitize('-99'), equals('99'));
      expect(_fmt.sanitize('1e9'), equals('19'));
    });

    test('leaves an already-valid amount byte-identical', () {
      expect(_fmt.sanitize('4599'), equals('4599'));
      expect(_fmt.sanitize('0.05'), equals('0.05'));
      expect(_fmt.sanitize(''), isEmpty);
    });

    test('everything it emits is parseable by the modal, or empty', () {
      for (final raw in const [
        'abc',
        '12abc34',
        '₹1,234.50 at Cafe',
        '12.3456',
        '9,99,999',
      ]) {
        final clean = _fmt.sanitize(raw);
        if (clean.isEmpty) continue;
        expect(_parseLikeTheModal(clean), isNotNull,
            reason: '"$raw" sanitised to "$clean" which the modal cannot parse');
      }
    });
  });

  group('AmountInputFormatter.formatEditUpdate', () {
    test('returns the value untouched when nothing needs stripping', () {
      final value = _v('1234');
      expect(identical(_fmt.formatEditUpdate(_v(''), value), value), isTrue);
    });

    test('caret lands after the surviving prefix, not at the end', () {
      // User typed "x" between 1 and 2 of "12" → raw "1x2", caret at 2.
      const raw = TextEditingValue(
        text: '1x2',
        selection: TextSelection.collapsed(offset: 2),
      );
      final out = _fmt.formatEditUpdate(_v('12'), raw);
      expect(out.text, equals('12'));
      expect(out.selection.baseOffset, equals(1));
      expect(out.composing, equals(TextRange.empty));
    });
  });

  group('amount TextField wiring', () {
    Future<TextEditingController> pumpField(WidgetTester tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(
              controller: controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: const [AmountInputFormatter()],
            ),
          ),
        ),
      );
      return controller;
    }

    testWidgets('typing letters into the amount field is rejected',
        (tester) async {
      final controller = await pumpField(tester);
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump();
      expect(controller.text, isEmpty);
    });

    testWidgets('a decimal amount still goes in', (tester) async {
      final controller = await pumpField(tester);
      await tester.enterText(find.byType(TextField), '1250.75');
      await tester.pump();
      expect(controller.text, equals('1250.75'));
      expect(_parseLikeTheModal(controller.text), closeTo(1250.75, 1e-9));
    });

    testWidgets('pasting a receipt line keeps only the number',
        (tester) async {
      final controller = await pumpField(tester);
      await tester.enterText(find.byType(TextField), 'Total ₹1,234.50');
      await tester.pump();
      expect(controller.text, equals('1,234.50'));
      expect(_parseLikeTheModal(controller.text), closeTo(1234.50, 1e-9));
    });

    testWidgets(
        'receipt-scan / voice autofill writes the controller directly and is '
        'NOT filtered', (tester) async {
      // Both modals autofill with `_amountCtrl.text = …`. Flutter only
      // runs formatters on platform edits, so that path must stay intact
      // even if its value would not survive sanitise.
      final controller = await pumpField(tester);
      controller.text = '4599';
      await tester.pump();
      expect(controller.text, equals('4599'));
    });
  });
}
