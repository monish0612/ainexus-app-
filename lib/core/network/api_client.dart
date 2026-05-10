import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import '../services/telegram_logger.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

class ApiClient {
  ApiClient() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    _dio.interceptors.addAll([
      LoggingInterceptor(),
      _RetryInterceptor(_dio),
    ]);
  }

  late final Dio _dio;

  Dio get dio => _dio;

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) =>
      _dio.get<T>(path, queryParameters: queryParameters);

  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Options? options,
    CancelToken? cancelToken,
  }) =>
      _dio.post<T>(path,
          data: data, options: options, cancelToken: cancelToken);

  Future<Response<T>> put<T>(
    String path, {
    Object? data,
  }) =>
      _dio.put<T>(path, data: data);

  Future<Response<T>> delete<T>(String path) => _dio.delete<T>(path);
}

/// HTTP request/response logger that funnels everything through [TLog].
///
/// Severity policy (kept in sync with `test/core/network/api_client_logging_test.dart`):
///   • cancel       → no log (control-flow signal, not an error)
///   • 4xx          → TLog.w with status + URL + elapsed (NO `error:` payload)
///   • 5xx          → TLog.e with status + URL + elapsed + full DioException
///   • network err  → TLog.e with type + URL + elapsed + full DioException
///
/// Made non-private so unit tests can compose a Dio that has only this
/// interceptor (and skip the retry loop) when asserting on log shape.
class LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra['_requestStartMs'] = DateTime.now().millisecondsSinceEpoch;
    TLog.d('HTTP', '→ ${options.method} ${options.uri}');
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final startMs =
        response.requestOptions.extra['_requestStartMs'] as int? ?? 0;
    final elapsed = DateTime.now().millisecondsSinceEpoch - startMs;
    TLog.d('HTTP',
        '← ${response.statusCode} ${response.requestOptions.uri} (${elapsed}ms)');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final startMs =
        err.requestOptions.extra['_requestStartMs'] as int? ?? 0;
    final elapsed = DateTime.now().millisecondsSinceEpoch - startMs;
    final status = err.response?.statusCode;

    // Cancellation is a normal control-flow signal, not an error.
    if (err.type == DioExceptionType.cancel) {
      handler.next(err);
      return;
    }

    // 4xx are client errors and almost always either expected (404 "not
    // found", 400 from validation) or actionable in the calling code.
    // Logging them as ERROR with the full DioException body floods
    // Telegram with stack-trace-shaped noise (e.g. when the backend has
    // not yet deployed an endpoint). Downgrade to WARN and skip the
    // verbose `error:` payload — the URL + status code + message are
    // already enough to triage.
    if (status != null && status >= 400 && status < 500) {
      TLog.w(
        'HTTP',
        '✖ ${err.requestOptions.method} ${err.requestOptions.uri} '
            '[$status] (${elapsed}ms)',
      );
      handler.next(err);
      return;
    }

    TLog.e(
      'HTTP',
      '✖ ${err.requestOptions.method} ${err.requestOptions.uri} '
          '[${status ?? err.type.name}] (${elapsed}ms): ${err.message}',
      error: err,
    );
    handler.next(err);
  }
}

class _RetryInterceptor extends Interceptor {
  _RetryInterceptor(this._dio);
  final Dio _dio;
  static const _maxRetries = 3;
  static final _random = Random();

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.requestOptions.cancelToken?.isCancelled == true) {
      handler.next(err);
      return;
    }

    if (!_shouldRetry(err)) {
      handler.next(err);
      return;
    }

    DioException lastError = err;

    for (int attempt = 1; attempt <= _maxRetries; attempt++) {
      final delay = _retryDelay(attempt);
      TLog.w(
        'HTTP',
        'Retry $attempt/$_maxRetries for '
            '${err.requestOptions.method} ${err.requestOptions.uri} '
            'after ${delay.inMilliseconds}ms '
            '(reason: ${_retryReason(lastError)})',
      );

      await Future<void>.delayed(delay);

      try {
        final options = Options(
          method: err.requestOptions.method,
          headers: err.requestOptions.headers,
          responseType: err.requestOptions.responseType,
          contentType: err.requestOptions.contentType,
          receiveTimeout: err.requestOptions.receiveTimeout,
          sendTimeout: err.requestOptions.sendTimeout,
        );
        final response = await _dio.request(
          err.requestOptions.path,
          data: err.requestOptions.data,
          queryParameters: err.requestOptions.queryParameters,
          cancelToken: err.requestOptions.cancelToken,
          options: options,
        );
        TLog.i('HTTP', 'Retry $attempt succeeded: ${err.requestOptions.uri}');
        handler.resolve(response);
        return;
      } on DioException catch (retryErr) {
        lastError = retryErr;
        if (!_shouldRetry(retryErr)) {
          TLog.e(
            'HTTP',
            'Retry $attempt/$_maxRetries non-retryable for '
                '${err.requestOptions.uri}: ${retryErr.message}',
          );
          handler.next(retryErr);
          return;
        }
        if (attempt == _maxRetries) {
          TLog.e(
            'HTTP',
            'Retry $_maxRetries/$_maxRetries exhausted for '
                '${err.requestOptions.uri}: ${retryErr.message}',
          );
          handler.next(retryErr);
          return;
        }
      }
    }

    handler.next(lastError);
  }

  static Duration _retryDelay(int attempt) {
    final baseMs = 500 * pow(2, attempt - 1).toInt();
    final cappedMs = min(baseMs, 8000);
    final jitterMs =
        _random.nextInt((cappedMs * 0.25).toInt().clamp(1, 2000));
    return Duration(milliseconds: cappedMs + jitterMs);
  }

  String _retryReason(DioException err) {
    if (err.response?.statusCode != null) {
      return 'HTTP ${err.response!.statusCode}';
    }
    return err.type.name;
  }

  bool _shouldRetry(DioException err) {
    if (err.type == DioExceptionType.cancel) return false;

    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.unknown) {
      return true;
    }

    final status = err.response?.statusCode;
    if (status != null) {
      return status == 408 ||
          status == 429 ||
          status == 502 ||
          status == 503 ||
          status == 504;
    }

    return false;
  }
}
