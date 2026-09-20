// Parsing helpers for the `own` rephrase platform, where the user supplies both
// the instruction and the text in one free-form string.
//
// Shared by the Tutor Rephrase tab (whole input typed in one field) and the
// floating bubble (text comes from the focused field, only the instruction is
// typed).

final _ownDoubleQuote = RegExp(r'"([^"]+)"');
final _ownSingleQuote = RegExp(r"(?<![a-zA-Z])'([^']+)'");
final _ownSmartQuote = RegExp(r'\u201c([^\u201d]+)\u201d');
final _ownPrefixStrip =
    RegExp(r'^rephrase\b\s*(this\s+)?(it\s+)?(to\s+|as\s+)?', caseSensitive: false);

/// Drops a leading `rephrase [this|it] [to|as]` so `rephrase to formal tone`
/// becomes `formal tone`.
String stripRephrasePrefix(String raw) =>
    raw.trim().replaceFirst(_ownPrefixStrip, '').trim();

/// Splits `rephrase to formal tone "please send the report"` into
/// `(intent: 'formal tone', text: 'please send the report')`.
///
/// With no quotes the whole (prefix-stripped) string is the text and there is
/// no explicit intent.
({String intent, String text}) parseOwnRephraseInput(String raw) {
  final input = raw.trim();
  if (input.isEmpty) return (intent: '', text: '');

  for (final pattern in [_ownDoubleQuote, _ownSingleQuote, _ownSmartQuote]) {
    final match = pattern.firstMatch(input);
    if (match != null) {
      final quoted = match.group(1)!.trim();
      if (quoted.isEmpty) continue;

      final before = input.substring(0, match.start).trim();
      final intent = before.replaceFirst(_ownPrefixStrip, '').trim();
      return (intent: intent, text: quoted);
    }
  }

  // No quotes found — treat as plain text with no explicit intent
  final stripped = input.replaceFirst(_ownPrefixStrip, '').trim();
  if (stripped.length < input.length) {
    return (intent: '', text: stripped);
  }
  return (intent: '', text: input);
}
