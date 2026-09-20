import '../utils/expense_logged_at.dart';
import '../../domain/entities/expense_entities.dart';

/// Rupee amounts stay at two decimals so 10.1 + 20.2 never drifts.
double roundExpenseAmount(double n) {
  if (!n.isFinite) return 0;
  return (n * 100).round() / 100;
}

class ExpenseMergeException implements Exception {
  const ExpenseMergeException(this.message);
  final String message;

  @override
  String toString() => 'ExpenseMergeException: $message';
}

/// Pure plan for combining two or more expenses into one replacement row.
class ExpenseMergePlan {
  const ExpenseMergePlan({
    required this.sourceIds,
    required this.total,
    required this.loggedAt,
    required this.bank,
    required this.cardType,
    required this.defaultCategory,
    required this.count,
  });

  final List<String> sourceIds;
  final double total;
  final DateTime loggedAt;
  final String bank;
  final String cardType;
  final String defaultCategory;
  final int count;

  bool get canMerge => count >= 2 && total > 0 && sourceIds.length >= 2;
}

/// Latest wall-clock among [sources], using Auto Detected stamps when the
/// stored ISO is a dummy noon/midnight.
DateTime latestExpenseLoggedAt(Iterable<Expense> sources) {
  DateTime? best;
  for (final e in sources) {
    final t = resolveExpenseLoggedAt(e.date, comments: e.comments);
    if (best == null || t.isAfter(best)) best = t;
  }
  return best ?? DateTime.fromMillisecondsSinceEpoch(0);
}

/// Bank + card from the majority of rows; ties break toward the latest row.
({String bank, String cardType}) majorityBankCard(List<Expense> sources) {
  final latest = sources.reduce((a, b) {
    final cmp = resolveExpenseLoggedAt(a.date, comments: a.comments)
        .compareTo(resolveExpenseLoggedAt(b.date, comments: b.comments));
    return cmp >= 0 ? a : b;
  });
  final counts = <String, int>{};
  for (final e in sources) {
    final key = '${e.bank}\u0000${e.cardType}';
    counts[key] = (counts[key] ?? 0) + 1;
  }
  var bestKey = '${latest.bank}\u0000${latest.cardType}';
  var bestN = 0;
  counts.forEach((key, n) {
    if (n > bestN) {
      bestN = n;
      bestKey = key;
    } else if (n == bestN && key == '${latest.bank}\u0000${latest.cardType}') {
      bestKey = key;
    }
  });
  final parts = bestKey.split('\u0000');
  return (
    bank: parts.isNotEmpty && parts[0].isNotEmpty ? parts[0] : latest.bank,
    cardType: parts.length > 1 && parts[1].isNotEmpty ? parts[1] : latest.cardType,
  );
}

ExpenseMergePlan planExpenseMerge(List<Expense> sources) {
  final unique = <String, Expense>{};
  for (final e in sources) {
    final id = e.id.trim();
    if (id.isEmpty) continue;
    unique[id] = e;
  }
  if (unique.length < 2) {
    throw const ExpenseMergeException(
      'Select at least two expenses to merge',
    );
  }
  final rows = unique.values.toList(growable: false);
  // Round per row first so a NaN/Infinity amount cannot poison the fold.
  final total = roundExpenseAmount(
    rows.fold<double>(0, (s, e) => s + roundExpenseAmount(e.amount)),
  );
  if (total <= 0) {
    throw const ExpenseMergeException('Merged total must be greater than 0');
  }
  final loggedAt = latestExpenseLoggedAt(rows);
  final bankCard = majorityBankCard(rows);
  final cats = rows.map((e) => e.category.trim()).where((c) => c.isNotEmpty);
  final catSet = cats.toSet();
  final defaultCategory =
      catSet.length == 1 ? catSet.first : 'Others';
  return ExpenseMergePlan(
    sourceIds: rows.map((e) => e.id.trim()).toList(growable: false),
    total: total,
    loggedAt: loggedAt,
    bank: bankCard.bank,
    cardType: bankCard.cardType,
    defaultCategory: defaultCategory,
    count: rows.length,
  );
}

/// Picked calendar day keeps the merged clock (latest source time), never a
/// dummy noon.
DateTime mergeTimestampOnPickedDay(DateTime pickedDay, DateTime sourceClock) =>
    combineCalendarDay(pickedDay, sourceClock);

Expense composeMergedExpense({
  required ExpenseMergePlan plan,
  required String id,
  required String description,
  required String category,
  DateTime? pickedDay,
  String? bank,
  String? cardType,
  String? comments,
}) {
  final desc = description.trim();
  if (id.trim().isEmpty) {
    throw const ExpenseMergeException('Merged expense needs an id');
  }
  if (plan.sourceIds.contains(id)) {
    throw const ExpenseMergeException(
      'Merged expense cannot reuse a source id',
    );
  }
  if (desc.isEmpty) {
    throw const ExpenseMergeException('Enter a description');
  }
  var cat = category.trim();
  if (cat.isEmpty) cat = plan.defaultCategory;
  if (cat.isEmpty) cat = 'Others';
  if (!plan.canMerge) {
    throw const ExpenseMergeException('Select at least two expenses to merge');
  }
  final when = pickedDay == null
      ? plan.loggedAt
      : mergeTimestampOnPickedDay(pickedDay, plan.loggedAt);
  return Expense(
    id: id.trim(),
    amount: plan.total,
    description: desc,
    category: cat,
    bank: (bank ?? plan.bank).trim(),
    cardType: (cardType ?? plan.cardType).trim(),
    date: when.toIso8601String(),
    isManualCategory: true,
    comments: (comments ?? '').trim(),
  );
}
