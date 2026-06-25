// Unit tests for the AI expense-search service + its query-spec parsing.
// The service must (a) send only the question + schema hints (never raw rows),
// (b) robustly parse / sanitize whatever the LLM returns, and (c) fail soft
// (return null) so the UI can fall back to a plain keyword search.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/data/repositories/expense_repository.dart';
import 'package:ai_nexus/data/services/expense_ai_search_service.dart';

class _FakeApi extends ApiClient {
  _FakeApi({this.response, this.throwError = false});

  Object? response;
  bool throwError;
  Object? lastBody;
  String? lastPath;

  @override
  Future<Response<T>> post<T>(String path,
      {Object? data, Options? options, CancelToken? cancelToken}) async {
    lastPath = path;
    lastBody = data;
    if (throwError) {
      throw DioException(requestOptions: RequestOptions(path: path));
    }
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data: response as T?,
      statusCode: 200,
    );
  }
}

void main() {
  group('ExpenseQuerySpec.fromJson', () {
    test('parses a full spec and maps sort', () {
      final spec = ExpenseQuerySpec.fromJson({
        'title': "Today's expenses",
        'answer': 'Here is what you spent today.',
        'startIso': '2026-06-25T00:00:00',
        'endIso': '2026-06-26T00:00:00',
        'category': 'Food',
        'search': 'swiggy',
        'sort': 'amount_desc',
        'limit': 100,
        'mode': 'summary',
        'model': 'gemini-x',
      });
      expect(spec.title, "Today's expenses");
      expect(spec.startIso, '2026-06-25T00:00:00');
      expect(spec.category, 'Food');
      expect(spec.search, 'swiggy');
      expect(spec.sort, ExpenseSort.amountDesc);
      expect(spec.limit, 100);
      expect(spec.isSummary, isTrue);
    });

    test('blank strings become null; bad sort falls back to date desc', () {
      final spec = ExpenseQuerySpec.fromJson({
        'title': '',
        'startIso': '   ',
        'category': '',
        'search': null,
        'sort': 'nonsense',
        'mode': 'list',
      });
      expect(spec.title, 'Results');
      expect(spec.startIso, isNull);
      expect(spec.category, isNull);
      expect(spec.search, isNull);
      expect(spec.sort, ExpenseSort.dateDesc);
      expect(spec.isSummary, isFalse);
    });

    test('limit clamps to 1..500 and tolerates strings/garbage', () {
      expect(ExpenseQuerySpec.fromJson({'limit': 9999}).limit, 500);
      expect(ExpenseQuerySpec.fromJson({'limit': 0}).limit, 1);
      expect(ExpenseQuerySpec.fromJson({'limit': '42'}).limit, 42);
      expect(ExpenseQuerySpec.fromJson({'limit': 'abc'}).limit, 500);
      expect(ExpenseQuerySpec.fromJson(<String, dynamic>{}).limit, 500);
    });

    test('searchAny is sanitized: trimmed, deduped, capped, type-safe', () {
      final spec = ExpenseQuerySpec.fromJson({
        'searchAny': [
          'car', ' Fuel ', 'fuel', 'CAR', // dupes (case-insensitive) + trim
          '', '   ', 42, null, // junk dropped
          'x' * 41, // too long, dropped
          'garage', 'service', 'tyre', 'insurance', 'parking',
          'toll', 'uber', 'ola', 'diesel', 'petrol', 'wash', // > 12 total
        ],
      });
      // Deduped (car/CAR → one, fuel/Fuel → one), junk removed, capped at 12.
      expect(spec.searchTerms.length, 12);
      expect(spec.searchTerms, contains('car'));
      expect(spec.searchTerms, contains('Fuel')); // first-seen form kept
      expect(spec.searchTerms.where((t) => t.toLowerCase() == 'car').length, 1);
      expect(spec.searchTerms.where((t) => t.toLowerCase() == 'fuel').length, 1);
      expect(spec.searchTerms.every((t) => t.trim().isNotEmpty), isTrue);
      expect(spec.searchTerms.every((t) => t.length <= 40), isTrue);
    });

    test('missing / non-list searchAny yields an empty list', () {
      expect(ExpenseQuerySpec.fromJson(<String, dynamic>{}).searchTerms, isEmpty);
      expect(
        ExpenseQuerySpec.fromJson({'searchAny': 'not-a-list'}).searchTerms,
        isEmpty,
      );
      expect(
        ExpenseQuerySpec.fromJson({'searchAny': null}).searchTerms,
        isEmpty,
      );
    });

    test('chart type parses only when mode is "chart"', () {
      expect(
        ExpenseQuerySpec.fromJson({'mode': 'chart', 'chartType': 'daily'}).chart,
        ExpenseChart.daily,
      );
      expect(
        ExpenseQuerySpec.fromJson({'mode': 'chart', 'chartType': 'monthly'})
            .chart,
        ExpenseChart.monthly,
      );
      expect(
        ExpenseQuerySpec.fromJson({'mode': 'chart', 'chartType': 'category'})
            .chart,
        ExpenseChart.category,
      );
      // chart requested but type missing/garbage → defaults to category.
      expect(
        ExpenseQuerySpec.fromJson({'mode': 'chart', 'chartType': 'xyz'}).chart,
        ExpenseChart.category,
      );
      // Not a chart request → none, even if chartType is present.
      expect(
        ExpenseQuerySpec.fromJson({'mode': 'list', 'chartType': 'daily'}).chart,
        ExpenseChart.none,
      );
      expect(ExpenseQuerySpec.fromJson({'mode': 'summary'}).chart,
          ExpenseChart.none);
    });

    test('topic parses salary; defaults to expenses otherwise', () {
      expect(
        ExpenseQuerySpec.fromJson({'topic': 'salary'}).isSalaryTopic,
        isTrue,
      );
      expect(
        ExpenseQuerySpec.fromJson({'topic': 'expenses'}).isSalaryTopic,
        isFalse,
      );
      expect(
        ExpenseQuerySpec.fromJson(<String, dynamic>{}).isSalaryTopic,
        isFalse,
      );
      expect(
        ExpenseQuerySpec.fromJson({'topic': 'something-else'}).isSalaryTopic,
        isFalse,
      );
    });
  });

  group('ExpenseAiSearchService.query', () {
    test('sends question + categories + now, never expense rows', () async {
      final api = _FakeApi(response: {
        'title': 'Food',
        'answer': 'ok',
        'sort': 'date_desc',
        'category': 'Food',
      });
      final svc = ExpenseAiSearchService(api);
      final spec = await svc.query(
        'food today',
        categories: ['Food', 'Travel'],
        liteModel: 'gemini-flash-lite',
      );
      expect(spec, isNotNull);
      expect(spec!.category, 'Food');
      final body = api.lastBody as Map;
      expect(body['question'], 'food today');
      expect(body['categories'], ['Food', 'Travel']);
      expect(body['liteModel'], 'gemini-flash-lite');
      expect(body['now'], isA<String>());
      // No expense data is ever transmitted.
      expect(body.containsKey('expenses'), isFalse);
    });

    test('empty question short-circuits without a network call', () async {
      final api = _FakeApi(response: {});
      final svc = ExpenseAiSearchService(api);
      final spec = await svc.query('   ');
      expect(spec, isNull);
      expect(api.lastPath, isNull);
    });

    test('network failure fails soft (returns null)', () async {
      final api = _FakeApi(throwError: true);
      final svc = ExpenseAiSearchService(api);
      final spec = await svc.query('highest expense');
      expect(spec, isNull);
    });

    test('non-map response fails soft (returns null)', () async {
      final api = _FakeApi(response: 'not a map');
      final svc = ExpenseAiSearchService(api);
      final spec = await svc.query('anything');
      expect(spec, isNull);
    });
  });
}
