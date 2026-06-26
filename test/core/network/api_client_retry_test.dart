// Hermetic tests for the Dio _RetryInterceptor wired into ApiClient.
//
// We swap in a scripted HttpClientAdapter so no real network is touched, and
// drive the exact retry/backoff/give-up behaviour:
//   • retryable transient (connectionError) → retried then succeeds
//   • retryable status (503 / 429) → retried then succeeds
//   • non-retryable status (400 / 404) → NOT retried, error bubbles once
//   • persistent retryable failure → original + 3 retries (4 calls) then fails
//
// Backoff is real (500ms→1s→2s base) so the exhaustion test is a few seconds.

import 'dart:typed_data';

import 'package:ai_nexus/core/network/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// One scripted outcome for a single adapter `fetch`.
class _Outcome {
  const _Outcome.status(this.status) : error = null;
  const _Outcome.connectionError()
      : status = null,
        error = DioExceptionType.connectionError;

  final int? status;
  final DioExceptionType? error;
}

/// Returns scripted outcomes in order; the last one repeats if calls exceed
/// the script length.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.script);
  final List<_Outcome> script;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final i = calls++;
    final outcome = script[i < script.length ? i : script.length - 1];
    final errType = outcome.error;
    if (errType != null) {
      throw DioException(requestOptions: options, type: errType);
    }
    return ResponseBody.fromString(
      '{"ok":true}',
      outcome.status!,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ApiClient withScript(List<_Outcome> script, _ScriptedAdapter Function(_ScriptedAdapter) capture) {
    final client = ApiClient();
    final adapter = _ScriptedAdapter(script);
    capture(adapter);
    client.dio.httpClientAdapter = adapter;
    return client;
  }

  test('retryable connectionError → retried then succeeds', () async {
    late _ScriptedAdapter adapter;
    final client = withScript(
      [const _Outcome.connectionError(), const _Outcome.status(200)],
      (a) => adapter = a,
    );
    final resp = await client.get<dynamic>('/x');
    expect(resp.statusCode, 200);
    expect(adapter.calls, 2, reason: '1 original + 1 retry');
  });

  test('retryable 503 → retried then succeeds', () async {
    late _ScriptedAdapter adapter;
    final client = withScript(
      [const _Outcome.status(503), const _Outcome.status(200)],
      (a) => adapter = a,
    );
    final resp = await client.get<dynamic>('/x');
    expect(resp.statusCode, 200);
    expect(adapter.calls, 2);
  });

  test('retryable 429 (rate limit) → retried then succeeds', () async {
    late _ScriptedAdapter adapter;
    final client = withScript(
      [const _Outcome.status(429), const _Outcome.status(200)],
      (a) => adapter = a,
    );
    final resp = await client.get<dynamic>('/x');
    expect(resp.statusCode, 200);
    expect(adapter.calls, 2);
  });

  test('non-retryable 400 → NOT retried, error bubbles after one call',
      () async {
    late _ScriptedAdapter adapter;
    final client = withScript(
      [const _Outcome.status(400), const _Outcome.status(200)],
      (a) => adapter = a,
    );
    await expectLater(
      client.get<dynamic>('/x'),
      throwsA(isA<DioException>()),
    );
    expect(adapter.calls, 1, reason: '4xx (except 408/429) is not retryable');
  });

  test('non-retryable 404 → NOT retried', () async {
    late _ScriptedAdapter adapter;
    final client = withScript(
      [const _Outcome.status(404)],
      (a) => adapter = a,
    );
    await expectLater(
      client.get<dynamic>('/x'),
      throwsA(isA<DioException>()),
    );
    expect(adapter.calls, 1);
  });

  test('persistent retryable failure → original + 3 retries then gives up',
      () async {
    late _ScriptedAdapter adapter;
    final client = withScript(
      [const _Outcome.status(503)],
      (a) => adapter = a,
    );
    await expectLater(
      client.get<dynamic>('/x'),
      throwsA(isA<DioException>()),
    );
    expect(adapter.calls, 4, reason: '1 original + 3 retries (max)');
  }, timeout: const Timeout(Duration(seconds: 15)));
}
