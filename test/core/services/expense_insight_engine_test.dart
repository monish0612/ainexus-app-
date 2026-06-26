// Pure unit tests for the deterministic Insight Engine: it must compute every
// fact (top category, percentages, month-over-month, averages) correctly and
// expose them as bindable tokens with both a display string and a raw number.

import 'package:ai_nexus/core/services/expense_insight_engine.dart';
import 'package:ai_nexus/data/repositories/expense_repository.dart';
import 'package:ai_nexus/data/services/expense_memory_service.dart';
import 'package:ai_nexus/domain/entities/expense_insight.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 6, 26, 12);

  MemoryFacts memoryWith() => MemoryFacts.fromBuckets(
        const [
          (month: '2026-05', category: 'Food', total: 400, count: 4),
          (month: '2026-06', category: 'Food', total: 600, count: 6),
          (month: '2026-06', category: 'Travel', total: 300, count: 2),
        ],
        now: now,
      );

  test('computes slice facts: total, count, avg, top category + percentage', () {
    final facts = ExpenseInsightEngine.compute(
      question: 'recommendations to minimize my expenses',
      firstName: 'Monish',
      sliceTotal: 900,
      sliceCount: 8,
      sliceCategories: const [
        (category: 'Food', total: 600, count: 6),
        (category: 'Travel', total: 300, count: 2),
      ],
      timeBuckets: const [],
      memory: memoryWith(),
    );

    expect(facts.hasData, isTrue);
    expect(facts.firstName, 'Monish');
    expect(facts.displayOf('name'), 'Monish');
    expect(facts.numberOf('total'), 900);
    expect(facts.numberOf('count'), 8);
    expect(facts.displayOf('topCategory.name'), 'Food');
    expect(facts.numberOf('topCategory.total'), 600);
    // 600 / 900 = 66.7% -> rounds to 67.
    expect(facts.numberOf('topCategory.pct'), 67);
    expect(facts.displayOf('topCategory.pct'), '67%');
    expect(facts.displayOf('secondCategory.name'), 'Travel');
    expect(facts.numberOf('avgPerTxn'), closeTo(113, 1)); // 900/8 = 112.5
  });

  test('computes month-over-month direction from the memory layer', () {
    final facts = ExpenseInsightEngine.compute(
      question: 'q',
      firstName: 'Monish',
      sliceTotal: 900,
      sliceCount: 8,
      sliceCategories: const [(category: 'Food', total: 600, count: 6)],
      timeBuckets: const [],
      memory: memoryWith(),
    );
    // current 900 vs previous 400 -> up by 500.
    expect(facts.numberOf('thisMonth'), 900);
    expect(facts.numberOf('lastMonth'), 400);
    expect(facts.numberOf('momDelta'), 500);
    expect(facts.displayOf('momDirection'), 'more');
    // 500 / 400 = 125%.
    expect(facts.numberOf('momPct'), 125);
    // spending rose -> warning tone.
    expect(facts.tone, InsightTone.warning);
  });

  test('falling month -> positive tone', () {
    final memory = MemoryFacts.fromBuckets(
      const [
        (month: '2026-05', category: 'Food', total: 1000, count: 4),
        (month: '2026-06', category: 'Food', total: 400, count: 2),
      ],
      now: now,
    );
    final facts = ExpenseInsightEngine.compute(
      question: 'q',
      firstName: 'Monish',
      sliceTotal: 400,
      sliceCount: 2,
      sliceCategories: const [(category: 'Food', total: 400, count: 2)],
      timeBuckets: const [],
      memory: memory,
    );
    expect(facts.displayOf('momDirection'), 'less');
    expect(facts.tone, InsightTone.positive);
  });

  test('empty slice -> hasData false, info tone, no top category', () {
    final facts = ExpenseInsightEngine.compute(
      question: 'q',
      firstName: 'Monish',
      sliceTotal: 0,
      sliceCount: 0,
      sliceCategories: const [],
      timeBuckets: const [],
      memory: MemoryFacts.empty(now),
    );
    expect(facts.hasData, isFalse);
    expect(facts.has('topCategory.name'), isFalse);
    expect(facts.tone, InsightTone.info);
  });

  test('peak bucket is derived from the time series when present', () {
    final facts = ExpenseInsightEngine.compute(
      question: 'last 3 days',
      firstName: 'Monish',
      sliceTotal: 2050,
      sliceCount: 3,
      sliceCategories: const [(category: 'Food', total: 2050, count: 3)],
      timeBuckets: const <ExpenseBucket>[
        (bucket: '2026-06-23', total: 540, count: 1),
        (bucket: '2026-06-24', total: 1200, count: 1),
        (bucket: '2026-06-25', total: 310, count: 1),
      ],
      memory: memoryWith(),
    );
    expect(facts.numberOf('peakBucket.total'), 1200);
    expect(facts.has('peakBucket.label'), isTrue);
  });

  test('blank name falls back to a friendly placeholder', () {
    final facts = ExpenseInsightEngine.compute(
      question: 'q',
      firstName: '   ',
      sliceTotal: 100,
      sliceCount: 1,
      sliceCategories: const [(category: 'Food', total: 100, count: 1)],
      timeBuckets: const [],
      memory: MemoryFacts.empty(now),
    );
    expect(facts.displayOf('name'), 'there');
  });
}
