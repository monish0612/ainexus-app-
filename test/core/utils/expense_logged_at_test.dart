import 'dart:io';

import 'package:ai_nexus/core/utils/expense_logged_at.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en_IN');
  });

  final noon = DateTime(2026, 9, 13, 12);
  const stamp = 'Auto Detected · 13 Sep 2026, 3:14 PM';

  group('smsExpenseLoggedAt', () {
    test('uses SMS arrival clock on the bank day', () {
      final received = DateTime(2026, 9, 13, 15, 14, 2);
      expect(
        smsExpenseLoggedAt(DateTime(2026, 9, 13), received),
        DateTime(2026, 9, 13, 15, 14, 2),
      );
    });

    test('keeps a bank ISO clock', () {
      final received = DateTime(2026, 9, 13, 15, 14);
      expect(
        smsExpenseLoggedAt(DateTime(2026, 9, 13, 8, 2, 11), received),
        DateTime(2026, 9, 13, 8, 2, 11),
      );
    });

    test('±1 day still trusts the bank day with the received clock', () {
      final received = DateTime(2026, 9, 13, 15, 14);
      expect(
        smsExpenseLoggedAt(DateTime(2026, 9, 12), received),
        DateTime(2026, 9, 12, 15, 14),
      );
    });

    test('wild dd/mm swap uses the received day so Today still shows it', () {
      final received = DateTime(2026, 9, 10, 15, 28);
      expect(
        smsExpenseLoggedAt(DateTime(2026, 10, 9), received),
        DateTime(2026, 9, 10, 15, 28),
      );
    });
  });

  group('parseAutoDetectedStamp', () {
    test('parses 12-hour AM/PM including noon and midnight', () {
      expect(
        parseAutoDetectedStamp('Auto Detected · 13 Sep 2026, 3:14 PM'),
        DateTime(2026, 9, 13, 15, 14),
      );
      expect(
        parseAutoDetectedStamp('Auto Detected · 13 Sep 2026, 12:00 PM'),
        DateTime(2026, 9, 13, 12),
      );
      expect(
        parseAutoDetectedStamp('Auto Detected · 13 Sep 2026, 12:05 AM'),
        DateTime(2026, 9, 13, 0, 5),
      );
      expect(
        parseAutoDetectedStamp('Auto Detected · 13 Sep 2026, 9:05 AM'),
        DateTime(2026, 9, 13, 9, 5),
      );
      expect(parseAutoDetectedStamp('no stamp here'), isNull);
    });
  });

  group('isDayAnchor', () {
    test('exact midnight and noon are anchors; live clocks are not', () {
      expect(isDayAnchor(DateTime(2026, 9, 13, 12)), isTrue);
      expect(isDayAnchor(DateTime(2026, 9, 13)), isTrue);
      expect(isDayAnchor(DateTime(2026, 9, 13, 12, 0, 0, 12)), isFalse);
      expect(isDayAnchor(DateTime(2026, 9, 13, 15, 14)), isFalse);
    });
  });

  group('formatExpenseStamp', () {
    test('recovers SMS clock from Auto Detected instead of dummy noon', () {
      final label = formatExpenseStamp(
        noon.toIso8601String(),
        comments: stamp,
        now: DateTime(2026, 9, 13, 16),
      );
      expect(label.toLowerCase(), contains('3:14'));
      expect(label.toLowerCase(), isNot(contains('12:00')));
    });

    test('after a date edit, dummy noon shows the edited date not 12:00 pm', () {
      final edited = DateTime(2026, 9, 12, 12);
      final label = formatExpenseStamp(
        edited.toIso8601String(),
        comments: stamp,
        now: DateTime(2026, 9, 13, 16),
      );
      expect(label.toLowerCase(), contains('12 sep'));
      expect(label.toLowerCase(), isNot(contains('12:00')));
    });

    test('live logged clock is shown as-is', () {
      final logged = DateTime(2026, 9, 13, 8, 20, 33, 12);
      final label = formatExpenseStamp(
        logged.toIso8601String(),
        comments: stamp,
        now: DateTime(2026, 9, 13, 16),
      );
      expect(label.toLowerCase(), contains('8:20'));
    });

    test('genuine noon with milliseconds still shows 12:00', () {
      final lunch = DateTime(2026, 9, 13, 12, 0, 0, 12);
      final label = formatExpenseStamp(
        lunch.toIso8601String(),
        comments: stamp,
        now: DateTime(2026, 9, 13, 16),
      );
      expect(label.toLowerCase(), contains('12:00'));
    });

    test('date-only ISO without a matching stamp is not 12:00 pm', () {
      final label = formatExpenseStamp(
        '2026-09-12',
        now: DateTime(2026, 9, 13, 16),
      );
      expect(label, isNotEmpty);
      expect(label.toLowerCase(), isNot(contains('12:00')));
    });

    test('malformed date does not throw', () {
      expect(formatExpenseStamp(''), '');
      expect(formatExpenseStamp('nope', comments: stamp), '');
    });

    test('edit modal keeps the original ISO on the same day', () {
      final src = File(
        'lib/presentation/screens/expense/modals/edit_expense_modal.dart',
      ).readAsStringSync();
      expect(src, contains('dateOnly(expenseLocal(parsed))'));
      expect(src, contains('sameCalendarDay(original, _selectedDate)'));
      expect(src, contains('expenseTimestampOnPickedDay(_selectedDate)'));
    });

    test('add modal stamps the live clock instead of noon', () {
      final src = File(
        'lib/presentation/screens/expense/modals/add_expense_modal.dart',
      ).readAsStringSync();
      expect(src, contains('expenseTimestampOnPickedDay(_selectedDate)'));
    });
  });

  group('formatExpenseWhen', () {
    test('SMS noon recovers clock on the longer when-line', () {
      final label = formatExpenseWhen(
        noon.toIso8601String(),
        comments: stamp,
        now: DateTime(2026, 9, 13, 16),
      );
      expect(label.toLowerCase(), contains('13 sep'));
      expect(label.toLowerCase(), contains('3:14'));
      expect(label.toLowerCase(), isNot(contains('12:00')));
    });

    test('edited dummy noon is date-only', () {
      final label = formatExpenseWhen(
        DateTime(2026, 9, 12, 12).toIso8601String(),
        comments: stamp,
        now: DateTime(2026, 9, 13, 16),
      );
      expect(label.toLowerCase(), contains('12 sep'));
      expect(label.contains('·'), isFalse);
    });
  });

  group('expenseTimestampOnPickedDay', () {
    test('today uses the live clock', () {
      final now = DateTime(2026, 9, 13, 16, 58, 7);
      expect(
        expenseTimestampOnPickedDay(DateTime(2026, 9, 13), now: now),
        now,
      );
    });

    test('other day uses the live clock on that calendar day', () {
      final now = DateTime(2026, 9, 13, 16, 58, 7);
      expect(
        expenseTimestampOnPickedDay(DateTime(2026, 9, 12), now: now),
        DateTime(2026, 9, 12, 16, 58, 7),
      );
    });
  });

  group('sameCalendarDay', () {
    test('UTC values compare on the local wall-clock day', () {
      final utc = DateTime.utc(2026, 9, 13, 6, 30);
      expect(sameCalendarDay(utc, utc.toLocal()), isTrue);
      expect(
        sameCalendarDay(DateTime(2026, 9, 13), DateTime(2026, 9, 13, 23, 59)),
        isTrue,
      );
      expect(
        sameCalendarDay(DateTime(2026, 9, 13), DateTime(2026, 9, 12, 23, 59)),
        isFalse,
      );
    });

    test('ISO stamps use the local calendar day, not a rolling 24h window', () {
      final now = DateTime(2026, 9, 17, 13, 29);
      expect(expenseIsoOnLocalDay('2026-09-16T13:37:00', now), isFalse);
      expect(expenseIsoOnLocalDay('2026-09-17T00:05:00', now), isTrue);
      expect(expenseIsoInLocalMonth('2026-09-16T13:37:00', now), isTrue);
      expect(calendarDayDelta(DateTime(2026, 9, 16, 13, 37), now), 1);
    });
  });
}
