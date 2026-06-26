// Pure unit tests for the SalaryInsightEngine: it must turn a verified
// SalaryStats snapshot into bindable, grounded tokens (so the LLM can only
// phrase real numbers) AND produce a sensible deterministic fallback that is
// always personalized — and that always survives the grounding validator.

import 'package:ai_nexus/core/services/insight_grounding.dart';
import 'package:ai_nexus/core/services/salary_insight_engine.dart';
import 'package:ai_nexus/domain/entities/expense_insight.dart';
import 'package:ai_nexus/domain/entities/salary_entities.dart';
import 'package:flutter_test/flutter_test.dart';

SalaryStats _stats({
  double salary = 100000,
  double budget = 0,
  double spent = 0,
  double? previousSalary,
  double cumulativeSaved = 0,
  double avgSavingsRatePct = 0,
  double avgMonthlySpend = 0,
  int dayOfMonth = 15,
  int daysInMonth = 30,
  int months = 1,
  double highest = 100000,
  double average = 100000,
  double ccSpentThisMonth = 0,
  double ccDueThisMonth = 0,
}) {
  return SalaryStats(
    month: '2026-06',
    salary: salary,
    budget: budget,
    spent: spent,
    previousSalary: previousSalary,
    totalRecorded: average * months,
    monthsRecorded: months,
    highestSalary: highest,
    averageSalary: average,
    cumulativeSaved: cumulativeSaved,
    avgSavingsRatePct: avgSavingsRatePct,
    avgMonthlySpend: avgMonthlySpend,
    dayOfMonth: dayOfMonth,
    daysInMonth: daysInMonth,
    ccSpentThisMonth: ccSpentThisMonth,
    ccDueThisMonth: ccDueThisMonth,
  );
}

void main() {
  group('SalaryInsightEngine.compute facts', () {
    test('exposes core income/savings/budget tokens with numbers', () {
      final facts = SalaryInsightEngine.compute(
        firstName: 'Monish',
        stats: _stats(
          salary: 100000,
          budget: 50000,
          spent: 30000,
          previousSalary: 90000,
          cumulativeSaved: 135000,
          avgSavingsRatePct: 48.0,
          avgMonthlySpend: 52500,
        ),
      );

      expect(facts.hasData, isTrue);
      expect(facts.firstName, 'Monish');
      expect(facts.displayOf('name'), 'Monish');
      expect(facts.displayOf('month'), 'June 2026');
      expect(facts.numberOf('salary'), 100000);
      expect(facts.numberOf('spent'), 30000);
      expect(facts.numberOf('saved'), 70000);
      expect(facts.displayOf('savedPct'), '70%');
      expect(facts.numberOf('budget'), 50000);
      expect(facts.displayOf('budgetUsedPct'), '60%');
    });

    test('hike tokens computed vs previous month', () {
      final facts = SalaryInsightEngine.compute(
        firstName: 'Monish',
        stats: _stats(salary: 100000, previousSalary: 90000),
      );
      expect(facts.has('hikePct'), isTrue);
      expect(facts.displayOf('hikePct'), '+11.1%');
      expect(facts.displayOf('hikeDirection'), 'more');
    });

    test('projection + runway tokens', () {
      final facts = SalaryInsightEngine.compute(
        firstName: 'Monish',
        stats: _stats(
          salary: 100000,
          budget: 50000,
          spent: 15000,
          dayOfMonth: 15,
          daysInMonth: 30,
          cumulativeSaved: 300000,
          avgMonthlySpend: 50000,
        ),
      );
      expect(facts.numberOf('projectedSpend'), 30000);
      expect(facts.numberOf('projectedSaved'), 70000);
      expect(facts.numberOf('safePerDay'), closeTo(2333, 1)); // 35k/15d
      expect(facts.has('runway'), isTrue);
      expect(facts.displayOf('runway'), '6.0 months');
    });

    test('no salary → info tone, no-data flag, friendly placeholder name', () {
      final facts = SalaryInsightEngine.compute(
        firstName: '   ',
        stats: _stats(salary: 0, spent: 5000, months: 0),
      );
      expect(facts.hasData, isFalse);
      expect(facts.displayOf('name'), 'there');
      expect(facts.tone, InsightTone.info);
    });

    test('overspending pace yields a warning tone', () {
      final facts = SalaryInsightEngine.compute(
        firstName: 'Monish',
        stats: _stats(
          salary: 100000, budget: 40000, spent: 30000, dayOfMonth: 10),
      );
      // ₹30k in 10/30 days → ₹90k projected, over the ₹40k budget.
      expect(facts.tone, InsightTone.warning);
    });

    test('healthy savings yields a positive tone', () {
      final facts = SalaryInsightEngine.compute(
        firstName: 'Monish',
        stats: _stats(salary: 100000, spent: 20000, dayOfMonth: 28),
      );
      expect(facts.tone, InsightTone.positive);
    });
  });

  group('credit-card repayment facts + warning', () {
    test('exposes CC tokens only when there is card activity', () {
      final without = SalaryInsightEngine.compute(
        firstName: 'Monish',
        stats: _stats(salary: 100000),
      );
      expect(without.has('ccThisMonth'), isFalse);

      final withCc = SalaryInsightEngine.compute(
        firstName: 'Monish',
        stats: _stats(salary: 100000, ccSpentThisMonth: 25000),
      );
      expect(withCc.numberOf('ccThisMonth'), 25000);
      expect(withCc.numberOf('forecastNextTakeHome'), 75000);
      expect(withCc.displayOf('ccPctOfSalary'), '25%');
    });

    test('CC bill that leaves next month short yields a warning tone', () {
      final facts = SalaryInsightEngine.compute(
        firstName: 'Monish',
        stats: _stats(
          salary: 100000,
          spent: 10000,
          dayOfMonth: 5,
          ccSpentThisMonth: 50000,
          avgMonthlySpend: 70000,
        ),
      );
      expect(facts.tone, InsightTone.warning);
    });

    test('template leads with the credit-card repayment warning', () {
      final rec = SalaryInsightEngine.template(
        _stats(salary: 100000, spent: 10000, ccSpentThisMonth: 25000),
        'Monish',
      );
      expect(rec.tip.toLowerCase(), contains('credit'));
      expect(rec.tip, contains('₹75,000')); // forecast take-home
      expect(rec.chips, contains('What\'s my card bill next month?'));
    });

    test('template warns about a bill due now when nothing charged yet', () {
      final rec = SalaryInsightEngine.template(
        _stats(salary: 100000, spent: 10000, ccDueThisMonth: 30000),
        'Monish',
      );
      expect(rec.tip.toLowerCase(), contains('card bill'));
      expect(rec.tip, contains('₹70,000')); // effective take-home now
    });

    test('AI cannot invent a card bill when there is no CC activity', () {
      // No CC spend → no CC tokens exist. A composer that references them (or a
      // bare rupee figure) must be REJECTED, never shown as a fake warning.
      final stats = _stats(salary: 100000, spent: 20000);
      final facts =
          SalaryInsightEngine.compute(firstName: 'Monish', stats: stats);
      expect(facts.has('ccThisMonth'), isFalse);
      expect(facts.has('forecastNextTakeHome'), isFalse);
      const spec = ResponseSpec(
        greeting: 'Hey {{name}},',
        headline: 'Your card bill next month is {{ccThisMonth}}.',
        tip: 'You\'ll only have ₹55,000 left.',
        tone: InsightTone.warning,
        chips: [],
      );
      final grounded = InsightGrounding.ground(spec, facts);
      expect(grounded.isTemplate, isTrue,
          reason: 'a fabricated CC warning must drop to the template');
    });

    test('template CC warning is internally consistent (salary − bill)', () {
      // forecast = 100k - 30k = 70k; the tip must quote exactly that, never a
      // fabricated figure.
      final rec = SalaryInsightEngine.template(
        _stats(salary: 100000, spent: 5000, ccSpentThisMonth: 30000),
        'Monish',
      );
      expect(rec.tip, contains('₹30,000')); // the charge
      expect(rec.tip, contains('₹70,000')); // the grounded forecast
    });

    test('CC warning leads even while also overspending the budget', () {
      final rec = SalaryInsightEngine.template(
        _stats(
          salary: 100000,
          budget: 30000,
          spent: 80000, // pace → month-end overspend
          dayOfMonth: 20,
          ccSpentThisMonth: 40000,
        ),
        'Monish',
      );
      final tip = rec.tip.toLowerCase();
      // Both signals are present, and the repayment warning comes first.
      expect(tip, contains('credit'));
      expect(tip, contains('overspend'));
      expect(tip.indexOf('credit'), lessThan(tip.indexOf('overspend')));
      expect(rec.tone, InsightTone.warning);
    });

    test('CC tokens survive the grounding validator end-to-end', () {
      final stats = _stats(salary: 100000, ccSpentThisMonth: 25000);
      final facts =
          SalaryInsightEngine.compute(firstName: 'Monish', stats: stats);
      const spec = ResponseSpec(
        greeting: 'Hey {{name}},',
        headline:
            'You charged {{ccThisMonth}} to credit this month, {{ccPctOfSalary}} '
            'of your pay.',
        tip: 'Next month you\'ll have {{forecastNextTakeHome}} after repaying.',
        tone: InsightTone.warning,
        chips: ['What\'s my card bill next month?'],
      );
      final grounded = InsightGrounding.ground(spec, facts);
      expect(grounded.isTemplate, isFalse);
      expect(grounded.headline, contains('₹25,000'));
      expect(grounded.headline, contains('25%'));
      expect(grounded.tip, contains('₹75,000'));
    });
  });

  group('SalaryInsightEngine.template (deterministic fallback)', () {
    test('always personalized and grounded for a healthy month', () {
      final stats = _stats(
        salary: 100000,
        budget: 50000,
        spent: 20000,
        dayOfMonth: 10,
        cumulativeSaved: 200000,
        avgMonthlySpend: 40000,
      );
      final rec = SalaryInsightEngine.template(stats, 'Monish');
      expect(rec.greeting, 'Hey Monish,');
      expect(rec.headline, contains('saved'));
      expect(rec.tip, isNotEmpty);
      expect(rec.isTemplate, isTrue);
      expect(rec.chips, isNotEmpty);
    });

    test('flags overspending in the headline', () {
      final stats = _stats(salary: 50000, spent: 60000, dayOfMonth: 20);
      final rec = SalaryInsightEngine.template(stats, 'Monish');
      expect(rec.headline.toLowerCase(), contains('more than'));
      expect(rec.tone, InsightTone.warning);
    });

    test('no-salary state nudges the user to enter salary', () {
      final rec =
          SalaryInsightEngine.template(_stats(salary: 0, months: 0), 'Monish');
      expect(rec.headline.toLowerCase(), contains('salary'));
      expect(rec.chips, contains('Enter salary'));
    });

    test('blank name still greets gracefully', () {
      final rec = SalaryInsightEngine.template(_stats(), '');
      expect(rec.greeting, 'Hey,');
    });
  });

  group('grounding contract', () {
    // A composer response that references ONLY known tokens and no bare numbers
    // must pass grounding and bind to the verified display values.
    test('valid composed spec grounds with real figures', () {
      final stats = _stats(
        salary: 100000,
        budget: 50000,
        spent: 30000,
        previousSalary: 90000,
      );
      final facts =
          SalaryInsightEngine.compute(firstName: 'Monish', stats: stats);
      const spec = ResponseSpec(
        greeting: 'Hey {{name}},',
        headline: 'You saved {{saved}} ({{savedPct}}) of {{salary}}.',
        tip: 'You used {{budgetUsedPct}} of your budget — nice pace.',
        tone: InsightTone.positive,
        chips: ['How can I save more?'],
      );
      final grounded = InsightGrounding.ground(spec, facts);
      expect(grounded.isTemplate, isFalse);
      expect(grounded.greeting, 'Hey Monish,');
      expect(grounded.headline, contains('₹70,000'));
      expect(grounded.headline, contains('70%'));
      expect(grounded.headline, contains('₹1,00,000'));
      expect(grounded.tip, contains('60%'));
    });

    test('a fabricated bare number is rejected (falls back to template)', () {
      final stats = _stats(salary: 100000, spent: 30000);
      final facts =
          SalaryInsightEngine.compute(firstName: 'Monish', stats: stats);
      const spec = ResponseSpec(
        greeting: 'Hey {{name}},',
        // 42000 is NOT a bound token → hallucination → must be rejected.
        headline: 'You secretly saved ₹42000 extra.',
        tip: 'Keep it up.',
        tone: InsightTone.positive,
        chips: [],
      );
      final grounded = InsightGrounding.ground(spec, facts);
      expect(grounded.isTemplate, isTrue,
          reason: 'ungrounded prose must drop to the deterministic template');
    });
  });
}
