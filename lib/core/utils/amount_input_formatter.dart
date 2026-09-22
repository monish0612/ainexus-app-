import 'package:flutter/services.dart';

/// Numeric-only input for money fields.
///
/// Every expense amount is parsed with
/// `double.tryParse(text.replaceAll(',', ''))` — `.` is the decimal point
/// and `,` is a thousands group, which is exactly the app's `en_IN`
/// number locale. This formatter enforces that same grammar on the way
/// in, so a keyboard that happens to expose letters (hardware keyboards,
/// swipe/voice input, and every IME that ignores `TextInputType.number`)
/// can no longer produce an unparseable amount.
///
/// Rules, applied left to right:
///   * digits pass through;
///   * [groupSeparator] passes through before the decimal point, because
///     the parsers strip it;
///   * the first [decimalSeparator] passes, later ones are dropped;
///   * at most [maxDecimals] fraction digits are kept;
///   * everything else is dropped, so pasting `₹1,234.50 Cafe` lands as
///     `1,234.50` instead of being rejected outright.
///
/// Autofill is unaffected: Flutter runs input formatters only on user /
/// platform edits, never on a programmatic `controller.text = …`, which
/// is how receipt-scan and voice parsing populate the field.
class AmountInputFormatter extends TextInputFormatter {
  const AmountInputFormatter({
    this.maxDecimals = 2,
    this.decimalSeparator = '.',
    this.groupSeparator = ',',
  });

  final int maxDecimals;
  final String decimalSeparator;
  final String groupSeparator;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = sanitize(newValue.text);
    if (text == newValue.text) return newValue;

    // Re-derive the caret from the surviving prefix so deleting a
    // rejected character does not jump the cursor to the end.
    final raw = newValue.text;
    final end = newValue.selection.end;
    final caret = end < 0
        ? text.length
        : sanitize(raw.substring(0, end.clamp(0, raw.length))).length;

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret.clamp(0, text.length)),
      composing: TextRange.empty,
    );
  }

  /// Exposed for tests and for callers that need to clean pasted text
  /// outside of a [TextField].
  String sanitize(String raw) {
    final out = StringBuffer();
    var seenDecimal = false;
    var decimals = 0;

    for (var i = 0; i < raw.length; i++) {
      final ch = raw[i];

      if (ch == decimalSeparator) {
        if (seenDecimal || maxDecimals <= 0) continue;
        seenDecimal = true;
        out.write(ch);
        continue;
      }

      if (ch == groupSeparator) {
        // A group separator after the decimal point is meaningless and
        // would survive `replaceAll(',', '')` as a silent digit shift.
        if (seenDecimal) continue;
        out.write(ch);
        continue;
      }

      final code = ch.codeUnitAt(0);
      if (code < 0x30 || code > 0x39) continue;

      if (seenDecimal) {
        if (decimals >= maxDecimals) continue;
        decimals++;
      }
      out.write(ch);
    }

    return out.toString();
  }
}
