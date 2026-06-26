import 'package:flutter/foundation.dart';

/// Emotional colour for a recommendation, used to tint the card.
enum InsightTone { info, warning, positive }

/// A single bound value the AI narrative may reference via a `{{token}}`.
///
/// [display] is the human-facing, pre-formatted string (e.g. `"₹12,480"`,
/// `"62%"`, `"Food"`). [number] is the raw numeric value (when the token is
/// numeric) used by the grounding validator. Text tokens (a category name)
/// have a null [number].
@immutable
class InsightToken {
  const InsightToken(this.display, {this.number});

  final String display;
  final num? number;
}

/// Deterministic, fully-computed facts about a result slice + the user's
/// overall spending history. EVERY number a recommendation can mention exists
/// here as a real value — the LLM never originates a figure, it only phrases
/// and arranges these tokens. This is the anti-hallucination contract.
@immutable
class InsightFacts {
  const InsightFacts({
    required this.question,
    required this.firstName,
    required this.tokens,
    required this.tone,
    required this.hasData,
  });

  final String question;
  final String firstName;

  /// token name -> bound value (e.g. `topCategory.name`, `total`, `momPct`).
  final Map<String, InsightToken> tokens;

  /// Suggested tone (the composer may override within reason).
  final InsightTone tone;

  /// False when the slice has no matching expenses.
  final bool hasData;

  num? numberOf(String token) => tokens[token]?.number;
  String displayOf(String token) => tokens[token]?.display ?? '';
  bool has(String token) => tokens.containsKey(token);

  /// All numeric values the validator will accept in free prose.
  Iterable<num> get allowedNumbers =>
      tokens.values.where((t) => t.number != null).map((t) => t.number!);

  /// Compact `{ token: {display, value} }` payload sent to the composer so it
  /// can pick which tokens to weave in. No raw expense rows are ever included.
  Map<String, dynamic> toPromptTokens() => {
        for (final e in tokens.entries)
          e.key: {
            'display': e.value.display,
            if (e.value.number != null) 'value': e.value.number,
          },
      };
}

/// A dynamic, LLM-authored response layout. The narrative fields may contain
/// `{{token}}` placeholders that are bound from [InsightFacts] before display;
/// they must never contain bare numbers (enforced by the grounding validator).
@immutable
class ResponseSpec {
  const ResponseSpec({
    required this.greeting,
    required this.headline,
    required this.tip,
    required this.tone,
    required this.chips,
  });

  /// e.g. "Hi {{name}}," — short personalized opener.
  final String greeting;

  /// One-line headline insight (bolded in the UI).
  final String headline;

  /// The actionable saving recommendation (1-2 sentences).
  final String tip;

  final InsightTone tone;

  /// Dynamic follow-up suggestion chips (tappable -> new question).
  final List<String> chips;

  bool get isEmpty =>
      greeting.isEmpty && headline.isEmpty && tip.isEmpty && chips.isEmpty;

  static InsightTone parseTone(Object? raw) {
    switch (raw?.toString()) {
      case 'warning':
        return InsightTone.warning;
      case 'positive':
        return InsightTone.positive;
      default:
        return InsightTone.info;
    }
  }

  factory ResponseSpec.fromJson(Map<String, dynamic> m) {
    final chips = <String>[];
    final raw = m['chips'];
    if (raw is List) {
      for (final c in raw) {
        if (c is! String) continue;
        final t = c.trim();
        if (t.isEmpty || t.length > 48) continue;
        chips.add(t);
        if (chips.length >= 4) break;
      }
    }
    String str(Object? v) => (v is String) ? v.trim() : '';
    return ResponseSpec(
      greeting: str(m['greeting']),
      headline: str(m['headline']),
      tip: str(m['tip']),
      tone: parseTone(m['tone']),
      chips: chips,
    );
  }
}

/// The final, display-ready recommendation after token-binding + grounding.
/// All `{{tokens}}` have been replaced with verified values, so every figure
/// shown is real. [isTemplate] is true when this came from the deterministic
/// fallback (composer offline or its prose failed grounding) instead of the
/// LLM — useful for analytics, never shown to the user.
@immutable
class GroundedRecommendation {
  const GroundedRecommendation({
    required this.greeting,
    required this.headline,
    required this.tip,
    required this.tone,
    required this.chips,
    required this.isTemplate,
  });

  final String greeting;
  final String headline;
  final String tip;
  final InsightTone tone;
  final List<String> chips;
  final bool isTemplate;

  bool get hasContent =>
      greeting.isNotEmpty || headline.isNotEmpty || tip.isNotEmpty;
}
