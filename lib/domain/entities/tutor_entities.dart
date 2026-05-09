import 'package:flutter/foundation.dart';

import '../../core/services/telegram_logger.dart';

@immutable
class RephraseResult {
  const RephraseResult({
    required this.platform,
    required this.rephrasedText,
  });

  final String platform;
  final String rephrasedText;

  factory RephraseResult.fromJson(Map<String, dynamic> json) {
    return RephraseResult(
      platform: _str(json, const ['platform']),
      rephrasedText: _str(
        json,
        const ['rephrasedText', 'rephrased_text', 'text'],
      ),
    );
  }
}

@immutable
class CoachVariation {
  const CoachVariation({required this.label, required this.text});

  final String label;
  final String text;

  factory CoachVariation.fromJson(Map<String, dynamic> json) {
    return CoachVariation(
      label: _str(json, const [
        'label', 'tone', 'type', 'style', 'name',
      ]),
      text: _str(json, const [
        'text', 'content', 'message', 'response', 'output',
        'value', 'sentence', 'version', 'rephrased', 'example',
      ]),
    );
  }
}

@immutable
class CoachResult {
  const CoachResult({
    required this.correctedText,
    required this.explanation,
    required this.variations,
  });

  final String correctedText;
  final String explanation;
  final List<CoachVariation> variations;

  factory CoachResult.fromJson(Map<String, dynamic> json) {
    TLog.d('CoachResult', 'Keys: ${json.keys.toList()}');

    // Try many possible key names for the variations array
    final dynamic rawVariations = json['variations']
        ?? json['alternatives']
        ?? json['options']
        ?? json['suggestions']
        ?? json['rewrites']
        ?? json['toneVariations']
        ?? json['tone_variations'];

    List<CoachVariation> list;

    if (rawVariations is List) {
      TLog.d('CoachResult', 'Variations is List, length=${rawVariations.length}');
      if (rawVariations.isNotEmpty) {
        TLog.d('CoachResult', 'First item type: ${rawVariations.first.runtimeType}');
      }

      list = rawVariations
          .whereType<Map>()
          .map<CoachVariation>((item) {
            final map = item.map(
              (k, v) => MapEntry(k.toString(), v),
            );
            return CoachVariation.fromJson(map);
          })
          .where((v) => v.label.isNotEmpty && v.text.isNotEmpty)
          .toList();
    } else if (rawVariations is Map) {
      // LLM returned { "Casual": "text", "Professional": "text" }
      TLog.d('CoachResult', 'Variations is Map, keys=${rawVariations.keys.toList()}');
      list = rawVariations.entries.map<CoachVariation>((entry) {
        final key = entry.key.toString();
        final val = entry.value;
        if (val is String) {
          return CoachVariation(label: key, text: val.trim());
        } else if (val is Map) {
          final map = val.map((k, v) => MapEntry(k.toString(), v));
          final text = _str(map, const [
            'text', 'content', 'message', 'response', 'output',
          ]);
          return CoachVariation(
            label: _str(map, const ['label', 'tone']) .isNotEmpty
                ? _str(map, const ['label', 'tone'])
                : key,
            text: text,
          );
        }
        return const CoachVariation(label: '', text: '');
      }).where((v) => v.label.isNotEmpty && v.text.isNotEmpty).toList();
    } else {
      TLog.w('CoachResult', 'Variations missing or unexpected type: '
          '${rawVariations?.runtimeType}');
      list = const <CoachVariation>[];
    }

    TLog.d('CoachResult', 'Parsed ${list.length} variations');

    return CoachResult(
      correctedText: _str(
        json,
        const ['correctedText', 'corrected_text', 'corrected'],
      ),
      explanation: _str(
        json,
        const ['explanation', 'reasoning', 'reason'],
      ),
      variations: list,
    );
  }
}

@immutable
class DictionaryResult {
  const DictionaryResult({
    required this.word,
    required this.pronunciation,
    required this.partOfSpeech,
    required this.definition,
    required this.examples,
    required this.usageGuide,
  });

  final String word;
  final String pronunciation;
  final String partOfSpeech;
  final String definition;
  final List<String> examples;
  final String usageGuide;

  factory DictionaryResult.fromJson(Map<String, dynamic> json) {
    TLog.d('DictResult', 'Keys: ${json.keys.toList()}');

    final rawExamples = json['examples'];
    final examples =
        rawExamples is List
            ? rawExamples
                .map((e) => e?.toString().trim() ?? '')
                .where((s) => s.isNotEmpty)
                .toList()
            : const <String>[];

    final usageGuide = _str(json, const [
      'usageGuide', 'usage_guide', 'usage',
      'whenToUse', 'when_to_use',
      'usageNotes', 'usage_notes',
      'guide', 'context', 'notes',
      'situationsToUse', 'situations_to_use',
      'howToUse', 'how_to_use',
    ]);

    TLog.d('DictResult', 'usageGuide length: ${usageGuide.length}');

    return DictionaryResult(
      word: _str(json, const ['word']),
      pronunciation: _str(json, const ['pronunciation', 'phonetic']),
      partOfSpeech: _str(json, const [
        'partOfSpeech', 'part_of_speech', 'pos', 'type',
      ]),
      definition: _str(json, const [
        'definition', 'meaning', 'explanation',
      ]),
      examples: examples,
      usageGuide: usageGuide,
    );
  }

  Map<String, dynamic> toJson() => {
    'word': word,
    'pronunciation': pronunciation,
    'partOfSpeech': partOfSpeech,
    'definition': definition,
    'examples': examples,
    'usageGuide': usageGuide,
  };
}

// ── Summarizer ──────────────────────────────────────────────────────────────

@immutable
class SummarizerResult {
  const SummarizerResult({
    required this.title,
    required this.summary,
    required this.keyPoints,
    required this.category,
    required this.readTime,
    required this.source,
    required this.extractionMethod,
    required this.url,
    required this.model,
    this.providerUsed = '',
    this.fallback = false,
  });

  final String title;
  final String summary;
  final List<String> keyPoints;
  final String category;
  final int readTime;
  final String source;
  final String extractionMethod;
  final String url;
  final String model;
  final String providerUsed;
  final bool fallback;

  bool get isXGrok =>
      providerUsed.contains('xgrok') ||
      model.toLowerCase().contains('grok');

  factory SummarizerResult.fromJson(Map<String, dynamic> json) {
    final rawKeyPoints = json['keyPoints'] ?? json['key_points'] ?? json['highlights'];
    final keyPoints = rawKeyPoints is List
        ? rawKeyPoints.map((e) => e?.toString().trim() ?? '').where((s) => s.isNotEmpty).toList()
        : const <String>[];

    return SummarizerResult(
      title: _str(json, const ['title', 'headline']),
      summary: _str(json, const ['summary', 'content', 'text']),
      keyPoints: keyPoints,
      category: _str(json, const ['category', 'type']),
      readTime: (json['readTime'] is int)
          ? json['readTime'] as int
          : int.tryParse(json['readTime']?.toString() ?? '') ?? 3,
      source: _str(json, const ['source', 'domain']),
      extractionMethod: _str(json, const ['extractionMethod', 'extraction_method']),
      url: _str(json, const ['url']),
      model: _str(json, const ['model']),
      providerUsed: _str(json, const ['providerUsed', 'provider_used']),
      fallback: json['fallback'] == true,
    );
  }

  /// Camel-case JSON form, suitable for both Drift snapshots and the
  /// saved-search wire body.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'title': title,
        'summary': summary,
        'keyPoints': keyPoints,
        'category': category,
        'readTime': readTime,
        'source': source,
        'extractionMethod': extractionMethod,
        'url': url,
        'model': model,
        'providerUsed': providerUsed,
        'fallback': fallback,
      };
}

// ── Tavily Search ────────────────────────────────────────────────────────────

@immutable
class TavilySearchResponse {
  const TavilySearchResponse({
    required this.answer,
    required this.query,
    required this.results,
  });

  final String answer;
  final String query;
  final List<TavilyResultItem> results;

  factory TavilySearchResponse.fromJson(Map<String, dynamic> json) {
    final rawResults = json['results'];
    final results = rawResults is List
        ? rawResults
            .whereType<Map>()
            .map((r) => TavilyResultItem.fromJson(
                r.map((k, v) => MapEntry(k.toString(), v))))
            .toList()
        : const <TavilyResultItem>[];

    return TavilySearchResponse(
      answer: _str(json, const ['answer', 'response', 'text']),
      query: _str(json, const ['query']),
      results: results,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'answer': answer,
        'query': query,
        'results': results.map((r) => r.toJson()).toList(),
      };
}

@immutable
class TavilyResultItem {
  const TavilyResultItem({
    required this.title,
    required this.url,
    required this.content,
    required this.score,
  });

  final String title;
  final String url;
  final String content;
  final double score;

  factory TavilyResultItem.fromJson(Map<String, dynamic> json) {
    return TavilyResultItem(
      title: _str(json, const ['title']),
      url: _str(json, const ['url']),
      content: _str(json, const ['content', 'snippet']),
      score: (json['score'] is num) ? (json['score'] as num).toDouble() : 0,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'title': title,
        'url': url,
        'content': content,
        'score': score,
      };
}

// ── Grounded Search (Gemini + Google Search) ─────────────────────────────────

@immutable
class GroundedSearchResponse {
  const GroundedSearchResponse({
    required this.answer,
    required this.query,
    required this.model,
    required this.searchQueries,
    required this.sources,
    required this.citations,
  });

  final String answer;
  final String query;
  final String model;
  final List<String> searchQueries;
  final List<GroundedSource> sources;
  final List<GroundedCitation> citations;

  factory GroundedSearchResponse.fromJson(Map<String, dynamic> json) {
    final rawSources = json['sources'];
    final sources = rawSources is List
        ? rawSources
            .whereType<Map>()
            .map((s) => GroundedSource.fromJson(
                s.map((k, v) => MapEntry(k.toString(), v))))
            .toList()
        : const <GroundedSource>[];

    final rawCitations = json['citations'];
    final citations = rawCitations is List
        ? rawCitations
            .whereType<Map>()
            .map((c) => GroundedCitation.fromJson(
                c.map((k, v) => MapEntry(k.toString(), v))))
            .toList()
        : const <GroundedCitation>[];

    final rawQueries = json['searchQueries'];
    final queries = rawQueries is List
        ? rawQueries.whereType<String>().toList()
        : const <String>[];

    return GroundedSearchResponse(
      answer: _str(json, const ['answer', 'text']),
      query: _str(json, const ['query']),
      model: _str(json, const ['model']),
      searchQueries: queries,
      sources: sources,
      citations: citations,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'answer': answer,
        'query': query,
        'model': model,
        'searchQueries': searchQueries,
        'sources': sources.map((s) => s.toJson()).toList(),
        'citations': citations.map((c) => c.toJson()).toList(),
      };
}

@immutable
class GroundedSource {
  const GroundedSource({
    required this.index,
    required this.title,
    required this.url,
  });

  final int index;
  final String title;
  final String url;

  factory GroundedSource.fromJson(Map<String, dynamic> json) {
    return GroundedSource(
      index: (json['index'] is int) ? json['index'] as int : 0,
      title: _str(json, const ['title']),
      url: _str(json, const ['url', 'uri']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'index': index,
        'title': title,
        'url': url,
      };
}

@immutable
class GroundedCitation {
  const GroundedCitation({
    required this.text,
    required this.startIndex,
    required this.endIndex,
    required this.sourceIndices,
  });

  final String text;
  final int startIndex;
  final int endIndex;
  final List<int> sourceIndices;

  factory GroundedCitation.fromJson(Map<String, dynamic> json) {
    final raw = json['sourceIndices'];
    final indices = raw is List
        ? raw.whereType<int>().toList()
        : const <int>[];

    return GroundedCitation(
      text: _str(json, const ['text']),
      startIndex: (json['startIndex'] is int) ? json['startIndex'] as int : 0,
      endIndex: (json['endIndex'] is int) ? json['endIndex'] as int : 0,
      sourceIndices: indices,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'text': text,
        'startIndex': startIndex,
        'endIndex': endIndex,
        'sourceIndices': sourceIndices,
      };
}

// ── Article Follow-Up ────────────────────────────────────────────────────────

@immutable
class ArticleFollowUpResponse {
  const ArticleFollowUpResponse({
    required this.answer,
    required this.model,
    required this.sources,
    required this.searchQueries,
  });

  final String answer;
  final String model;
  final List<GroundedSource> sources;
  final List<String> searchQueries;

  factory ArticleFollowUpResponse.fromJson(Map<String, dynamic> json) {
    final rawSources = json['sources'];
    final sources = rawSources is List
        ? rawSources
            .whereType<Map>()
            .map((s) => GroundedSource.fromJson(
                s.map((k, v) => MapEntry(k.toString(), v))))
            .toList()
        : const <GroundedSource>[];

    final rawQueries = json['searchQueries'];
    final queries = rawQueries is List
        ? rawQueries.whereType<String>().toList()
        : const <String>[];

    return ArticleFollowUpResponse(
      answer: _str(json, const ['answer', 'text']),
      model: _str(json, const ['model']),
      sources: sources,
      searchQueries: queries,
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

String _str(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
  }
  return '';
}
