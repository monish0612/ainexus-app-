// Domain tests for SavedSearchEntry — exercises round-trips between the
// in-app entity, the wire format, and the typed result DTOs.

import 'dart:convert';

import 'package:ai_nexus/domain/entities/saved_search.dart';
import 'package:ai_nexus/domain/entities/tutor_entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SavedSearchEntry', () {
    group('deriveTitle', () {
      test('strips path-trailing slash from URLs', () {
        expect(
          SavedSearchEntry.deriveTitle(
            kind: SavedSearchKind.url,
            query: 'https://example.com/articles/test/',
          ),
          equals('example.com/articles/test'),
        );
      });

      test('returns hostname-only when path is empty', () {
        expect(
          SavedSearchEntry.deriveTitle(
            kind: SavedSearchKind.url,
            query: 'https://example.com',
          ),
          equals('example.com'),
        );
      });

      test('truncates long text queries with an ellipsis', () {
        final long = 'a' * 200;
        final title = SavedSearchEntry.deriveTitle(
          kind: SavedSearchKind.query,
          query: long,
        );
        expect(title.length, lessThanOrEqualTo(80));
        expect(title.endsWith('\u2026'), isTrue);
      });

      test('preserves short queries verbatim', () {
        expect(
          SavedSearchEntry.deriveTitle(
            kind: SavedSearchKind.query,
            query: 'today\'s ipl match',
          ),
          equals('today\'s ipl match'),
        );
      });
    });

    group('decodedResult', () {
      test('summarizer JSON round-trips into a SummarizerResult', () {
        const original = SummarizerResult(
          title: 't',
          summary: 's',
          keyPoints: ['a', 'b'],
          category: 'c',
          readTime: 3,
          source: 'src',
          extractionMethod: 'em',
          url: 'u',
          model: 'm',
          providerUsed: 'gemini',
        );
        final entry = SavedSearchEntry(
          id: 'id',
          kind: SavedSearchKind.url,
          query: 'q',
          title: 't',
          responseType: SavedSearchResponseType.summarizer,
          responseJson: jsonEncode(original.toJson()),
          savedAt: '2024-01-01T00:00:00Z',
          updatedAt: '2024-01-01T00:00:00Z',
        );
        final decoded = entry.decodedResult();
        expect(decoded, isA<SummarizerResult>());
        expect((decoded as SummarizerResult).summary, equals('s'));
        expect(decoded.keyPoints, equals(['a', 'b']));
        expect(decoded.providerUsed, equals('gemini'));
      });

      test('grounded JSON round-trips into a GroundedSearchResponse', () {
        const original = GroundedSearchResponse(
          answer: 'ans',
          query: 'q',
          model: 'gemini-2.5',
          searchQueries: ['s1'],
          sources: [
            GroundedSource(index: 0, title: 'src', url: 'https://s.example')
          ],
          citations: [],
        );
        final entry = SavedSearchEntry(
          id: 'id',
          kind: SavedSearchKind.query,
          query: 'q',
          title: 'q',
          responseType: SavedSearchResponseType.grounded,
          responseJson: jsonEncode(original.toJson()),
          savedAt: '2024-01-01T00:00:00Z',
          updatedAt: '2024-01-01T00:00:00Z',
        );
        final decoded = entry.decodedResult();
        expect(decoded, isA<GroundedSearchResponse>());
        expect((decoded as GroundedSearchResponse).answer, equals('ans'));
        expect(decoded.sources, hasLength(1));
        expect(decoded.sources.first.url, equals('https://s.example'));
      });

      test('tavily JSON round-trips into a TavilySearchResponse', () {
        const original = TavilySearchResponse(
          answer: 'ans',
          query: 'q',
          results: [
            TavilyResultItem(
                title: 't',
                url: 'https://t.example',
                content: 'c',
                score: 0.9),
          ],
        );
        final entry = SavedSearchEntry(
          id: 'id',
          kind: SavedSearchKind.query,
          query: 'q',
          title: 'q',
          responseType: SavedSearchResponseType.tavily,
          responseJson: jsonEncode(original.toJson()),
          savedAt: '2024-01-01T00:00:00Z',
          updatedAt: '2024-01-01T00:00:00Z',
        );
        final decoded = entry.decodedResult();
        expect(decoded, isA<TavilySearchResponse>());
        expect((decoded as TavilySearchResponse).results, hasLength(1));
        expect(decoded.results.first.score, closeTo(0.9, 1e-6));
      });

      test('returns null for an unknown response type', () {
        const entry = SavedSearchEntry(
          id: 'id',
          kind: SavedSearchKind.query,
          query: 'q',
          title: 'q',
          responseType: 'unknown',
          responseJson: '{}',
          savedAt: '2024-01-01T00:00:00Z',
          updatedAt: '2024-01-01T00:00:00Z',
        );
        expect(entry.decodedResult(), isNull);
      });

      test('returns null for malformed JSON', () {
        const entry = SavedSearchEntry(
          id: 'id',
          kind: SavedSearchKind.query,
          query: 'q',
          title: 'q',
          responseType: SavedSearchResponseType.tavily,
          responseJson: '{not-json',
          savedAt: '2024-01-01T00:00:00Z',
          updatedAt: '2024-01-01T00:00:00Z',
        );
        expect(entry.decodedResult(), isNull);
      });
    });

    group('JSON wire format', () {
      test('round-trips toJson → fromJson preserving values', () {
        final entry = SavedSearchEntry(
          id: 'id-1',
          kind: SavedSearchKind.url,
          query: 'https://example.com',
          title: 'example.com',
          responseType: SavedSearchResponseType.summarizer,
          responseJson: jsonEncode({'title': 'hi', 'summary': 'world'}),
          model: 'gemini',
          provider: 'gemini',
          mode: 'lite',
          savedAt: '2024-01-01T00:00:00Z',
          updatedAt: '2024-01-02T00:00:00Z',
          pinned: true,
        );

        final wire = entry.toJson();
        final reconstructed = SavedSearchEntry.fromJson(wire);
        expect(reconstructed.id, equals(entry.id));
        expect(reconstructed.kind, equals(entry.kind));
        expect(reconstructed.title, equals(entry.title));
        expect(reconstructed.responseType, equals(entry.responseType));
        expect(reconstructed.model, equals(entry.model));
        expect(reconstructed.savedAt, equals(entry.savedAt));
        expect(reconstructed.updatedAt, equals(entry.updatedAt));
        // The wire form sends responseJson as a structured object when it
        // parses cleanly — when read back it's re-encoded to the same
        // canonical JSON string.
        expect(jsonDecode(reconstructed.responseJson), isMap);
      });

      test('fromJson tolerates snake_case field names', () {
        final wire = <String, dynamic>{
          'id': 'a',
          'kind': SavedSearchKind.query,
          'query': 'q',
          'title': 't',
          'response_type': SavedSearchResponseType.tavily,
          'response_json': {'answer': 'x'},
          'saved_at': '2024-01-01T00:00:00Z',
          'updated_at': '2024-01-01T00:00:00Z',
        };
        final entry = SavedSearchEntry.fromJson(wire);
        expect(entry.responseType, equals(SavedSearchResponseType.tavily));
        expect(entry.savedAt, equals('2024-01-01T00:00:00Z'));
        expect(entry.updatedAt, equals('2024-01-01T00:00:00Z'));
      });
    });

    test('copyWith.clearDeletedAt nulls the tombstone', () {
      const entry = SavedSearchEntry(
        id: 'id',
        kind: SavedSearchKind.query,
        query: 'q',
        title: 'q',
        responseType: SavedSearchResponseType.tavily,
        responseJson: '{}',
        savedAt: '2024-01-01T00:00:00Z',
        updatedAt: '2024-01-01T00:00:00Z',
        deletedAt: '2024-02-01T00:00:00Z',
      );
      expect(entry.deletedAt, isNotNull);
      final undeleted = entry.copyWith(clearDeletedAt: true);
      expect(undeleted.deletedAt, isNull);
    });
  });
}
