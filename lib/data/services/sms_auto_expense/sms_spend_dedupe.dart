import '../../../core/utils/expense_logged_at.dart';
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

  static DateTime? parseStamp(String comments, String description) =>
      parseAutoDetectedStamp('$comments $description');

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
