import 'package:ai_nexus/core/utils/currency_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('safeParseDate', () {
    test('parses a valid ISO-8601 string', () {
      final d = safeParseDate('2024-03-15T10:30:00');
      expect(d.year, 2024);
      expect(d.month, 3);
      expect(d.day, 15);
    });

    test('returns epoch fallback for malformed / empty input (no throw)', () {
      expect(safeParseDate(''), DateTime.fromMillisecondsSinceEpoch(0));
      expect(safeParseDate('not-a-date'), DateTime.fromMillisecondsSinceEpoch(0));
      expect(safeParseDate('15/03/2024'), DateTime.fromMillisecondsSinceEpoch(0));
    });
  });

  group('formatDate — crash safety (regression)', () {
    test('malformed string is returned verbatim instead of throwing', () {
      // Before the fix DateTime.parse ran outside the try/catch and threw
      // FormatException, crashing the whole screen build.
      expect(() => formatDate('garbage'), returnsNormally);
      expect(formatDate('garbage'), 'garbage');
      expect(() => formatDate(''), returnsNormally);
    });

    test('today / yesterday / recent-past relative labels', () {
      final now = DateTime.now();
      expect(formatDate(now.toIso8601String()), 'Today');
      expect(
        formatDate(now.subtract(const Duration(days: 1)).toIso8601String()),
        'Yesterday',
      );
      expect(
        formatDate(now.subtract(const Duration(days: 3)).toIso8601String()),
        '3 days ago',
      );
    });

    test('yesterday afternoon is Yesterday after midnight, not Today', () {
      final now = DateTime(2026, 9, 17, 13, 29);
      expect(
        formatDate('2026-09-16T13:37:00', now: now),
        'Yesterday',
      );
      expect(
        formatDate('2026-09-17T08:00:00', now: now),
        'Today',
      );
    });

    test('future date never renders a negative "-N days ago" (regression)', () {
      final future = DateTime.now().add(const Duration(days: 40));
      final label = formatDate(future.toIso8601String());
      expect(label.startsWith('-'), isFalse);
      expect(label.contains('days ago'), isFalse);
    });
  });

  group('formatTime — crash safety (regression)', () {
    test('malformed string returns empty instead of throwing', () {
      expect(() => formatTime('nonsense'), returnsNormally);
      expect(formatTime('nonsense'), '');
      expect(formatTime(''), '');
    });

    test('valid timestamp returns a non-empty time string', () {
      expect(formatTime('2024-03-15T13:05:00'), isNotEmpty);
    });

    test('UTC Z timestamps render in local time', () {
      final utc = DateTime.utc(2026, 9, 13, 9, 44);
      final label = formatTime(utc.toIso8601String());
      expect(label, isNotEmpty);
      final local = utc.toLocal();
      expect(
        label.toLowerCase(),
        contains(local.minute.toString().padLeft(2, '0')),
      );
    });
  });

  group('formatCurrency — degenerate numbers (no throw)', () {
    test('zero / positive / negative render with rupee symbol', () {
      expect(formatCurrency(0), contains('₹'));
      expect(formatCurrency(1500), contains('₹'));
      expect(formatCurrency(-250).startsWith('-'), isTrue);
    });

    test('NaN and Infinity do not throw', () {
      expect(() => formatCurrency(double.nan), returnsNormally);
      expect(() => formatCurrency(double.infinity), returnsNormally);
      expect(() => formatCurrency(double.negativeInfinity), returnsNormally);
    });

    test('very large value does not throw', () {
      expect(() => formatCurrency(9999999999999), returnsNormally);
    });
  });

  group('formatCompactRupee', () {
    test('empty for zero, rupee for small, k and L for larger', () {
      expect(formatCompactRupee(0), '');
      expect(formatCompactRupee(219), '₹219');
      expect(formatCompactRupee(1200), '₹1.2k');
      expect(formatCompactRupee(12000), '₹12k');
      expect(formatCompactRupee(120000), '₹1.2L');
    });

    test('never throws on degenerate numbers', () {
      expect(() => formatCompactRupee(double.nan), returnsNormally);
      expect(() => formatCompactRupee(double.infinity), returnsNormally);
    });
  });

  group('formatBytes', () {
    test('scales across units', () {
      expect(formatBytes(512), '512 B');
      expect(formatBytes(2048), contains('KB'));
      expect(formatBytes(5 * 1048576), contains('MB'));
      expect(formatBytes(3 * 1073741824), contains('GB'));
    });
  });
}
