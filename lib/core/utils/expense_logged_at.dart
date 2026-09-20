import 'package:intl/intl.dart';

/// Local wall-clock for an expense [DateTime], whether it was stored as UTC
/// (`...Z`) or as a timezone-less ISO string.
DateTime expenseLocal(DateTime d) => d.isUtc ? d.toLocal() : d;

bool sameCalendarDay(DateTime a, DateTime b) {
  final x = expenseLocal(a);
  final y = expenseLocal(b);
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

/// Local midnight of [d]'s wall-clock calendar day.
DateTime localCalendarDay(DateTime d) {
  final l = expenseLocal(d);
  return DateTime(l.year, l.month, l.day);
}

/// Calendar days from [date] to [now] on the device clock.
/// `0` = same local day, `1` = yesterday, negative = future.
int calendarDayDelta(DateTime date, DateTime now) =>
    localCalendarDay(now).difference(localCalendarDay(date)).inDays;

bool sameCalendarMonth(DateTime a, DateTime b) {
  final x = expenseLocal(a);
  final y = expenseLocal(b);
  return x.year == y.year && x.month == y.month;
}

/// Parses an expense ISO stamp and checks the local calendar day of [now].
bool expenseIsoOnLocalDay(String iso, DateTime now) {
  final d = DateTime.tryParse(iso);
  if (d == null) return false;
  return sameCalendarDay(d, now);
}

bool expenseIsoInLocalMonth(String iso, DateTime now) {
  final d = DateTime.tryParse(iso);
  if (d == null) return false;
  return sameCalendarMonth(d, now);
}

/// True when [d] is an exact midnight or noon with no sub-minute fragment.
///
/// Add/SMS historically wrote `DateTime(y, m, d, 12)` so every row rendered
/// as 12:00 PM. `DateTime.now()` always carries milliseconds, so a genuine
/// lunch at noon still formats as a clock.
bool isDayAnchor(DateTime d) {
  return (d.hour == 0 || d.hour == 12) &&
      d.minute == 0 &&
      d.second == 0 &&
      d.millisecond == 0 &&
      d.microsecond == 0;
}

bool isDateOnlyIso(String raw) =>
    RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw.trim());

DateTime combineCalendarDay(DateTime day, DateTime clock) {
  final d = expenseLocal(day);
  final c = expenseLocal(clock);
  return DateTime(
    d.year,
    d.month,
    d.day,
    c.hour,
    c.minute,
    c.second,
    c.millisecond,
  );
}

/// Picked calendar day + the moment the user actually logged or edited.
///
/// Today keeps the live clock so the Tracker row reads as "just now". Any
/// other day still uses that live clock on the chosen date so we never write
/// a dummy noon.
DateTime expenseTimestampOnPickedDay(DateTime picked, {DateTime? now}) {
  final n = now ?? DateTime.now();
  if (sameCalendarDay(picked, n)) return n;
  return combineCalendarDay(picked, n);
}

/// SMS row timestamp: trust the bank's calendar day when it is within one day
/// of the phone's received day (so a dd/mm vs mm/dd swap cannot hide Today),
/// and stamp the clock from the bank when it sent one, otherwise from when
/// the SMS arrived.
DateTime smsExpenseLoggedAt(DateTime txn, DateTime received) {
  final tDay = DateTime(txn.year, txn.month, txn.day);
  final rDay = DateTime(received.year, received.month, received.day);
  final day = (tDay.difference(rDay).inDays).abs() > 1 ? received : txn;
  final txnHasClock = txn.hour != 0 || txn.minute != 0 || txn.second != 0;
  final clock = txnHasClock ? txn : received;
  return combineCalendarDay(day, clock);
}

/// `Auto Detected · 13 Sep 2026, 3:14 PM` as written by [autoDetectedStamp].
DateTime? parseAutoDetectedStamp(String hay) {
  final m = _stamp.firstMatch(hay);
  if (m == null) return null;
  final day = int.tryParse(m.group(1)!) ?? 1;
  final month = _months[m.group(2)!];
  final year = int.tryParse(m.group(3)!) ?? 0;
  var hour = int.tryParse(m.group(4)!) ?? 0;
  final minute = int.tryParse(m.group(5)!) ?? 0;
  final ampm = m.group(6)!;
  if (month == null || year <= 0) return null;
  if (ampm == 'AM') {
    if (hour == 12) hour = 0;
  } else if (hour != 12) {
    hour += 12;
  }
  return DateTime(year, month, day, hour, minute);
}

bool expenseStampHasClock(String dateStr, {String comments = ''}) {
  final stored = DateTime.tryParse(dateStr);
  if (stored == null) return false;
  if (!isDateOnlyIso(dateStr) && !isDayAnchor(stored)) return true;
  final stamp = parseAutoDetectedStamp(comments);
  return stamp != null && sameCalendarDay(stamp, stored);
}

/// Best local timestamp to show on a row: stored clock, else the Auto
/// Detected stamp when it is still the same calendar day (unedited SMS).
DateTime resolveExpenseLoggedAt(String dateStr, {String comments = ''}) {
  final stored = DateTime.tryParse(dateStr);
  if (stored == null) return DateTime.fromMillisecondsSinceEpoch(0);
  if (!isDateOnlyIso(dateStr) && !isDayAnchor(stored)) {
    return expenseLocal(stored);
  }
  final stamp = parseAutoDetectedStamp(comments);
  if (stamp != null && sameCalendarDay(stamp, stored)) {
    return combineCalendarDay(stored, stamp);
  }
  return expenseLocal(stored);
}

/// Tracker / list label under the amount.
///
/// * Real logged or SMS-recovered clock → `3:14 pm`
/// * Dummy noon/midnight after the user changed the date (stamp day no
///   longer matches) → `12 Sep` so the edited date is visible
String formatExpenseStamp(
  String dateStr, {
  String comments = '',
  DateTime? now,
}) {
  final stored = DateTime.tryParse(dateStr);
  if (stored == null) return '';
  final at = resolveExpenseLoggedAt(dateStr, comments: comments);
  final n = now ?? DateTime.now();
  try {
    if (!expenseStampHasClock(dateStr, comments: comments)) {
      final sameYear = expenseLocal(stored).year == n.year;
      return DateFormat(
        sameYear ? 'd MMM' : 'd MMM y',
        'en_IN',
      ).format(expenseLocal(stored));
    }
    return DateFormat('h:mm a', 'en_IN').format(at);
  } catch (_) {
    if (!expenseStampHasClock(dateStr, comments: comments)) {
      final d = expenseLocal(stored);
      return '${d.day}/${d.month}/${d.year}';
    }
    return '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
  }
}

/// Longer "when" line for detail sheets: `13 Sep · 3:14 pm`, or just the
/// date when the clock was a dummy noon.
String formatExpenseWhen(
  String dateStr, {
  String comments = '',
  DateTime? now,
}) {
  final stored = DateTime.tryParse(dateStr);
  if (stored == null) return dateStr;
  final at = resolveExpenseLoggedAt(dateStr, comments: comments);
  final n = now ?? DateTime.now();
  try {
    final sameYear = at.year == n.year;
    final datePart = DateFormat(
      sameYear ? 'd MMM' : 'd MMM y',
      'en_IN',
    ).format(at);
    if (!expenseStampHasClock(dateStr, comments: comments)) return datePart;
    final timePart = DateFormat('h:mm a', 'en_IN').format(at);
    return '$datePart · $timePart';
  } catch (_) {
    return formatExpenseStamp(dateStr, comments: comments, now: now);
  }
}

const _months = {
  'Jan': 1,
  'Feb': 2,
  'Mar': 3,
  'Apr': 4,
  'May': 5,
  'Jun': 6,
  'Jul': 7,
  'Aug': 8,
  'Sep': 9,
  'Oct': 10,
  'Nov': 11,
  'Dec': 12,
};

final _stamp = RegExp(
  r'Auto Detected · (\d{1,2}) ([A-Za-z]{3}) (\d{4}), (\d{1,2}):(\d{2}) (AM|PM)',
);
