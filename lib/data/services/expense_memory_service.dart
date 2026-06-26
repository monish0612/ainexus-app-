import 'package:drift/drift.dart';

import '../../core/services/telegram_logger.dart';
import '../../domain/entities/expense_entities.dart' as domain;
import '../local/database/app_database.dart' as db;

/// A single (month, category) rollup bucket from the memory layer.
typedef MemoryBucket = ({String month, String category, double total, int count});

/// One month's total spend, used for the trend line.
typedef MonthTotal = ({String month, double total});

/// One category's total spend, used for the "biggest drain" facts.
typedef CategoryTotal = ({String category, double total, int count});

/// Compact, derived snapshot of the user's whole spending history, computed
/// from the (tiny) memory-layer rollup rather than the raw expenses table.
///
/// This is the "context" the AI recommendation engine reasons over: it is
/// constant-cost to build regardless of how many base rows exist, which is
/// what makes the feature scale to very large histories. Every field here is
/// a real, computed number — the LLM never invents any of these.
class MemoryFacts {
  const MemoryFacts({
    required this.lifetimeTotal,
    required this.lifetimeCount,
    required this.monthsTracked,
    required this.currentMonth,
    required this.currentMonthTotal,
    required this.previousMonthTotal,
    required this.avgMonthlyTotal,
    required this.topCategoriesAllTime,
    required this.topCategoriesCurrentMonth,
    required this.monthlyTrend,
  });

  /// Total spend across all months/categories on record.
  final double lifetimeTotal;

  /// Total number of expenses across all buckets.
  final int lifetimeCount;

  /// Number of distinct months that have at least one expense.
  final int monthsTracked;

  /// 'YYYY-MM' for "now" (the month the snapshot was taken in).
  final String currentMonth;

  /// Spend in [currentMonth].
  final double currentMonthTotal;

  /// Spend in the month immediately before [currentMonth].
  final double previousMonthTotal;

  /// Mean spend per tracked month (lifetimeTotal / monthsTracked).
  final double avgMonthlyTotal;

  /// Categories by all-time spend, highest first (top 5).
  final List<CategoryTotal> topCategoriesAllTime;

  /// Categories by spend in [currentMonth], highest first (top 5).
  final List<CategoryTotal> topCategoriesCurrentMonth;

  /// Per-month totals for the most recent 6 months, oldest first.
  final List<MonthTotal> monthlyTrend;

  bool get isEmpty => lifetimeCount == 0;

  /// Month-over-month delta for the current vs previous month.
  double get momDelta => currentMonthTotal - previousMonthTotal;

  /// Builds the snapshot from the raw rollup buckets. Pure — fully testable.
  factory MemoryFacts.fromBuckets(
    List<MemoryBucket> buckets, {
    required DateTime now,
  }) {
    final currentMonth = _monthKey(now);
    final previousMonth = _monthKey(DateTime(now.year, now.month - 1));

    var lifetimeTotal = 0.0;
    var lifetimeCount = 0;
    final byMonth = <String, double>{};
    final byCategoryAll = <String, ({double total, int count})>{};
    final byCategoryCurrent = <String, ({double total, int count})>{};

    for (final b in buckets) {
      lifetimeTotal += b.total;
      lifetimeCount += b.count;
      byMonth.update(b.month, (v) => v + b.total, ifAbsent: () => b.total);
      byCategoryAll.update(
        b.category,
        (v) => (total: v.total + b.total, count: v.count + b.count),
        ifAbsent: () => (total: b.total, count: b.count),
      );
      if (b.month == currentMonth) {
        byCategoryCurrent.update(
          b.category,
          (v) => (total: v.total + b.total, count: v.count + b.count),
          ifAbsent: () => (total: b.total, count: b.count),
        );
      }
    }

    final monthsTracked = byMonth.length;
    final sortedMonths = byMonth.keys.toList()..sort();
    final trend = sortedMonths
        .map((m) => (month: m, total: byMonth[m] ?? 0.0))
        .toList();
    final recentTrend =
        trend.length > 6 ? trend.sublist(trend.length - 6) : trend;

    List<CategoryTotal> topOf(Map<String, ({double total, int count})> m) {
      final list = m.entries
          .map((e) =>
              (category: e.key, total: e.value.total, count: e.value.count))
          .toList()
        ..sort((a, b) => b.total.compareTo(a.total));
      return list.take(5).toList();
    }

    return MemoryFacts(
      lifetimeTotal: lifetimeTotal,
      lifetimeCount: lifetimeCount,
      monthsTracked: monthsTracked,
      currentMonth: currentMonth,
      currentMonthTotal: byMonth[currentMonth] ?? 0.0,
      previousMonthTotal: byMonth[previousMonth] ?? 0.0,
      avgMonthlyTotal: monthsTracked == 0 ? 0.0 : lifetimeTotal / monthsTracked,
      topCategoriesAllTime: topOf(byCategoryAll),
      topCategoriesCurrentMonth: topOf(byCategoryCurrent),
      monthlyTrend: recentTrend,
    );
  }

  /// An empty snapshot for the "no data yet" case.
  factory MemoryFacts.empty(DateTime now) =>
      MemoryFacts.fromBuckets(const [], now: now);

  static String _monthKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
}

/// Maintains the continuously-updated memory layer (the
/// `expense_monthly_category` rollup) and derives a [MemoryFacts] snapshot from
/// it.
///
/// Design goals:
/// - O(1) per write: [applyDelta] only touches the affected (month, category)
///   bucket(s), so it stays fast no matter how large the expense history grows.
/// - Self-healing: [recompute] rebuilds the whole rollup from `expenses` in a
///   single GROUP BY (used after a server pull-sync or as a repair).
/// - Never authoritative: the rollup is a derived cache; the `expenses` table
///   is always the source of truth, so a memory error can never corrupt data.
class ExpenseMemoryService {
  ExpenseMemoryService(this._db);

  final db.AppDatabase _db;

  /// Apply the effect of an add ([newExpense] only), a delete ([oldExpense]
  /// only), or an update (both — handles category/month changes correctly).
  Future<void> applyDelta({
    domain.Expense? oldExpense,
    domain.Expense? newExpense,
  }) async {
    await _db.transaction(() async {
      if (oldExpense != null) {
        final m = _month(oldExpense.date);
        if (m != null) {
          await _adjust(m, oldExpense.category, -oldExpense.amount, -1);
        }
      }
      if (newExpense != null) {
        final m = _month(newExpense.date);
        if (m != null) {
          await _adjust(m, newExpense.category, newExpense.amount, 1);
        }
      }
    });
  }

  /// Rebuild the entire rollup from the `expenses` table. Cheap relative to its
  /// frequency (migration / full server-sync / clear), and keeps the cache
  /// exactly consistent with the source of truth.
  Future<void> recompute() async {
    await _db.transaction(() async {
      await _db.delete(_db.expenseMonthlyCategory).go();
      await _db.customStatement(
        'INSERT INTO expense_monthly_category (month, category, total, count) '
        'SELECT substr(date, 1, 7) AS month, category, '
        'SUM(amount) AS total, COUNT(id) AS count '
        'FROM expenses '
        'WHERE date IS NOT NULL AND length(date) >= 7 '
        'GROUP BY substr(date, 1, 7), category',
      );
    });
  }

  /// Build the compact [MemoryFacts] snapshot from the rollup. Reads only the
  /// (small) rollup table, never the raw expenses, so it is instant.
  Future<MemoryFacts> snapshot({DateTime? now}) async {
    try {
      final rows = await _db.select(_db.expenseMonthlyCategory).get();
      final buckets = rows
          .map((r) => (
                month: r.month,
                category: r.category,
                total: r.total,
                count: r.count,
              ))
          .toList();
      return MemoryFacts.fromBuckets(buckets, now: now ?? DateTime.now());
    } catch (e) {
      TLog.w('ExpenseMemory', 'snapshot failed', error: e);
      return MemoryFacts.empty(now ?? DateTime.now());
    }
  }

  Future<void> _adjust(
    String month,
    String category,
    double amountDelta,
    int countDelta,
  ) async {
    final existing = await (_db.select(_db.expenseMonthlyCategory)
          ..where((t) => t.month.equals(month) & t.category.equals(category)))
        .getSingleOrNull();
    final newCount = (existing?.count ?? 0) + countDelta;
    if (newCount <= 0) {
      await (_db.delete(_db.expenseMonthlyCategory)
            ..where((t) => t.month.equals(month) & t.category.equals(category)))
          .go();
      return;
    }
    var newTotal = (existing?.total ?? 0) + amountDelta;
    if (newTotal < 0) newTotal = 0; // guard against float drift
    await _db.into(_db.expenseMonthlyCategory).insertOnConflictUpdate(
          db.ExpenseMonthlyCategoryCompanion.insert(
            month: month,
            category: category,
            total: Value(newTotal),
            count: Value(newCount),
          ),
        );
  }

  /// 'YYYY-MM' prefix of a naive-local ISO date string, or null if malformed.
  static String? _month(String date) {
    final d = date.trim();
    if (d.length < 7) return null;
    final m = d.substring(0, 7);
    // Cheap shape check: 'YYYY-MM'.
    if (m.length != 7 || m[4] != '-') return null;
    return m;
  }
}
