/// Locale-aware price grammar, ported from Droplert `ptParsePrice`.
///
/// Accepts `21,799.99` (US / IN with decimal point), `1.299,99` (EU),
/// `1 299,99` (FR / NBSP thousands) and Indian grouping `17,02,098.21`.
double? parsePrice(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final match = _priceRx.firstMatch(raw.replaceAll('\u00A0', ' '));
  if (match == null) return null;
  var s = match.group(0)!.replaceAll(RegExp(r'\s'), '');
  while (s.isNotEmpty && (s.endsWith('.') || s.endsWith(','))) {
    s = s.substring(0, s.length - 1);
  }
  if (s.isEmpty) return null;

  final negative = s.startsWith('-');
  if (negative) s = s.substring(1);

  final lastDot = s.lastIndexOf('.');
  final lastComma = s.lastIndexOf(',');
  String norm;
  if (lastDot < 0 && lastComma < 0) {
    norm = s;
  } else if (lastDot < 0) {
    norm = (s.length - lastComma - 1) <= 2
        ? s.replaceAll(',', '.').replaceAll(RegExp(r'\.(?=.*\.)'), '')
        : s.replaceAll(',', '');
  } else if (lastComma < 0) {
    norm = (s.length - lastDot - 1) <= 2
        ? s.replaceAll(RegExp(r'\.(?=.*\.)'), '')
        : s.replaceAll('.', '');
  } else if (lastDot > lastComma) {
    norm = s.replaceAll(',', '');
  } else {
    norm = s.replaceAll('.', '').replaceFirst(',', '.');
  }
  final n = double.tryParse(norm);
  if (n == null || !n.isFinite) return null;
  final signed = negative ? -n : n;
  if (signed <= 0 || signed >= 100000000) return null;
  return signed;
}

/// Every numeric candidate in [raw], in document order.
List<double> parseAllPrices(String raw) {
  final out = <double>[];
  final seen = <String>{};
  for (final m in _priceRx.allMatches(raw.replaceAll('\u00A0', ' '))) {
    final n = parsePrice(m.group(0));
    if (n == null) continue;
    final key = n.toStringAsFixed(2);
    if (seen.add(key)) out.add(n);
  }
  return out;
}

/// INR-style display: `₹ 2,499` or `₹ 2,499.50`.
String formatInr(double amount) {
  final hasPaise = (amount % 1).abs() > 0.001;
  final body = hasPaise
      ? amount.toStringAsFixed(2)
      : amount.toStringAsFixed(0);
  final parts = body.split('.');
  final whole = _indianGroup(parts[0]);
  if (parts.length == 1) return '₹ $whole';
  return '₹ $whole.${parts[1]}';
}

String _indianGroup(String digits) {
  final neg = digits.startsWith('-');
  var d = neg ? digits.substring(1) : digits;
  if (d.length <= 3) return neg ? '-$d' : d;
  final last3 = d.substring(d.length - 3);
  var rest = d.substring(0, d.length - 3);
  final chunks = <String>[];
  while (rest.length > 2) {
    chunks.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) chunks.insert(0, rest);
  final grouped = '${chunks.join(',')},$last3';
  return neg ? '-$grouped' : grouped;
}

final _priceRx = RegExp(
  r'-?'
  r'(?:'
  r'\d{1,3}(?:[., ]\d{2})+[.,]\d{3}(?:[.,]\d{1,2})?' // IN: 17,02,098.21
  r'|'
  r'\d{1,3}(?:[., ]\d{3})+(?:[.,]\d{1,2})?' // US/EU thousands
  r'|'
  r'\d+(?:[.,]\d{1,2})?'
  r')',
);
