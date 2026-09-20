import 'package:ai_nexus/core/utils/time_greeting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DateTime at(int hour, [int minute = 0, int second = 0]) =>
      DateTime(2026, 8, 21, hour, minute, second, 999);

  test('every hour 0–23 maps to the right greeting', () {
    const morning = {5, 6, 7, 8, 9, 10, 11};
    const afternoon = {12, 13, 14, 15, 16};
    const evening = {17, 18, 19, 20};
    for (var h = 0; h < 24; h++) {
      final g = greetingForHour(h);
      if (morning.contains(h)) {
        expect(g, 'Good morning', reason: 'hour $h');
      } else if (afternoon.contains(h)) {
        expect(g, 'Good afternoon', reason: 'hour $h');
      } else if (evening.contains(h)) {
        expect(g, 'Good evening', reason: 'hour $h');
      } else {
        expect(g, 'Good night', reason: 'hour $h');
      }
    }
  });

  test('boundaries use the hour, not the minute or millisecond', () {
    expect(greetingForDateTime(at(4, 59, 59)), 'Good night');
    expect(greetingForDateTime(at(5)), 'Good morning');
    expect(greetingForDateTime(at(11, 59, 59)), 'Good morning');
    expect(greetingForDateTime(at(12)), 'Good afternoon');
    expect(greetingForDateTime(at(16, 59, 59)), 'Good afternoon');
    expect(greetingForDateTime(at(17)), 'Good evening');
    expect(greetingForDateTime(at(20, 59, 59)), 'Good evening');
    expect(greetingForDateTime(at(21)), 'Good night');
    expect(greetingForDateTime(at(23, 59, 59)), 'Good night');
    expect(greetingForDateTime(at(0)), 'Good night');
  });

  test('leap day, DST-ish local timestamps, and UTC hours still bucket', () {
    expect(greetingForDateTime(DateTime(2024, 2, 29, 9)), 'Good morning');
    expect(greetingForDateTime(DateTime(2026, 3, 8, 2)), 'Good night');
    expect(
      greetingForDateTime(DateTime.utc(2026, 8, 21, 18)),
      'Good evening',
    );
  });

  test('out-of-range hours clamp instead of throwing', () {
    expect(greetingForHour(-1), 'Good night');
    expect(greetingForHour(-3), 'Good night');
    expect(greetingForHour(24), 'Good night');
    expect(greetingForHour(25), 'Good night');
    expect(greetingForHour(99), 'Good night');
  });

  test('nextUiClockTick hits greeting boundaries and midnight', () {
    expect(
      nextUiClockTick(DateTime(2026, 9, 16, 21, 5)),
      DateTime(2026, 9, 17),
    );
    expect(
      nextUiClockTick(DateTime(2026, 9, 17, 0, 0, 1)),
      DateTime(2026, 9, 17, 5),
    );
    expect(
      nextUiClockTick(DateTime(2026, 9, 17, 13, 29)),
      DateTime(2026, 9, 17, 17),
    );
  });

  test('formatHeaderName uses first token, strips dots, falls back', () {
    expect(formatHeaderName('Monish'), 'Monish');
    expect(formatHeaderName('Monish Kumar'), 'Monish');
    expect(formatHeaderName('Monish.'), 'Monish');
    expect(formatHeaderName('Monish...'), 'Monish');
    expect(formatHeaderName('  Monish.  '), 'Monish');
    expect(formatHeaderName('Monish\nKumar'), 'Monish');
    expect(formatHeaderName('Monish\tKumar'), 'Monish');
    expect(formatHeaderName(''), 'Monish');
    expect(formatHeaderName('   '), 'Monish');
    expect(formatHeaderName(null), 'Monish');
    expect(formatHeaderName('.'), 'Monish');
    expect(formatHeaderName('...'), 'Monish');
    expect(formatHeaderName('  ..  '), 'Monish');
    expect(formatHeaderName('', fallback: 'Guest'), 'Guest');
    expect(formatHeaderName('...', fallback: '...'), 'Monish');
    expect(formatHeaderName('மோனிஷ்'), 'மோனிஷ்');
  });

  test('headerNameLine always has exactly one trailing period', () {
    expect(headerNameLine('Monish'), 'Monish.');
    expect(headerNameLine('Monish.'), 'Monish.');
    expect(headerNameLine('Monish...'), 'Monish.');
    expect(headerNameLine(''), 'Monish.');
    expect(headerNameLine('.'), 'Monish.');
    expect(headerNameLine(null), 'Monish.');
  });
}
