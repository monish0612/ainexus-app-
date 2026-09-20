import 'package:ai_nexus/core/services/expense_sync_policy.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

DioException _dio({
  required DioExceptionType type,
  int? status,
}) {
  final req = RequestOptions(path: '/api/v1/expenses');
  return DioException(
    requestOptions: req,
    type: type,
    response: status == null
        ? null
        : Response<void>(requestOptions: req, statusCode: status),
  );
}

void main() {
  group('ExpenseSyncPolicy', () {
    test('retries timeouts, 5xx, 429', () {
      expect(
        ExpenseSyncPolicy.isPermanent(
          _dio(type: DioExceptionType.connectionTimeout),
        ),
        isFalse,
      );
      expect(
        ExpenseSyncPolicy.isPermanent(
          _dio(type: DioExceptionType.badResponse, status: 500),
        ),
        isFalse,
      );
      expect(
        ExpenseSyncPolicy.isPermanent(
          _dio(type: DioExceptionType.badResponse, status: 429),
        ),
        isFalse,
      );
    });

    test('does not retry 401 / 403 / 404 / 422 / cancel', () {
      expect(
        ExpenseSyncPolicy.isPermanent(
          _dio(type: DioExceptionType.badResponse, status: 401),
        ),
        isTrue,
      );
      expect(
        ExpenseSyncPolicy.isPermanent(
          _dio(type: DioExceptionType.badResponse, status: 422),
        ),
        isTrue,
      );
      expect(
        ExpenseSyncPolicy.isPermanent(
          _dio(type: DioExceptionType.cancel),
        ),
        isTrue,
      );
    });

    test('delay is 400ms × attempt', () {
      expect(ExpenseSyncPolicy.delayForAttempt(1), const Duration(milliseconds: 400));
      expect(ExpenseSyncPolicy.delayForAttempt(2), const Duration(milliseconds: 800));
    });
  });
}
