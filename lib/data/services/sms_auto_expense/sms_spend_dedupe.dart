import '../../../domain/entities/expense_entities.dart';
import 'sms_intake_policy.dart';
import 'sms_models.dart';

/// Outcome of matching an incoming SMS debit against recently saved rows.
class SmsDedupeHit {
  const SmsDedupeHit({required this.existing, required this.upgrade});

  final Expense existing;

  /// Incoming SMS has a real merchant and [existing] was the placeholder
  /// "Auto Detected" row from the collect/request SMS. Update that row.
  final bool upgrade;
}

/// Same UPI often produces two SMS: a collect/request (empty merchant) and
/// a later spent/debited alert (named merchant, sometimes another bank).
/// Native dedupe is per-sender, so Axis + HDFC both land. This collapses them.
class SmsSpendDedupe {
  const SmsSpendDedupe._();

  static const window = Duration(minutes: 45);
  static const amountEpsilon = 0.05;

  static bool amountsMatch(double a, double b) =>
      (a - b).abs() <= amountEpsilon;

  static const _months = {
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

  static final _stamp = RegExp(
    r'Auto Detected · (\d{1,2}) ([A-Za-z]{3}) (\d{4}), (\d{1,2}):(\d{2}) (AM|PM)',
  );

  /// Incoming SMS may fill in a blank Others row. Never rewrite a category
  /// the user already picked in the editor (Others → Medical must stick).
  static bool mayAutofillCategory(Expense existing) =>
      !existing.isManualCategory && existing.category == 'Others';

  static bool isSmsOrigin(Expense e) {
    if (e.id.startsWith('sms-')) return true;
    final hay = '${e.comments} ${e.description}';
    return hay.contains('Auto Detected');
  }

  static bool isPlaceholderDescription(String description) {
    final d = description.trim();
    return d.isEmpty || d.startsWith('Auto Detected');
  }

  static String normalizeMerchant(String raw) {
    var s = raw.trim().toLowerCase();
    if (s.contains('@')) s = s.split('@').first;
    return s.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  /// Empty vs named is the collect→success pair. Two different shop names
  /// are two spends.
  static bool merchantsCompatible(String a, String b) {
    final na = isPlaceholderDescription(a) ? '' : normalizeMerchant(a);
    final nb = isPlaceholderDescription(b) ? '' : normalizeMerchant(b);
    if (na.isEmpty || nb.isEmpty) return true;
    if (na == nb) return true;
    if (na.length >= 4 && nb.length >= 4 && (na.contains(nb) || nb.contains(na))) {
      return true;
    }
    return false;
  }

  static DateTime? parseStamp(String comments, String description) {
    final hay = '$comments $description';
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

  static SmsDedupeHit? match({
    required ParsedSmsDebit incoming,
    required String incomingDescription,
    required DateTime receivedAt,
    required List<Expense> recent,
  }) {
    final incomingDay = SmsIntakePolicy.expenseDay(
      incoming.transactionDate,
      receivedAt,
    );
    final incomingMerchant = incoming.hasMerchant &&
            !isPlaceholderDescription(incoming.merchantRaw)
        ? incoming.merchantRaw
        : (isPlaceholderDescription(incomingDescription) ? '' : incomingDescription);

    for (final e in recent) {
      if (!isSmsOrigin(e)) continue;
      if (!amountsMatch(e.amount, incoming.amount)) continue;
      final existingDay = DateTime.tryParse(e.date);
      if (existingDay != null) {
        final sameDay = existingDay.year == incomingDay.year &&
            existingDay.month == incomingDay.month &&
            existingDay.day == incomingDay.day;
        if (!sameDay) continue;
      }
      if (!merchantsCompatible(e.description, incomingMerchant)) continue;

      final stamped = parseStamp(e.comments, e.description);
      if (stamped != null &&
          receivedAt.difference(stamped).abs() > window) {
        continue;
      }

      final existingPlaceholder = isPlaceholderDescription(e.description);
      final incomingNamed = incoming.hasMerchant &&
          !isPlaceholderDescription(incomingDescription);
      return SmsDedupeHit(
        existing: e,
        upgrade: incomingNamed && existingPlaceholder,
      );
    }
    return null;
  }
}
