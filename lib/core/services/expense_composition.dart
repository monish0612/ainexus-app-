import '../../domain/entities/expense_entities.dart';
import 'expense_pace_metrics.dart';

/// One row for cash / debit / credit / moved composition. Dates are already
/// parsed so the engine stays free of I/O and UI types.
class CompositionTxn {
  const CompositionTxn({
    required this.amount,
    required this.category,
    required this.cardType,
    required this.date,
  });

  final double amount;
  final String category;
  final String cardType;
  final DateTime date;

  bool get isMoved => isNonSpendCategory(category);
}

enum CardSpendBucket { cash, debit, credit }

class PieSliceFact {
  const PieSliceFact({
    required this.category,
    required this.total,
    required this.pct,
    this.isOther = false,
  });

  final String category;
  final double total;
  final double pct;
  final bool isOther;
}

/// Money Manager Total-page composition mapped onto Nexus `cardType` +
/// Investment/Loan. Pure Dart — no I/O.
class ExpenseComposition {
  const ExpenseComposition({
    required this.cash,
    required this.debit,
    required this.credit,
    required this.moved,
    required this.spendTotal,
    required this.previousMonthSpend,
    required this.completedMonthAverage,
  });

  final double cash;
  final double debit;
  final double credit;

  /// Investment + Loan in the same calendar month. Not spend.
  final double moved;

  /// Cash + debit + credit for the month (Investment/Loan excluded).
  final double spendTotal;

  final double previousMonthSpend;
  final double? completedMonthAverage;

  bool get hasAny => spendTotal > 0 || moved > 0;

  /// 100 = same spend as last calendar month. Null when last month is empty.
  double? get momIndex {
    if (previousMonthSpend < ExpensePaceMetrics.rupeeFloor) return null;
    return (spendTotal / previousMonthSpend) * 100;
  }

  /// Overflow label when more than [maxNamed] categories are in the period.
  /// Distinct from the real expense category `Others` so a recategorized
  /// Medical/Health spend is never silently renamed.
  static const String otherLabel = 'Other';
  static const int defaultMaxNamed = 8;

  static CardSpendBucket bucketFor(String cardType) {
    final t = cardType.trim().toLowerCase();
    if (t == 'cash' || t == 'csh') return CardSpendBucket.cash;
    if (t == 'cc' || t.contains('credit')) return CardSpendBucket.credit;
    return CardSpendBucket.debit;
  }

  static ExpenseComposition ofMonth({
    required Iterable<CompositionTxn> txns,
    required DateTime now,
  }) {
    final monthStart = DateTime(now.year, now.month, 1);
    final nextMonth = DateTime(now.year, now.month + 1, 1);
    final prevStart = DateTime(now.year, now.month - 1, 1);

    var cash = 0.0;
    var debit = 0.0;
    var credit = 0.0;
    var moved = 0.0;
    var previous = 0.0;
    final monthTotals = <String, double>{};

    for (final e in txns) {
      final d = DateTime(e.date.year, e.date.month, e.date.day);
      final key = ExpensePaceMetrics.monthKey(d);
      if (!e.isMoved) {
        monthTotals[key] = (monthTotals[key] ?? 0) + e.amount;
      }

      final inMonth = !d.isBefore(monthStart) && d.isBefore(nextMonth);
      final inPrev = !d.isBefore(prevStart) && d.isBefore(monthStart);
      if (inMonth) {
        if (e.isMoved) {
          moved += e.amount;
        } else {
          switch (bucketFor(e.cardType)) {
            case CardSpendBucket.cash:
              cash += e.amount;
            case CardSpendBucket.debit:
              debit += e.amount;
            case CardSpendBucket.credit:
              credit += e.amount;
          }
        }
      } else if (inPrev && !e.isMoved) {
        previous += e.amount;
      }
    }

    return ExpenseComposition(
      cash: cash,
      debit: debit,
      credit: credit,
      moved: moved,
      spendTotal: cash + debit + credit,
      previousMonthSpend: previous,
      completedMonthAverage: ExpensePaceMetrics.completedPeriodAverage(
        monthTotals: monthTotals,
        now: now,
      ),
    );
  }

  /// Ranked pie slices for the tracker ring.
  ///
  /// Every real category keeps its name (so editing Others → Medical shows
  /// Medical on the ring). Only a 9th+ leftover collapses into [otherLabel].
  static List<PieSliceFact> pieSlices(
    Map<String, double> byCategory, {
    int maxNamed = defaultMaxNamed,
  }) {
    if (byCategory.isEmpty) return const [];
    final total = byCategory.values.fold<double>(0, (s, v) => s + v);
    if (total <= 0) return const [];

    final entries = byCategory.entries.toList()
      ..sort((a, b) {
        final byAmt = b.value.compareTo(a.value);
        if (byAmt != 0) return byAmt;
        return a.key.compareTo(b.key);
      });

    final named = <PieSliceFact>[];
    var other = 0.0;
    for (final e in entries) {
      final pct = (e.value / total) * 100;
      if (named.length < maxNamed) {
        named.add(
          PieSliceFact(
            category: e.key,
            total: e.value,
            pct: pct,
          ),
        );
      } else {
        other += e.value;
      }
    }

    if (other > 0) {
      named.add(
        PieSliceFact(
          category: otherLabel,
          total: other,
          pct: (other / total) * 100,
          isOther: true,
        ),
      );
    }
    return named;
  }
}
