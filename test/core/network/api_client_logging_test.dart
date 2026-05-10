// Locks down the severity policy of the HTTP logging interceptor.
//
// Background:
//   Production users were getting flooded in Telegram with the verbose
//   `DioException [bad response]: This exception was thrown because the
//    response has a status code of 404 …` text every time a routine 4xx
//   bubbled out of the dio pipeline. The interceptor used to call
//   `TLog.e(..., error: err)` for ALL errors, which serializes the full
//   exception stringification into the Telegram batch.
//
//   The new policy (locked down by these tests) is:
//     • cancel       → no log at all (control-flow signal, not an error)
//     • 4xx          → TLog.w (warning), NO `error:` payload attached
//     • 5xx          → TLog.e (error)   WITH `error:` payload (full DioException)
//     • network err  → TLog.e (error)   WITH `error:` payload
//
//   The test composes a slim Dio that has ONLY [LoggingInterceptor] (no
//   retry loop) and uses [TLog.debugOnLog] to spy on every emitted entry.

import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/core/services/telegram_logger.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _LogRecord {
  _LogRecord(this.level, this.tag, this.message, this.error);
  final String level; // 'debug' | 'info' | 'warning' | 'error' | 'fatal'
  final String tag;
  final String message;
  final Object? error;

  @override
  String toString() =>
      '[$level $tag] $message${error != null ? ' ⤷ $error' : ''}';
}

class _LogSpy {
  final entries = <_LogRecord>[];
  void install() {
    TLog.debugOnLog = (level, tag, message, {error}) {
      entries.add(_LogRecord(level, tag, message, error));
    };
  }

  void uninstall() {
    TLog.debugOnLog = null;
  }

  Iterable<_LogRecord> httpFailureEntries() =>
      entries.where((e) => e.tag == 'HTTP' && e.message.startsWith('✖'));
}

class _AlwaysThrowAdapter implements HttpClientAdapter {
  _AlwaysThrowAdapter({required this.statusCode, required this.type});
  final int? statusCode;
  final DioExceptionType type;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException(
      requestOptions: options,
      type: type,
      response: statusCode == null
          ? null
          : Response<dynamic>(
              requestOptions: options,
              statusCode: statusCode,
              data: 'fake $statusCode body',
            ),
      message:
          'fake adapter throw (status=$statusCode, type=${type.name})',
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Build a Dio that has ONLY the [LoggingInterceptor]. Skipping the retry
/// loop keeps tests fast and isolates the policy under test.
Dio _diOnlyLogging({required HttpClientAdapter adapter}) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
  dio.httpClientAdapter = adapter;
  dio.interceptors.add(LoggingInterceptor());
  return dio;
}

Future<void> _hit({
  required int? statusCode,
  required DioExceptionType type,
  CancelToken? cancelToken,
}) async {
  final dio = _diOnlyLogging(
    adapter: _AlwaysThrowAdapter(statusCode: statusCode, type: type),
  );
  try {
    await dio.get<Object?>('/sentinel-path', cancelToken: cancelToken);
  } catch (_) {/* expected */}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _LogSpy spy;

  setUp(() {
    spy = _LogSpy()..install();
  });

  tearDown(() {
    spy.uninstall();
  });

  group('LoggingInterceptor — severity policy', () {
    test('404 → warning only, no DioException body attached', () async {
      await _hit(statusCode: 404, type: DioExceptionType.badResponse);

      final http = spy.httpFailureEntries().toList();
      expect(http, hasLength(1),
          reason: '4xx must surface exactly one log entry from the logger '
              '(no retry interceptor in this test)');
      expect(http.single.level, equals('warning'),
          reason: '4xx must be logged at warning level, not error');
      expect(http.single.error, isNull,
          reason:
              '4xx must NOT attach the verbose DioException — that text was '
              'flooding Telegram with stack-trace-shaped noise');
      expect(http.single.message, contains('[404]'));
      expect(http.single.message, contains('/sentinel-path'));
      expect(http.single.message, contains('GET'));
    });

    test('400 → warning, no DioException body', () async {
      await _hit(statusCode: 400, type: DioExceptionType.badResponse);
      final http = spy.httpFailureEntries().toList();
      expect(http, hasLength(1));
      expect(http.single.level, equals('warning'));
      expect(http.single.error, isNull);
      expect(http.single.message, contains('[400]'));
    });

    test('429 → warning, no DioException body', () async {
      await _hit(statusCode: 429, type: DioExceptionType.badResponse);
      final http = spy.httpFailureEntries().toList();
      expect(http, hasLength(1));
      expect(http.single.level, equals('warning'));
      expect(http.single.error, isNull);
    });

    test('499 (last 4xx) → still a warning', () async {
      await _hit(statusCode: 499, type: DioExceptionType.badResponse);
      final http = spy.httpFailureEntries().toList();
      expect(http, hasLength(1));
      expect(http.single.level, equals('warning'));
    });

    test('500 → error WITH DioException body attached', () async {
      await _hit(statusCode: 500, type: DioExceptionType.badResponse);
      final http = spy.httpFailureEntries().toList();
      expect(http, hasLength(1));
      expect(http.single.level, equals('error'),
          reason: '5xx must escalate to error level');
      expect(http.single.error, isA<DioException>(),
          reason: '5xx must include the DioException for triage');
      expect((http.single.error as DioException).response?.statusCode,
          equals(500));
    });

    test('502 / 503 / 504 → error WITH DioException body', () async {
      for (final code in [502, 503, 504]) {
        spy.entries.clear();
        await _hit(statusCode: code, type: DioExceptionType.badResponse);
        final http = spy.httpFailureEntries().toList();
        expect(http, hasLength(1), reason: 'one log per request, code=$code');
        expect(http.single.level, equals('error'),
            reason: '$code must escalate to error');
        expect(http.single.error, isA<DioException>());
      }
    });

    test('connectionError (network down) → error WITH DioException body',
        () async {
      await _hit(statusCode: null, type: DioExceptionType.connectionError);
      final http = spy.httpFailureEntries().toList();
      expect(http, hasLength(1));
      expect(http.single.level, equals('error'));
      expect(http.single.error, isA<DioException>());
    });

    test('receiveTimeout → error WITH DioException body', () async {
      await _hit(statusCode: null, type: DioExceptionType.receiveTimeout);
      final http = spy.httpFailureEntries().toList();
      expect(http.single.level, equals('error'));
      expect(http.single.error, isA<DioException>());
    });

    test('cancel → produces NO ✖ HTTP log at all', () async {
      final ct = CancelToken()..cancel('test-cancel');
      await _hit(
        statusCode: null,
        type: DioExceptionType.cancel,
        cancelToken: ct,
      );

      // The request log line (→) is fine; only the failure (✖) must be absent.
      final failureLogs = spy.httpFailureEntries().toList();
      expect(failureLogs, isEmpty,
          reason: 'cancellation is a control-flow signal, never an error');
    });
  });
}
