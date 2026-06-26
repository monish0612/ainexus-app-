import 'package:intl/intl.dart';

import '../../data/repositories/expense_repository.dart' show ExpenseBucket;
import '../../data/services/expense_memory_service.dart';
import '../../domain/entities/expense_insight.dart';
import '../utils/currency_formatter.dart';

/// Pure, deterministic computation of [InsightFacts] from the SQL result slice
/// (already loaded by the screen) plus the whole-history [MemoryFacts].
///
/// No LLM, no I/O — every value is computed here in code, which is exactly why
/// the recommendation can be both dynamic AND impossible to hallucinate: the
/// composer only ever phrases these pre-computed tokens.
class ExpenseInsightEngine {
  const ExpenseInsightEngine._();

  /// [sliceCategories] must be sorted by total descending (as
  /// `ExpenseRepository.categoryBreakdown` returns them).
  static InsightFacts compute({
    required String question,
    required String firstName,
    required double sliceTotal,
    required int sliceCount,
    required List<CategoryTotal> sliceCategories,
    required List<ExpenseBucket> timeBuckets,
    required MemoryFacts memory,
  }) {
    final t = <String, InsightToken>{};
    final fn = firstName.trim().isEmpty ? 'there' : firstName.trim();
    t['name'] = InsightToken(fn);

    final hasData = sliceCount > 0;

    t['total'] = InsightToken(formatCurrency(sliceTotal),
        number: _r(sliceTotal));
    t['count'] = InsightToken('$sliceCount', number: sliceCount);
    if (sliceCount > 0) {
      final avg = sliceTotal / sliceCount;
      t['avgPerTxn'] = InsightToken(formatCurrency(avg), number: _r(avg));
    }

    if (sliceCategories.isNotEmpty) {
      final top = sliceCategories.first;
      t['topCategory.name'] = InsightToken(top.category);
      t['topCategory.total'] =
          InsightToken(formatCurrency(top.total), number: _r(top.total));
      t['topCategory.count'] = InsightToken('${top.count}', number: top.count);
      if (sliceTotal > 0) {
        final pct = top.total / sliceTotal * 100;
        t['topCategory.pct'] =
            InsightToken('${pct.round()}%', number: pct.round());
      }
      if (sliceCategories.length > 1) {
        final second = sliceCategories[1];
        t['secondCategory.name'] = InsightToken(second.category);
        t['secondCategory.total'] = InsightToken(formatCurrency(second.total),
            number: _r(second.total));
      }
    }

    // Whole-history context from the memory layer.
    t['thisMonth'] = InsightToken(formatCurrency(memory.currentMonthTotal),
        number: _r(memory.currentMonthTotal));
    t['lastMonth'] = InsightToken(formatCurrency(memory.previousMonthTotal),
        number: _r(memory.previousMonthTotal));
    final mom = memory.momDelta;
    t['momDelta'] =
        InsightToken(formatCurrency(mom.abs()), number: _r(mom.abs()));
    t['momDirection'] =
        InsightToken(mom > 0 ? 'more' : (mom < 0 ? 'less' : 'about the same'));
    if (memory.previousMonthTotal > 0) {
      final pct = (mom / memory.previousMonthTotal * 100).abs();
      t['momPct'] = InsightToken('${pct.round()}%', number: pct.round());
    }
    t['avgMonthly'] = InsightToken(formatCurrency(memory.avgMonthlyTotal),
        number: _r(memory.avgMonthlyTotal));
    t['lifetimeTotal'] = InsightToken(formatCurrency(memory.lifetimeTotal),
        number: _r(memory.lifetimeTotal));
    t['monthsTracked'] =
        InsightToken('${memory.monthsTracked}', number: memory.monthsTracked);

    if (memory.topCategoriesCurrentMonth.isNotEmpty) {
      final mc = memory.topCategoriesCurrentMonth.first;
      t['monthTopCategory.name'] = InsightToken(mc.category);
      t['monthTopCategory.total'] =
          InsightToken(formatCurrency(mc.total), number: _r(mc.total));
    }

    if (timeBuckets.isNotEmpty) {
      final peak =
          timeBuckets.reduce((a, b) => a.total >= b.total ? a : b);
      t['peakBucket.label'] = InsightToken(_humanBucket(peak.bucket));
      t['peakBucket.total'] =
          InsightToken(formatCurrency(peak.total), number: _r(peak.total));
    }

    return InsightFacts(
      question: question,
      firstName: fn,
      tokens: t,
      tone: _tone(
        hasData: hasData,
        mom: mom,
        prevMonth: memory.previousMonthTotal,
        sliceTotal: sliceTotal,
        sliceCategories: sliceCategories,
      ),
      hasData: hasData,
    );
  }

  static int _r(num v) => v.round();

  static InsightTone _tone({
    required bool hasData,
    required double mom,
    required double prevMonth,
    required double sliceTotal,
    required List<CategoryTotal> sliceCategories,
  }) {
    if (!hasData) return InsightTone.info;
    if (prevMonth > 0 && mom > 0) return InsightTone.warning;
    if (prevMonth > 0 && mom < 0) return InsightTone.positive;
    final topPct = (sliceCategories.isNotEmpty && sliceTotal > 0)
        ? sliceCategories.first.total / sliceTotal * 100
        : 0;
    return topPct >= 50 ? InsightTone.warning : InsightTone.info;
  }

  /// Human label for a 'YYYY-MM' or 'YYYY-MM-DD' bucket; falls back to the raw
  /// string if it can't be parsed.
  static String _humanBucket(String bucket) {
    final b = bucket.trim();
    try {
      if (b.length == 7) {
        final d = DateTime.parse('$b-01');
        return DateFormat('MMM yyyy', 'en_IN').format(d);
      }
      if (b.length >= 10) {
        final d = DateTime.parse(b.substring(0, 10));
        return DateFormat('d MMM', 'en_IN').format(d);
      }
    } catch (_) {/* fall through */}
    return b;
  }
}
