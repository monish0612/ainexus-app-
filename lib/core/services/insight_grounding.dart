import '../../domain/entities/expense_insight.dart';

/// Token-binding + grounding safety net for AI recommendations.
///
/// The composer (LLM) is only allowed to reference figures via `{{token}}`
/// placeholders. This class:
///  1. validates that the model's prose contains ONLY known tokens and NO bare
///     digits (a stray number means it tried to fabricate a value), and
///  2. binds the tokens to their verified [InsightFacts] display values.
///
/// If validation fails (or the composer was offline), it returns a fully
/// deterministic [GroundedRecommendation] built in code from the same facts —
/// so the user always gets a correct, personalized message and a hallucinated
/// number can never reach the screen.
class InsightGrounding {
  const InsightGrounding._();

  static final RegExp _tokenRe = RegExp(r'\{\{\s*([\w.]+)\s*\}\}');
  static final RegExp _digitRe = RegExp(r'\d');

  /// Produce the display-ready recommendation. [spec] may be null (composer
  /// offline) -> deterministic template.
  static GroundedRecommendation ground(ResponseSpec? spec, InsightFacts facts) {
    if (spec == null || spec.isEmpty) return template(facts);

    // Grounding gate: every narrative field must use only known tokens and
    // contain no bare numbers. Chips are plain suggestions, not factual claims,
    // so they are bound but not number-gated.
    final gated = [spec.greeting, spec.headline, spec.tip];
    for (final field in gated) {
      if (!_isGrounded(field, facts)) return template(facts);
    }

    final headline = _bind(spec.headline, facts);
    final tip = _bind(spec.tip, facts);
    // A composed response with no usable body is worse than the template.
    if (headline.trim().isEmpty && tip.trim().isEmpty) return template(facts);

    return GroundedRecommendation(
      greeting: _bind(spec.greeting, facts),
      headline: headline,
      tip: tip,
      tone: spec.tone,
      chips: spec.chips
          .map((c) => _bind(c, facts).trim())
          .where((c) => c.isNotEmpty)
          .toList(),
      isTemplate: false,
    );
  }

  /// True if [s] references only tokens that exist in [facts] and contains no
  /// digit outside a `{{token}}` (which would be a fabricated number).
  static bool _isGrounded(String s, InsightFacts facts) {
    if (s.isEmpty) return true;
    for (final m in _tokenRe.allMatches(s)) {
      final name = m.group(1);
      if (name == null || !facts.has(name)) return false;
    }
    final stripped = s.replaceAll(_tokenRe, '');
    return !_digitRe.hasMatch(stripped);
  }

  /// Replace known `{{token}}` with its verified display; drop unknown tokens.
  static String _bind(String s, InsightFacts facts) {
    if (s.isEmpty) return s;
    return s.replaceAllMapped(_tokenRe, (m) {
      final name = m.group(1);
      if (name == null) return '';
      return facts.tokens[name]?.display ?? '';
    });
  }

  /// Deterministic, always-grounded fallback built directly from facts.
  static GroundedRecommendation template(InsightFacts f) {
    final name = f.displayOf('name');
    final greeting = name.isEmpty ? 'Hey,' : 'Hey $name,';

    if (!f.hasData) {
      return GroundedRecommendation(
        greeting: greeting,
        headline: 'No expenses match this view yet.',
        tip: 'Once you log some spending here, I can show you where to save.',
        tone: InsightTone.info,
        chips: const ['Show all my expenses', 'This month'],
        isTemplate: true,
      );
    }

    final total = f.displayOf('total');
    final count = f.displayOf('count');

    String headline;
    if (f.has('topCategory.name')) {
      final cat = f.displayOf('topCategory.name');
      final catTotal = f.displayOf('topCategory.total');
      headline = f.has('topCategory.pct')
          ? '$cat is your biggest spend at $catTotal — ${f.displayOf('topCategory.pct')} of $total.'
          : '$cat is your biggest spend at $catTotal.';
    } else {
      headline = "You've spent $total across $count expenses here.";
    }

    final tip = StringBuffer();
    if (f.has('topCategory.name')) {
      tip.write('Trimming ${f.displayOf('topCategory.name')} would save you the most.');
    } else {
      tip.write('Review the largest items below to find quick savings.');
    }
    final momDelta = f.numberOf('momDelta') ?? 0;
    if (momDelta != 0 && f.has('momDelta') && f.has('momDirection')) {
      tip.write(' That\'s ${f.displayOf('momDelta')} ${f.displayOf('momDirection')} than last month.');
    }

    final chips = <String>[];
    if (f.has('topCategory.name')) {
      chips.add('Break down ${f.displayOf('topCategory.name')}');
    }
    chips.add('Compare to last month');
    chips.add('Show daily trend');

    return GroundedRecommendation(
      greeting: greeting,
      headline: headline,
      tip: tip.toString(),
      tone: f.tone,
      chips: chips.take(3).toList(),
      isTemplate: true,
    );
  }
}
