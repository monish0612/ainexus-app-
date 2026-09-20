import 'package:dio/dio.dart';

/// Shared expense/budget cloud-write retry contract (same shape as salary).
///
/// Attempt 1 is immediate. Attempts 2–3 wait [delayForAttempt]. Transient
/// failures retry; permanent failures (auth / not-found / validation) do
/// not — they must not be written to the durable outbox.
class ExpenseSyncPolicy {
  const ExpenseSyncPolicy._();

  static const int maxAttempts = 3;

  /// Delay *before* retrying [attempt] (1-based, after a failed try).
  /// Attempt 1 → 400ms, attempt 2 → 800ms.
  static Duration delayForAttempt(int attempt) =>
      Duration(milliseconds: 400 * attempt);

  static bool isPermanent(Object error) {
    if (error is! DioException) return false;
    if (error.type == DioExceptionType.cancel) return true;
    if (error.type == DioExceptionType.badCertificate) return true;
    final code = error.response?.statusCode;
    if (code == null) return false;
    return code == 401 || code == 403 || code == 404 || code == 422;
  }
}
