import 'package:intl/intl.dart';

import 'expense_logged_at.dart';

/// Parses an ISO-8601 date/time string without ever throwing.
///
/// Returns the Unix epoch as a stable, sortable fallback when [raw] is null,
/// empty, or malformed (which can happen for corrupted/partial server-synced
/// rows). This lets downstream date math, sorting, and charts degrade
/// gracefully instead of throwing a [FormatException] mid-build and taking
/// down the entire screen.
DateTime safeParseDate(String raw) {
  final d = DateTime.tryParse(raw);
  if (d == null) return DateTime.fromMillisecondsSinceEpoch(0);
  return expenseLocal(d);
}

NumberFormat? _inrFormat;
NumberFormat? _inrFormatDecimal;

NumberFormat get _fmt {
  return _inrFormat ??= NumberFormat.currency(
    symbol: '₹',
    locale: 'en_IN',
    decimalDigits: 0,
  );
}

NumberFormat get _fmtDecimal {
  return _inrFormatDecimal ??= NumberFormat.currency(
    symbol: '₹',
    locale: 'en_IN',
    decimalDigits: 2,
  );
}

String formatCurrency(num amount, {bool showDecimal = false}) {
  final abs = amount.abs();
  try {
    final formatted = showDecimal ? _fmtDecimal.format(abs) : _fmt.format(abs);
    return amount < 0 ? '-$formatted' : formatted;
  } catch (_) {
    final str = showDecimal ? abs.toStringAsFixed(2) : abs.toStringAsFixed(0);
    return amount < 0 ? '-₹$str' : '₹$str';
  }
}

/// Compact rupee label for tight cells (heat calendar). Never throws.
///
/// 0 → `''`; under 1000 → `₹219`; 1k–99.9k → `₹1.2k`; 1L+ → `₹1.2L`.
String formatCompactRupee(num amount) {
  if (amount is double && (amount.isNaN || amount.isInfinite)) return '';
  final abs = amount.abs();
  if (abs <= 0) return '';
  final sign = amount < 0 ? '-' : '';
  try {
    if (abs >= 100000) {
      final lakh = abs / 100000;
      final body = lakh >= 10
          ? lakh.toStringAsFixed(0)
          : lakh.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
      return '$sign₹${body}L';
    }
    if (abs >= 1000) {
      final k = abs / 1000;
      final body = k >= 10
          ? k.toStringAsFixed(0)
          : k.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
      return '$sign₹${body}k';
    }
    return '$sign₹${abs.round()}';
  } catch (_) {
    return '';
  }
}

String formatDate(String dateStr, {DateTime? now}) {
  final date = DateTime.tryParse(dateStr);
  if (date == null) return dateStr;
  final n = now ?? DateTime.now();
  final local = expenseLocal(date);
  final nLocal = expenseLocal(n);
  final diff = calendarDayDelta(local, nLocal);

  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  // Only relative-label genuine recent-past dates. Future dates (diff < 0,
  // e.g. projections) and anything >= 7 days fall through to an absolute date
  // so we never render "-5 days ago".
  if (diff > 1 && diff < 7) return '$diff days ago';

  try {
    final sameYear = local.year == nLocal.year;
    return DateFormat(sameYear ? 'd MMM' : 'd MMM y', 'en_IN').format(local);
  } catch (_) {
    return '${local.day}/${local.month}/${local.year}';
  }
}

String formatTime(String dateStr) {
  final parsed = DateTime.tryParse(dateStr);
  if (parsed == null) return '';
  final date = parsed.isUtc ? parsed.toLocal() : parsed;
  try {
    return DateFormat('hh:mm a', 'en_IN').format(date);
  } catch (_) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

/// Group header for Tracker lists: calendar Today / Yesterday / `15 Sep`.
String formatCalendarDayLabel(DateTime date, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final local = expenseLocal(date);
  final nLocal = expenseLocal(n);
  final diff = calendarDayDelta(local, nLocal);
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  try {
    final sameYear = local.year == nLocal.year;
    return DateFormat(sameYear ? 'd MMM' : 'd MMM y', 'en_IN').format(local);
  } catch (_) {
    return '${local.day}/${local.month}/${local.year}';
  }
}

String formatRelativeTime(DateTime date, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final local = expenseLocal(date);
  final nLocal = expenseLocal(n);
  final dayDelta = calendarDayDelta(local, nLocal);
  String absLabel() => DateFormat(
        local.year == nLocal.year ? 'd MMM' : 'd MMM yyyy',
        'en_IN',
      ).format(local);

  // Future-dated entries (e.g. a next-month bill logged in advance).
  if (dayDelta < 0) {
    final days = -dayDelta;
    if (days == 1) return 'Tomorrow';
    if (days < 7) return 'In $days days';
    return absLabel();
  }

  if (dayDelta == 0) {
    final diff = nLocal.difference(local);
    if (diff.isNegative) return 'Later today';
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    return '${diff.inHours} hr ago';
  }
  if (dayDelta == 1) return 'Yesterday';
  if (dayDelta < 7) return '$dayDelta days ago';
  return absLabel();
}

String formatBytes(int bytes) {
  if (bytes >= 1073741824) {
    return '${(bytes / 1073741824).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1048576) {
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
}
