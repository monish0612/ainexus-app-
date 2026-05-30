import 'dart:async';

import '../services/telegram_logger.dart';

/// Run an async [action] up to [attempts] times with linear back-off.
///
/// Designed for local-first UI mutations (Drift writes, in-memory cache
/// updates) where the failure mode is transient — main-thread SQLite
/// contention, an isolate that hasn't finished warming up, a brief
/// pause-during-resume hiccup. The defaults (3 attempts, 80 ms step)
/// keep the worst-case latency under ~250 ms so the user doesn't notice
/// a retry even when one happens.
///
/// Semantics:
///   • First call to [action] fires immediately (no warm-up delay).
///   • On exception, sleeps `baseDelayMs * (attemptIndex + 1)` and tries
///     again — so a 3-attempt run with the default 80 ms base waits
///     80 ms before attempt 2 and 160 ms before attempt 3. Pure linear,
///     not exponential — exponential makes sense for network calls
///     where the backend might genuinely be overwhelmed; for local
///     mutations it's just dead time.
///   • Each FAILED attempt emits a `TLog.w` warning so a flaky run
///     leaves an auditable Telegram trail without spamming on success.
///   • If every attempt fails, rethrows the LAST exception with its
///     ORIGINAL stack trace via [Error.throwWithStackTrace] so callers
///     see a useful error chain instead of a synthetic wrapper.
///
/// Calling code is expected to wrap the result in its own try/catch and
/// surface user-visible feedback (snackbar / toast). This helper does
/// NOT log success — that's the caller's responsibility because only
/// the caller knows the right info-level message.
///
/// Use [tag] / [operation] to namespace the warning logs:
/// `[News] Retry swipe-delete[Movies] attempt 2/3 after error: ...`
///
/// Throws the last error if every attempt fails.
Future<T> runWithRetry<T>({
  required String tag,
  required String operation,
  required Future<T> Function() action,
  int attempts = 3,
  int baseDelayMs = 80,
}) async {
  assert(attempts >= 1, 'attempts must be >= 1');
  assert(baseDelayMs >= 0, 'baseDelayMs must be >= 0');

  Object? lastError;
  StackTrace? lastStack;

  for (var i = 0; i < attempts; i++) {
    try {
      return await action();
    } catch (e, st) {
      lastError = e;
      lastStack = st;
      if (i + 1 < attempts) {
        TLog.w(
          tag,
          'Retry $operation attempt ${i + 1}/$attempts after error: $e',
          error: e,
        );
        if (baseDelayMs > 0) {
          await Future<void>.delayed(Duration(milliseconds: baseDelayMs * (i + 1)));
        }
      }
    }
  }

  Error.throwWithStackTrace(
    lastError ?? StateError('$operation failed without error'),
    lastStack ?? StackTrace.current,
  );
}
