// Tests the Composer client: it must send only firstName + computed facts
// (never raw rows), parse the ResponseSpec, and fail soft (null) so the caller
// falls back to the deterministic template.

import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/data/services/expense_insight_service.dart';
import 'package:ai_nexus/domain/entities/expense_insight.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

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

InsightFacts _facts() => const InsightFacts(
      question: 'minimize my expenses',
      firstName: 'Monish',
      hasData: true,
      tone: InsightTone.warning,
      tokens: {
        'name': InsightToken('Monish'),
        'total': InsightToken('₹83,286', number: 83286),
        'topCategory.name': InsightToken('Food'),
      },
    );

void main() {
  group('ExpenseInsightService.compose', () {
    test('sends firstName + facts tokens, never raw expense rows', () async {
      final api = _FakeApi(response: {
        'greeting': 'Hey {{name}},',
        'headline': 'Food is your top spend.',
        'tip': 'Trim it.',
        'tone': 'warning',
        'chips': ['Compare to last month'],
      });
      final svc = ExpenseInsightService(api);
      final spec = await svc.compose(_facts(), liteModel: 'gemini-flash-lite');

      expect(spec, isNotNull);
      expect(spec!.tone, InsightTone.warning);
      expect(spec.chips, contains('Compare to last month'));

      final body = api.lastBody as Map;
      expect(body['firstName'], 'Monish');
      expect(body['liteModel'], 'gemini-flash-lite');
      expect(body['facts'], isA<Map>());
      // Facts carry display + value, never expense rows.
      final facts = body['facts'] as Map;
      expect(facts['name'], {'display': 'Monish'});
      expect(facts['total'], {'display': '₹83,286', 'value': 83286});
      expect(body.containsKey('expenses'), isFalse);
    });

    test('network failure fails soft (returns null)', () async {
      final svc = ExpenseInsightService(_FakeApi(throwError: true));
      expect(await svc.compose(_facts()), isNull);
    });

    test('non-map response fails soft', () async {
      final svc = ExpenseInsightService(_FakeApi(response: 'nope'));
      expect(await svc.compose(_facts()), isNull);
    });

    test('all-empty response is treated as no spec (null)', () async {
      final svc = ExpenseInsightService(_FakeApi(response: {
        'greeting': '',
        'headline': '',
        'tip': '',
        'chips': <String>[],
      }));
      expect(await svc.compose(_facts()), isNull);
    });
  });
}
