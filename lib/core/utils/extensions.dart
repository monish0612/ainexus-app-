import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

extension ContextExtensions on BuildContext {
  ThemeData get theme => Theme.of(this);
  TextTheme get textTheme => theme.textTheme;
  ColorScheme get colorScheme => theme.colorScheme;
  MediaQueryData get mediaQuery => MediaQuery.of(this);
  double get screenWidth => mediaQuery.size.width;
  double get screenHeight => mediaQuery.size.height;
  EdgeInsets get padding => mediaQuery.padding;
  bool get isDark => theme.brightness == Brightness.dark;
}

final NumberFormat _inrCurrency = NumberFormat.currency(
  symbol: '₹',
  locale: 'en_IN',
  decimalDigits: 0,
);

final NumberFormat _inrCompactCurrency = NumberFormat.compactCurrency(
  symbol: '₹',
  locale: 'en_IN',
  decimalDigits: 0,
);

extension DoubleExtensions on double {
  String toCurrency({String symbol = '₹', String locale = 'en_IN'}) {
    if (symbol == '₹' && locale == 'en_IN') {
      return _inrCurrency.format(this);
    }
    return NumberFormat.currency(
      symbol: symbol,
      locale: locale,
      decimalDigits: 0,
    ).format(this);
  }

  String toCompactCurrency({String symbol = '₹', String locale = 'en_IN'}) {
    if (symbol == '₹' && locale == 'en_IN') {
      return _inrCompactCurrency.format(this);
    }
    return NumberFormat.compactCurrency(
      symbol: symbol,
      locale: locale,
      decimalDigits: 0,
    ).format(this);
  }

  String toPercentage({int decimals = 1}) {
    return '${toStringAsFixed(decimals)}%';
  }
}

extension StringExtensions on String {
  String get capitalize {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }

  String get initials {
    final parts = trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return isNotEmpty ? this[0].toUpperCase() : '';
  }
}

extension DateTimeExtensions on DateTime {
  String get timeAgo {
    final now = DateTime.now();
    final diff = now.difference(this);

    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(this);
  }

  String get formatted => DateFormat('MMM d, yyyy').format(this);
  String get shortDate => DateFormat('MMM d').format(this);
  String get time => DateFormat('HH:mm').format(this);
}

extension ColorExtensions on Color {
  Color get withHalfOpacity => withValues(alpha: 0.5);
}
