// Verifies formatRelativeTime handles the full spectrum the new date picker can
// produce: real-time entries, backdated ones (yesterday / last month) and
// forward-dated ones (tomorrow / next month). Future dates must never fall
// through to the "Just now / X ago" branch (the old bug).

import 'package:ai_nexus/core/utils/currency_formatter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en_IN');
  });

  test('recent past uses relative phrasing', () {
    final now = DateTime(2026, 9, 17, 15, 0);
    expect(formatRelativeTime(now.subtract(const Duration(seconds: 10)), now: now),
        'Just now');
    expect(formatRelativeTime(now.subtract(const Duration(minutes: 5)), now: now),
        '5 min ago');
    expect(
        formatRelativeTime(now.subtract(const Duration(hours: 3)), now: now),
        '3 hr ago');
  });

  test('previous calendar day is Yesterday even within 24 hours', () {
    final now = DateTime(2026, 9, 17, 13, 29);
    final yesterdayAfternoon = DateTime(2026, 9, 16, 13, 37);
    expect(formatRelativeTime(yesterdayAfternoon, now: now), 'Yesterday');
    expect(formatCalendarDayLabel(yesterdayAfternoon, now: now), 'Yesterday');
    expect(
      formatCalendarDayLabel(DateTime(2026, 9, 17, 8, 0), now: now),
      'Today',
    );
  });

  test('same calendar day still uses hour-ago phrasing', () {
    final now = DateTime(2026, 9, 17, 13, 29);
    expect(
      formatRelativeTime(DateTime(2026, 9, 17, 10, 29), now: now),
      '3 hr ago',
    );
    expect(
      formatCalendarDayLabel(DateTime(2026, 9, 17, 10, 29), now: now),
      'Today',
    );
  });

  test('yesterday and a few days ago', () {
    final now = DateTime.now();
    expect(formatRelativeTime(now.subtract(const Duration(hours: 30))),
        'Yesterday');
    expect(formatRelativeTime(now.subtract(const Duration(days: 3))),
        '3 days ago');
  });

  test('older past falls back to an absolute date (never a huge day count)', () {
    final now = DateTime.now();
    final label = formatRelativeTime(now.subtract(const Duration(days: 40)));
    expect(label.contains('ago'), isFalse);
    expect(label.contains('days'), isFalse);
  });

  test('future dates never read as "ago"', () {
    final now = DateTime.now();
    // Tomorrow.
    expect(
      formatRelativeTime(DateTime(now.year, now.month, now.day)
          .add(const Duration(days: 1, hours: 12))),
      'Tomorrow',
    );
    // A few days out.
    final inThree = formatRelativeTime(
        DateTime(now.year, now.month, now.day).add(const Duration(days: 3)));
    expect(inThree, 'In 3 days');
    // Next month → absolute label, definitely not "ago" / "Just now".
    final nextMonth = formatRelativeTime(DateTime(now.year, now.month + 1, 1));
    expect(nextMonth.contains('ago'), isFalse);
    expect(nextMonth, isNot('Just now'));
  });
}
