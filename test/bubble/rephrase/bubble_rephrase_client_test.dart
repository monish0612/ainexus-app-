import 'package:ai_nexus/bubble/rephrase/bubble_rephrase_client.dart';
import 'package:ai_nexus/bubble/rephrase/resilience.dart';
import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/data/services/tutor_ai_service.dart';
import 'package:ai_nexus/domain/entities/tutor_entities.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records every rephrase call and replays a scripted response, so the client's
/// caching, retry and error mapping can be tested without a network.
class _FakeTutorAiService extends TutorAiService {
  _FakeTutorAiService({this.error, this.reply = 'rephrased'}) : super(ApiClient());

  final Object? error;
  final String reply;

  int calls = 0;
  final List<Map<String, String?>> received = [];

  /// Fails this many times before succeeding, to exercise the backoff path.
  int failuresBeforeSuccess = 0;

  @override
  Future<RephraseResult> rephrase({
    required String text,
    required String platform,
    String? intent,
    String? liteModel,
  }) async {
    calls++;
    received.add({
      'text': text,
      'platform': platform,
      'intent': intent,
      'liteModel': liteModel,
    });
    if (failuresBeforeSuccess >= calls) {
      throw DioException(
        requestOptions: RequestOptions(path: '/rephrase'),
        response: Response(
          requestOptions: RequestOptions(path: '/rephrase'),
          statusCode: 503,
        ),
      );
    }
    if (error != null) throw error!;
    return RephraseResult(platform: platform, rephrasedText: reply);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('BubbleRephraseClient — request shape', () {
    test('sends the platform id with no intent for a normal chip', () async {
      final service = _FakeTutorAiService();
      final client = BubbleRephraseClient(service: service);

      final result = await client.rephrase(
        text: '  hello there  ',
        platform: 'whatsapp',
      );

      expect(result, 'rephrased');
      expect(service.received.single['platform'], 'whatsapp');
      expect(service.received.single['intent'], isNull);
      // Text is trimmed before it goes out.
      expect(service.received.single['text'], 'hello there');
    });

    test('strips the "rephrase to" leader from an Own tone', () async {
      final service = _FakeTutorAiService();
      final client = BubbleRephraseClient(service: service);

      await client.rephrase(
        text: 'move the meeting',
        platform: 'own',
        intent: 'Rephrase to professional simple',
      );

      expect(service.received.single['platform'], 'own');
      expect(service.received.single['intent'], 'professional simple');
    });

    test('treats a blank Own tone as no intent', () async {
      final service = _FakeTutorAiService();
      final client = BubbleRephraseClient(service: service);

      await client.rephrase(text: 'text here', platform: 'own', intent: '   ');
      expect(service.received.single['intent'], isNull);
    });

    test('forwards the lite model chosen in app settings', () async {
      SharedPreferences.setMockInitialValues({'lite_model': 'gemini-flash-lite'});
      final service = _FakeTutorAiService();
      final client = BubbleRephraseClient(service: service);

      await client.rephrase(text: 'text here', platform: 'casual');
      expect(service.received.single['liteModel'], 'gemini-flash-lite');
    });

    test('forwards a newer flash-lite id verbatim, not a hardcoded default',
        () async {
      SharedPreferences.setMockInitialValues({
        'lite_model': 'gemini-3.5-flash-lite',
      });
      final service = _FakeTutorAiService();
      final client = BubbleRephraseClient(service: service);

      await client.rephrase(text: 'text here', platform: 'fix');
      expect(service.received.single['liteModel'], 'gemini-3.5-flash-lite');
      expect(service.received.single['platform'], 'fix');
    });

    test('a Settings change to another flash-lite is sent on the next miss',
        () async {
      SharedPreferences.setMockInitialValues({
        'lite_model': 'gemini-3.1-flash-lite-preview',
      });
      final service = _FakeTutorAiService();
      final client = BubbleRephraseClient(service: service);

      await client.rephrase(text: 'hello', platform: 'fix');
      expect(
        service.received.single['liteModel'],
        'gemini-3.1-flash-lite-preview',
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lite_model', 'gemini-3.5-flash-lite');
      await client.rephrase(text: 'other text', platform: 'fix');
      expect(service.received.last['liteModel'], 'gemini-3.5-flash-lite');
    });

    test('blank lite_model is omitted so the API uses its default', () async {
      SharedPreferences.setMockInitialValues({'lite_model': '   '});
      final service = _FakeTutorAiService();
      final client = BubbleRephraseClient(service: service);

      await client.rephrase(text: 'text here', platform: 'casual');
      expect(service.received.single['liteModel'], isNull);
    });

    test('refuses empty text without calling the server', () async {
      final service = _FakeTutorAiService();
      final client = BubbleRephraseClient(service: service);

      await expectLater(
        client.rephrase(text: '   ', platform: 'casual'),
        throwsA(
          isA<BubbleError>().having(
            (e) => e.kind,
            'kind',
            BubbleErrorKind.permanent,
          ),
        ),
      );
      expect(service.calls, 0);
    });
  });

  group('BubbleRephraseClient — cache', () {
    test('repeat taps on the same chip are served from cache', () async {
      final service = _FakeTutorAiService();
      final client = BubbleRephraseClient(service: service);

      await client.rephrase(text: 'same text', platform: 'casual');
      await client.rephrase(text: 'same text', platform: 'casual');
      expect(service.calls, 1);
    });

    test('changing the Settings lite model is a different cache entry',
        () async {
      SharedPreferences.setMockInitialValues({
        'lite_model': 'gemini-3.1-flash-lite-preview',
      });
      final service = _FakeTutorAiService();
      final client = BubbleRephraseClient(service: service);

      await client.rephrase(text: 'same text', platform: 'casual');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lite_model', 'gemini-3.5-flash-lite');
      await client.rephrase(text: 'same text', platform: 'casual');
      expect(service.calls, 2);
      expect(service.received[0]['liteModel'], 'gemini-3.1-flash-lite-preview');
      expect(service.received[1]['liteModel'], 'gemini-3.5-flash-lite');
    });

    test('a different platform is a different cache entry', () async {
      final service = _FakeTutorAiService();
      final client = BubbleRephraseClient(service: service);

      await client.rephrase(text: 'same text', platform: 'casual');
      await client.rephrase(text: 'same text', platform: 'slack');
      expect(service.calls, 2);
    });

    test('a different Own tone is a different cache entry', () async {
      final service = _FakeTutorAiService();
      final client = BubbleRephraseClient(service: service);

      await client.rephrase(text: 'same', platform: 'own', intent: 'formal');
      await client.rephrase(text: 'same', platform: 'own', intent: 'casual');
      expect(service.calls, 2);
    });

    test('equivalent tones with different leaders hit the same entry', () async {
      final service = _FakeTutorAiService();
      final client = BubbleRephraseClient(service: service);

      await client.rephrase(text: 'same', platform: 'own', intent: 'formal');
      await client.rephrase(
        text: 'same',
        platform: 'own',
        intent: 'rephrase to formal',
      );
      expect(service.calls, 1);
    });

    test('fresh bypasses the cache (New version) and refreshes the entry',
        () async {
      final service = _FakeTutorAiService();
      final client = BubbleRephraseClient(service: service);

      await client.rephrase(text: 'same text', platform: 'casual');
      await client.rephrase(text: 'same text', platform: 'casual', fresh: true);
      expect(service.calls, 2, reason: 'fresh must hit the server');

      // The fresh result replaced the cached one, so a plain call is a hit.
      await client.rephrase(text: 'same text', platform: 'casual');
      expect(service.calls, 2);
    });

    test('unicode, emoji and newlines round-trip without being rewritten',
        () async {
      final service = _FakeTutorAiService();
      final client = BubbleRephraseClient(service: service);
      const source = 'नमस्ते 😊\nline two — café';

      await client.rephrase(text: source, platform: 'fix');
      expect(service.received.single['text'], source);
      expect(service.received.single['platform'], 'fix');
    });

    test('handles multi-thousand-character text without truncation', () async {
      final service = _FakeTutorAiService();
      final client = BubbleRephraseClient(service: service);

      final huge = 'long sentence with many words here. ' * 300;
      await client.rephrase(text: huge, platform: 'casual');
      expect(service.received.single['text'], huge.trim());
    });
  });

  group('BubbleRephraseClient — failures', () {
    test('retries a transient 503 and then succeeds', () async {
      final service = _FakeTutorAiService()..failuresBeforeSuccess = 1;
      final client = BubbleRephraseClient(service: service);

      final result = await client.rephrase(text: 'text here', platform: 'casual');
      expect(result, 'rephrased');
      expect(service.calls, 2);
    });

    test('surfaces an auth failure immediately without retrying', () async {
      final service = _FakeTutorAiService(
        error: DioException(
          requestOptions: RequestOptions(path: '/rephrase'),
          response: Response(
            requestOptions: RequestOptions(path: '/rephrase'),
            statusCode: 401,
          ),
        ),
      );
      final client = BubbleRephraseClient(service: service);

      await expectLater(
        client.rephrase(text: 'text here', platform: 'casual'),
        throwsA(
          isA<BubbleError>().having(
            (e) => e.kind,
            'kind',
            BubbleErrorKind.permanent,
          ),
        ),
      );
      expect(service.calls, 1);
    });

    test('reports offline as a short, friendly message', () async {
      final service = _FakeTutorAiService(
        error: DioException(
          requestOptions: RequestOptions(path: '/rephrase'),
          type: DioExceptionType.connectionError,
        ),
      );
      final client = BubbleRephraseClient(service: service);

      try {
        await client.rephrase(text: 'text here', platform: 'casual');
        fail('should have thrown');
      } on BubbleError catch (e) {
        expect(e.display, 'No network');
      }
    });

    test('an empty rephrase is treated as a failure, not written back',
        () async {
      final service = _FakeTutorAiService(reply: '   ');
      final client = BubbleRephraseClient(service: service);

      await expectLater(
        client.rephrase(text: 'text here', platform: 'casual'),
        throwsA(isA<BubbleError>()),
      );
    });

    test('cache keys distinguish rewrite platforms from tones', () async {
      final service = _FakeTutorAiService();
      final client = BubbleRephraseClient(service: service);

      await client.rephrase(text: 'same text', platform: 'fix');
      await client.rephrase(text: 'same text', platform: 'casual');
      expect(service.calls, 2);
    });

    test('a 422 without a REFUSAL envelope is still permanent', () async {
      final service = _FakeTutorAiService(
        error: DioException(
          requestOptions: RequestOptions(path: '/rephrase'),
          response: Response(
            requestOptions: RequestOptions(path: '/rephrase'),
            statusCode: 422,
            data: {
              'error': {'code': 'VALIDATION', 'message': 'too long'},
            },
          ),
        ),
      );
      final client = BubbleRephraseClient(service: service);

      await expectLater(
        client.rephrase(text: 'text here', platform: 'casual'),
        throwsA(
          isA<BubbleError>()
              .having((e) => e.kind, 'kind', BubbleErrorKind.permanent)
              .having((e) => e.display, 'display', 'Request failed (422)'),
        ),
      );
      expect(service.calls, 1);
    });

    test('a model refusal is permanent and is not cached', () async {
      final service = _FakeTutorAiService(
        reply: "I can't help with that request as an AI.",
      );
      final client = BubbleRephraseClient(service: service);

      await expectLater(
        client.rephrase(text: 'text here', platform: 'casual'),
        throwsA(
          isA<BubbleError>()
              .having((e) => e.kind, 'kind', BubbleErrorKind.permanent)
              .having((e) => e.display, 'display', 'Blocked — try another tone'),
        ),
      );
      expect(service.calls, 1);

      // Refusal must not land in the LRU — a retry hits the server again.
      await expectLater(
        client.rephrase(text: 'text here', platform: 'casual'),
        throwsA(isA<BubbleError>()),
      );
      expect(service.calls, 2);
    });

    test('a 422 REFUSAL from the server is not retried', () async {
      final service = _FakeTutorAiService(
        error: DioException(
          requestOptions: RequestOptions(path: '/rephrase'),
          response: Response(
            requestOptions: RequestOptions(path: '/rephrase'),
            statusCode: 422,
            data: {
              'error': {
                'code': 'REFUSAL',
                'message': 'Blocked — try another tone',
              },
            },
          ),
        ),
      );
      final client = BubbleRephraseClient(service: service);

      await expectLater(
        client.rephrase(text: 'text here', platform: 'fix'),
        throwsA(
          isA<BubbleError>().having(
            (e) => e.display,
            'display',
            'Blocked — try another tone',
          ),
        ),
      );
      expect(service.calls, 1);
    });
  });
}
