import 'package:intl/intl.dart';

/// Parses an ISO-8601 date/time string without ever throwing.
///
/// Returns the Unix epoch as a stable, sortable fallback when [raw] is null,
/// empty, or malformed (which can happen for corrupted/partial server-synced
/// rows). This lets downstream date math, sorting, and charts degrade
/// gracefully instead of throwing a [FormatException] mid-build and taking
/// down the entire screen.
DateTime safeParseDate(String raw) =>
    DateTime.tryParse(raw) ?? DateTime.fromMillisecondsSinceEpoch(0);

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

String formatDate(String dateStr) {
  final date = DateTime.tryParse(dateStr);
  if (date == null) return dateStr;
  final now = DateTime.now();
  final diff = now.difference(date).inDays;

  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  // Only relative-label genuine recent-past dates. Future dates (diff < 0,
  // e.g. projections) and anything >= 7 days fall through to an absolute date
  // so we never render "-5 days ago".
  if (diff > 1 && diff < 7) return '$diff days ago';

  try {
    final sameYear = date.year == now.year;
    return DateFormat(sameYear ? 'd MMM' : 'd MMM y', 'en_IN').format(date);
  } catch (_) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

String formatTime(String dateStr) {
  final date = DateTime.tryParse(dateStr);
  if (date == null) return '';
  try {
    return DateFormat('hh:mm a', 'en_IN').format(date);
  } catch (_) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

String formatRelativeTime(DateTime date) {
  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} hr ago';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  return DateFormat('d MMM', 'en_IN').format(date);
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
