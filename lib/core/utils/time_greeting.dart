/// Time-of-day greeting used on the Expense home header.
///
/// Local device clock. Minute/second do not matter — only the hour:
///   05:00–11:59  Good morning
///   12:00–16:59  Good afternoon
///   17:00–20:59  Good evening
///   21:00–04:59  Good night
String greetingForDateTime(DateTime now) => greetingForHour(now.hour);

/// Same buckets as [greetingForDateTime], with [hour] clamped to 0–23 so a
/// bad clock value cannot crash the header.
String greetingForHour(int hour) {
  final h = hour.clamp(0, 23);
  if (h >= 5 && h < 12) return 'Good morning';
  if (h >= 12 && h < 17) return 'Good afternoon';
  if (h >= 17 && h < 21) return 'Good evening';
  return 'Good night';
}

/// Next local instant the Expense UI must rebuild: greeting buckets
/// (05:00 / 12:00 / 17:00 / 21:00) and midnight (today's spend rolls over).
DateTime nextUiClockTick(DateTime now) {
  final day = DateTime(now.year, now.month, now.day);
  final candidates = <DateTime>[
    day.add(const Duration(hours: 5)),
    day.add(const Duration(hours: 12)),
    day.add(const Duration(hours: 17)),
    day.add(const Duration(hours: 21)),
    day.add(const Duration(days: 1)),
  ];
  for (final t in candidates) {
    if (t.isAfter(now)) return t;
  }
  return day.add(const Duration(days: 1, hours: 5));
}

String _cleanNameToken(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return '';
  final first = trimmed.split(RegExp(r'\s+')).first;
  return first.replaceAll(RegExp(r'\.+$'), '');
}

/// First name for the header. Empty / whitespace / all-dots falls back to
/// [fallback], then to `Monish`, so the header never renders a lone `.`
String formatHeaderName(String? raw, {String fallback = 'Monish'}) {
  var s = _cleanNameToken(raw ?? '');
  if (s.isEmpty) s = _cleanNameToken(fallback);
  if (s.isEmpty) s = 'Monish';
  return s;
}

/// Display line: `Monish.`
String headerNameLine(String? raw, {String fallback = 'Monish'}) =>
    '${formatHeaderName(raw, fallback: fallback)}.';
