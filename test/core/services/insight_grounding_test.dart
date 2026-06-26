// Tests the anti-hallucination guarantee: token binding substitutes verified
// values, and ANY ungrounded number or unknown token in the LLM prose causes a
// fall back to the deterministic, always-correct template.

import 'package:ai_nexus/core/services/insight_grounding.dart';
import 'package:ai_nexus/domain/entities/expense_insight.dart';
import 'package:flutter_test/flutter_test.dart';

InsightFacts _facts({bool hasData = true}) => InsightFacts(
      question: 'minimize my expenses',
      firstName: 'Monish',
      hasData: hasData,
      tone: InsightTone.warning,
      tokens: const {
        'name': InsightToken('Monish'),
        'total': InsightToken('₹83,286', number: 83286),
        'count': InsightToken('72', number: 72),
        'topCategory.name': InsightToken('Food'),
        'topCategory.total': InsightToken('₹14,700', number: 14700),
        'topCategory.pct': InsightToken('18%', number: 18),
        'momDelta': InsightToken('₹5,000', number: 5000),
        'momDirection': InsightToken('more'),
      },
    );

void main() {
  group('ground (valid composer output)', () {
    test('binds tokens to verified displays and keeps the LLM content', () {
      const spec = ResponseSpec(
        greeting: 'Hey {{name}},',
        headline: '{{topCategory.name}} leads at {{topCategory.total}}.',
        tip: "That's {{momDelta}} {{momDirection}} than last month — trim it.",
        tone: InsightTone.warning,
        chips: ['Break down {{topCategory.name}}', 'Compare to last month'],
      );
      final rec = InsightGrounding.ground(spec, _facts());

      expect(rec.isTemplate, isFalse);
      expect(rec.greeting, 'Hey Monish,');
      expect(rec.headline, 'Food leads at ₹14,700.');
      expect(rec.tip, contains('₹5,000 more than last month'));
      expect(rec.chips.first, 'Break down Food');
      expect(rec.tone, InsightTone.warning);
    });
  });

  group('grounding gate (fall back to template)', () {
    test('a bare number in the prose is rejected', () {
      const spec = ResponseSpec(
        greeting: 'Hey {{name}},',
        headline: 'You spent 50000 rupees on Food.', // fabricated digit
        tip: 'Cut back.',
        tone: InsightTone.info,
        chips: [],
      );
      final rec = InsightGrounding.ground(spec, _facts());
      expect(rec.isTemplate, isTrue,
          reason: 'ungrounded number forces the safe template');
    });

    test('an unknown token name is rejected', () {
      const spec = ResponseSpec(
        greeting: 'Hey {{name}},',
        headline: 'Your {{madeUpToken}} is high.',
        tip: 'Cut back.',
        tone: InsightTone.info,
        chips: [],
      );
      final rec = InsightGrounding.ground(spec, _facts());
      expect(rec.isTemplate, isTrue);
    });

    test('null spec (composer offline) -> template', () {
      final rec = InsightGrounding.ground(null, _facts());
      expect(rec.isTemplate, isTrue);
    });
  });

  group('template', () {
    test('is personalized, grounded, and mentions the top category', () {
      final rec = InsightGrounding.template(_facts());
      expect(rec.greeting, 'Hey Monish,');
      expect(rec.headline, contains('Food'));
      expect(rec.headline, contains('₹14,700'));
      // No fabricated values — only displays that exist in facts appear.
      expect(rec.tip, contains('Food'));
      expect(rec.chips, isNotEmpty);
    });

    test('handles the no-data case gracefully', () {
      final rec = InsightGrounding.template(_facts(hasData: false));
      expect(rec.isTemplate, isTrue);
      expect(rec.headline.toLowerCase(), contains('no expenses'));
    });
  });
}
