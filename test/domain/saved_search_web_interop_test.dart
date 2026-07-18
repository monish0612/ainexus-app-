// Cross-platform interop contract: a saved search created on the WEB must
// decode correctly on ANDROID, and vice-versa.
//
// This locks the exact wire shape the web's `saveSearch` now writes
// (responseType: 'grounded', responseJson in the GroundedSearchResponse
// shape) against Android's `SavedSearchEntry.fromJson` + `decodedResult()`.
// It is the regression net for the screenshot-2 bug where the phone showed
// the QUERY instead of the ANSWER because the web used an unknown
// responseType ('search').

import 'package:ai_nexus/domain/entities/saved_search.dart';
import 'package:ai_nexus/domain/entities/tutor_entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Web → Android saved-search interop', () {
    test(
        'web grounded payload (responseJson as a nested OBJECT) decodes to '
        'GroundedSearchResponse with the ANSWER + sources', () {
      // Exactly what the backend GET /saved-searches returns for a row the
      // web saved: responseType 'grounded', responseJson as a parsed object.
      final wire = <String, dynamic>{
        'id': 'srch-1',
        'kind': 'query',
        'query': 'current weather in chennai',
        'title': 'current weather in chennai',
        'responseType': 'grounded',
        'responseJson': <String, dynamic>{
          'answer': 'Chennai is sunny, 33°C.',
          'query': 'current weather in chennai',
          'model': 'gemini-3.1-flash-lite',
          'searchQueries': <String>['chennai weather'],
          'sources': <Map<String, dynamic>>[
            {'index': 1, 'title': 'Weather', 'url': 'https://x.test'},
          ],
          'citations': <dynamic>[],
        },
        'model': 'gemini-3.1-flash-lite',
        'provider': 'gemini',
        'mode': 'lite',
        'pinned': true,
        'savedAt': '2026-06-28T00:00:00Z',
        'updatedAt': '2026-06-28T00:00:00Z',
      };

      final entry = SavedSearchEntry.fromJson(wire);
      expect(entry.responseType, SavedSearchResponseType.grounded);

      final decoded = entry.decodedResult();
      expect(decoded, isA<GroundedSearchResponse>());
      final g = decoded as GroundedSearchResponse;
      expect(g.answer, 'Chennai is sunny, 33°C.',
          reason: 'the phone must render the ANSWER, not the query');
      expect(g.sources, hasLength(1));
      expect(g.sources.first.url, 'https://x.test');
      expect(g.model, 'gemini-3.1-flash-lite');
    });

    test(
        'legacy web shape (responseType "search") does NOT decode — documents '
        'the bug we fixed by switching the web to "grounded"', () {
      final wire = <String, dynamic>{
        'id': 's2',
        'kind': 'query',
        'query': 'q',
        'title': 'q',
        'responseType': 'search',
        'responseJson': <String, dynamic>{
          'answer': 'hi',
          'model': 'm',
          'sources': <dynamic>[],
          'searchQueries': <dynamic>[],
        },
        'savedAt': 't',
        'updatedAt': 't',
        'pinned': true,
      };
      final entry = SavedSearchEntry.fromJson(wire);
      expect(entry.decodedResult(), isNull,
          reason:
              'unknown responseType → null → Android fell back to rendering the '
              'query (the bug). The web now writes "grounded".');
    });

    test('responseJson delivered as a JSON STRING also decodes (defensive)', () {
      final wire = <String, dynamic>{
        'id': 's3',
        'kind': 'query',
        'query': 'q',
        'title': 'q',
        'responseType': 'grounded',
        'responseJson':
            '{"answer":"A","model":"m","sources":[],"searchQueries":[],"citations":[]}',
        'savedAt': 't',
        'updatedAt': 't',
        'pinned': true,
      };
      final entry = SavedSearchEntry.fromJson(wire);
      final g = entry.decodedResult() as GroundedSearchResponse;
      expect(g.answer, 'A');
    });

    test(
        'snake_case inbound keys are tolerated (response_type / response_json / '
        'saved_at) — server flexibility guarantee', () {
      final wire = <String, dynamic>{
        'id': 's4',
        'kind': 'query',
        'query': 'q',
        'title': 'q',
        'response_type': 'grounded',
        'response_json': <String, dynamic>{
          'answer': 'snake answer',
          'model': 'm',
          'sources': <dynamic>[],
          'searchQueries': <dynamic>[],
          'citations': <dynamic>[],
        },
        'saved_at': '2026-06-28T00:00:00Z',
        'updated_at': '2026-06-28T00:00:00Z',
        'pinned': true,
      };
      final entry = SavedSearchEntry.fromJson(wire);
      expect(entry.responseType, SavedSearchResponseType.grounded);
      final g = entry.decodedResult() as GroundedSearchResponse;
      expect(g.answer, 'snake answer');
    });
  });
}
