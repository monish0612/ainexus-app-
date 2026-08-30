import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/core/network/ai_error.dart';

DioException _buildDio({
  required int? status,
  required dynamic body,
  DioExceptionType type = DioExceptionType.badResponse,
}) {
  final reqOpts = RequestOptions(path: '/api/v1/ai/rephrase');
  return DioException(
    requestOptions: reqOpts,
    response: status == null
        ? null
        : Response(
            requestOptions: reqOpts,
            statusCode: status,
            data: body,
          ),
    type: type,
    message: body is String ? body : null,
  );
}

void main() {
  group('AiError.fromDio — backend envelope parsing', () {
    test('extracts message, code, model, provider from the rich object envelope', () {
      final dio = _buildDio(
        status: 404,
        body: {
          'error': {
            'message': 'Gemini model "gemini-foo" not found',
            'code': 'MODEL_NOT_FOUND',
            'provider': 'gemini',
            'model': 'gemini-foo',
          },
        },
      );

      final err = AiError.fromDio(dio);
      expect(err.code, 'MODEL_NOT_FOUND');
      expect(err.model, 'gemini-foo');
      expect(err.provider, 'gemini');
      expect(err.status, 404);
      expect(err.userMessage, contains('gemini-foo'));
      expect(err.isSettingsActionable, isTrue);
      expect(err.isRetryable, isFalse);
    });

    test('falls back gracefully when the body is a plain string envelope', () {
      // Legacy backend shape: `{error: "...message..."}` (no nested
      // object). We extract the string but the code stays UNKNOWN
      // because the body didn't carry one — clients should still
      // get a usable userMessage.
      final dio = _buildDio(
        status: 500,
        body: {'error': 'Internal server error'},
      );

      final err = AiError.fromDio(dio);
      expect(err.userMessage, 'Internal server error');
      expect(err.code, 'UNKNOWN');
      expect(err.status, 500);
    });

    test('HTTP 429 with a string limiter body maps to RATE_LIMIT', () {
      final dio = _buildDio(
        status: 429,
        body: {'error': 'Too many requests, please try again later'},
      );
      final err = AiError.fromDio(dio);
      expect(err.code, 'RATE_LIMIT');
      expect(err.status, 429);
      expect(err.toastMessage, contains('rate limit'));
    });

    test('HTTP 429 with no envelope still maps to RATE_LIMIT', () {
      final dio = _buildDio(status: 429, body: null);
      final err = AiError.fromDio(dio);
      expect(err.code, 'RATE_LIMIT');
      expect(err.toastMessage, contains('rate limit'));
    });

    test('RATE_LIMIT is retryable but NOT settings-actionable', () {
      final dio = _buildDio(
        status: 429,
        body: {'error': {'message': 'Rate limited', 'code': 'RATE_LIMIT'}},
      );

      final err = AiError.fromDio(dio);
      expect(err.code, 'RATE_LIMIT');
      expect(err.isRetryable, isTrue);
      expect(err.isSettingsActionable, isFalse);
      expect(err.toastMessage, contains('rate limit'));
    });

    test('BLOCKED has its own toast copy', () {
      final dio = _buildDio(
        status: 400,
        body: {'error': {'message': 'Blocked', 'code': 'BLOCKED'}},
      );
      final err = AiError.fromDio(dio);
      expect(err.code, 'BLOCKED');
      expect(err.isRetryable, isFalse);
      expect(err.isSettingsActionable, isFalse);
      expect(err.toastMessage.toLowerCase(), contains('safety'));
    });

    test('TIMEOUT envelope maps to retryable + timeout toast', () {
      final dio = _buildDio(
        status: 504,
        body: {'error': {'message': 'Timed out', 'code': 'TIMEOUT'}},
      );
      final err = AiError.fromDio(dio);
      expect(err.code, 'TIMEOUT');
      expect(err.isRetryable, isTrue);
      expect(err.toastMessage.toLowerCase(), contains('too long'));
    });

    test('MODEL_NOT_FOUND toast embeds the actual model id from the envelope', () {
      final dio = _buildDio(
        status: 404,
        body: {
          'error': {
            'message': 'not found',
            'code': 'MODEL_NOT_FOUND',
            'model': 'gemini-3.1-flash-lite',
          },
        },
      );
      final err = AiError.fromDio(dio);
      expect(err.toastMessage, contains('"gemini-3.1-flash-lite"'));
      expect(err.toastMessage.toLowerCase(), contains('open settings'));
    });
  });

  group('AiError.fromDio — DioException type fallback', () {
    test('connectionTimeout → TIMEOUT code', () {
      final dio = _buildDio(
        status: null,
        body: null,
        type: DioExceptionType.connectionTimeout,
      );
      final err = AiError.fromDio(dio);
      expect(err.code, 'TIMEOUT');
      expect(err.isRetryable, isTrue);
    });

    test('connectionError → NETWORK code', () {
      final dio = _buildDio(
        status: null,
        body: null,
        type: DioExceptionType.connectionError,
      );
      final err = AiError.fromDio(dio);
      expect(err.code, 'NETWORK');
      expect(err.isRetryable, isTrue);
    });

    test('cancel → CANCELLED code (not retryable, not actionable)', () {
      final dio = _buildDio(
        status: null,
        body: null,
        type: DioExceptionType.cancel,
      );
      final err = AiError.fromDio(dio);
      expect(err.code, 'CANCELLED');
      expect(err.isRetryable, isFalse);
      expect(err.isSettingsActionable, isFalse);
    });

    test('badResponse with no body uses status code in message', () {
      final dio = _buildDio(status: 503, body: null);
      final err = AiError.fromDio(dio);
      expect(err.status, 503);
      expect(err.code, 'SERVER');
      expect(err.isRetryable, isTrue);
    });
  });

  group('AiError.fromAny', () {
    test('routes a DioException to fromDio()', () {
      final dio = _buildDio(
        status: 404,
        body: {'error': {'message': 'not found', 'code': 'MODEL_NOT_FOUND'}},
      );
      final err = AiError.fromAny(dio);
      expect(err.code, 'MODEL_NOT_FOUND');
    });

    test('uses toString() of arbitrary throwables when no fallback given', () {
      final err = AiError.fromAny(StateError('bad state'));
      expect(err.code, 'UNKNOWN');
      expect(err.userMessage, contains('bad state'));
    });

    test('honours fallbackMessage when provided for non-Dio errors', () {
      final err = AiError.fromAny(
        StateError('internal'),
        fallbackMessage: 'Could not parse response',
      );
      expect(err.code, 'UNKNOWN');
      expect(err.userMessage, 'Could not parse response');
    });
  });

  group('AiError settings-actionable behaviour', () {
    test('CONFIG, INVALID_MODEL, MODEL_NOT_FOUND are settings-actionable', () {
      for (final code in ['CONFIG', 'INVALID_MODEL', 'MODEL_NOT_FOUND']) {
        final dio = _buildDio(
          status: 400,
          body: {'error': {'message': '$code msg', 'code': code}},
        );
        expect(AiError.fromDio(dio).isSettingsActionable, isTrue,
            reason: 'expected $code to be settings-actionable');
      }
    });

    test('RATE_LIMIT, TIMEOUT, NETWORK are NOT settings-actionable', () {
      for (final code in ['RATE_LIMIT', 'TIMEOUT', 'NETWORK']) {
        final dio = _buildDio(
          status: 429,
          body: {'error': {'message': '$code msg', 'code': code}},
        );
        expect(AiError.fromDio(dio).isSettingsActionable, isFalse,
            reason: 'expected $code to NOT be settings-actionable');
      }
    });
  });
}
