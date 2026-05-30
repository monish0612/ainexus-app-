// Unit tests for [runWithRetry] — the local-first retry helper used by
// the news screen's swipe-delete + Clear-All flows. These tests are
// production-critical because a regression here would mean a transient
// SQLite hiccup quietly surfaces to the user as "could not remove
// article" instead of being silently absorbed by the retry loop.
//
// COVERAGE
//
//   • Success on first attempt → action runs once, no retry warnings.
//   • Success on second attempt → action runs twice, exactly one
//     retry warning.
//   • Total failure → throws the LAST exception after exactly [attempts]
//     calls, with the original stack trace preserved.
//   • Linear back-off → second retry waits longer than first.
//   • Custom attempts param → 1 attempt means no retries.
//   • The TLog warning's tag/operation are wired correctly so the
//     Telegram trail is unambiguous.
//
// We use [TLog.debugOnLog] to assert on the production logger pipeline
// without actually hitting Telegram. The observer is reset between
// tests to avoid cross-test pollution.

import 'package:ai_nexus/core/services/telegram_logger.dart';
import 'package:ai_nexus/core/utils/retry.dart';
import 'package:flutter_test/flutter_test.dart';

class _Observation {
  _Observation(this.level, this.tag, this.message, this.error);
  final String level;
  final String tag;
  final String message;
  final Object? error;
}

void main() {
  final observed = <_Observation>[];

  setUp(() {
    observed.clear();
    TLog.debugOnLog = (level, tag, message, {Object? error}) {
      observed.add(_Observation(level, tag, message, error));
    };
  });

  tearDown(() {
    TLog.debugOnLog = null;
  });

  group('runWithRetry — happy path', () {
    test('first attempt succeeds: action runs once, no retry warnings',
        () async {
      var calls = 0;
      final result = await runWithRetry<String>(
        tag: 'Test',
        operation: 'op',
        attempts: 3,
        action: () async {
          calls++;
          return 'ok';
        },
      );

      expect(result, 'ok');
      expect(calls, 1);
      // No retry warning should have fired.
      final retries = observed.where((o) => o.level == 'warning');
      expect(retries, isEmpty);
    });

    test('second attempt succeeds: action runs twice, exactly 1 retry warning',
        () async {
      var calls = 0;
      final result = await runWithRetry<int>(
        tag: 'Test',
        operation: 'flaky',
        attempts: 3,
        baseDelayMs: 1, // keep test fast
        action: () async {
          calls++;
          if (calls == 1) throw StateError('first attempt fails');
          return 42;
        },
      );

      expect(result, 42);
      expect(calls, 2);
      final retries =
          observed.where((o) => o.level == 'warning').toList();
      expect(retries.length, 1);
      expect(retries.single.tag, 'Test');
      expect(retries.single.message, contains('Retry flaky attempt 1/3'));
      expect(retries.single.error, isA<StateError>());
    });
  });

  group('runWithRetry — total failure', () {
    test('every attempt fails: throws LAST error after exactly N calls',
        () async {
      var calls = 0;
      Object? caught;
      try {
        await runWithRetry<void>(
          tag: 'Test',
          operation: 'doomed',
          attempts: 3,
          baseDelayMs: 1,
          action: () async {
            calls++;
            throw StateError('attempt-$calls fails');
          },
        );
        fail('should have thrown');
      } catch (e) {
        caught = e;
      }

      expect(calls, 3);
      expect(caught, isA<StateError>());
      // The thrown error MUST be the LAST one (attempt-3), not the first.
      expect((caught as StateError).message, 'attempt-3 fails');
      // 2 retry warnings (between attempts 1→2 and 2→3). The final
      // failure is NOT logged here — it's the caller's responsibility
      // to log the user-visible failure.
      final retries =
          observed.where((o) => o.level == 'warning').toList();
      expect(retries.length, 2);
      expect(retries[0].message, contains('attempt 1/3'));
      expect(retries[1].message, contains('attempt 2/3'));
    });

    test('1-attempt mode: no retries, throws on first failure',
        () async {
      var calls = 0;
      Object? caught;
      try {
        await runWithRetry<void>(
          tag: 'Test',
          operation: 'oneshot',
          attempts: 1,
          baseDelayMs: 1,
          action: () async {
            calls++;
            throw StateError('once');
          },
        );
      } catch (e) {
        caught = e;
      }

      expect(calls, 1);
      expect(caught, isA<StateError>());
      // No warnings because we never tried a 2nd time.
      final retries =
          observed.where((o) => o.level == 'warning').toList();
      expect(retries, isEmpty);
    });
  });

  group('runWithRetry — back-off timing', () {
    test('linear back-off: second retry waits longer than first',
        () async {
      final timestamps = <DateTime>[];
      var calls = 0;
      try {
        await runWithRetry<void>(
          tag: 'Test',
          operation: 'timed',
          attempts: 3,
          baseDelayMs: 40, // 40 ms → 80 ms steps
          action: () async {
            timestamps.add(DateTime.now());
            calls++;
            throw StateError('keep failing');
          },
        );
      } catch (_) {/* expected */}

      expect(calls, 3);
      expect(timestamps.length, 3);
      // Between call 1 and 2: ~40 ms wait.
      final gap1 = timestamps[1].difference(timestamps[0]);
      // Between call 2 and 3: ~80 ms wait.
      final gap2 = timestamps[2].difference(timestamps[1]);
      expect(gap1.inMilliseconds, greaterThanOrEqualTo(30),
          reason: 'first retry should wait at least baseDelayMs');
      expect(gap2.inMilliseconds, greaterThan(gap1.inMilliseconds),
          reason: 'second retry must wait STRICTLY longer than first '
              '(linear back-off)');
      // Sanity bound — second retry should be roughly 2× the first
      // (with some slack for test scheduling noise).
      expect(gap2.inMilliseconds, lessThan(gap1.inMilliseconds * 4));
    });

    test('baseDelayMs=0 skips waits entirely', () async {
      final timestamps = <DateTime>[];
      var calls = 0;
      try {
        await runWithRetry<void>(
          tag: 'Test',
          operation: 'instant',
          attempts: 3,
          baseDelayMs: 0,
          action: () async {
            timestamps.add(DateTime.now());
            calls++;
            throw StateError('fail');
          },
        );
      } catch (_) {/* expected */}

      expect(calls, 3);
      // All three calls should fire within a tight window when
      // baseDelayMs is 0 (just async scheduler overhead, no Future.delayed).
      final span = timestamps.last.difference(timestamps.first);
      expect(span.inMilliseconds, lessThan(100),
          reason: 'baseDelayMs=0 must not introduce wall-clock delay');
    });
  });

  group('runWithRetry — type safety + edge cases', () {
    test('void return type works', () async {
      var ran = false;
      await runWithRetry<void>(
        tag: 'Test',
        operation: 'void-op',
        baseDelayMs: 0,
        action: () async {
          ran = true;
        },
      );
      expect(ran, isTrue);
    });

    test('non-async action that synchronously throws is caught',
        () async {
      var calls = 0;
      Object? caught;
      try {
        await runWithRetry<int>(
          tag: 'Test',
          operation: 'sync-throw',
          attempts: 2,
          baseDelayMs: 1,
          // Use an async closure that throws BEFORE any await — Dart
          // still catches it because the async function captures the
          // throw into the returned Future.
          action: () async {
            calls++;
            throw StateError('sync inside async');
          },
        );
      } catch (e) {
        caught = e;
      }

      expect(calls, 2);
      expect(caught, isA<StateError>());
    });

    test('preserves a custom Exception subclass in the rethrow',
        () async {
      Object? caught;
      try {
        await runWithRetry<void>(
          tag: 'Test',
          operation: 'custom-err',
          attempts: 2,
          baseDelayMs: 1,
          action: () async {
            throw const FormatException('bad input');
          },
        );
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<FormatException>());
    });

    test('returns the action result on success without wrapping',
        () async {
      // The success path must NOT wrap the result in a Future<Future<T>>
      // or unwrap it incorrectly.
      final list = [1, 2, 3];
      final result = await runWithRetry<List<int>>(
        tag: 'Test',
        operation: 'identity',
        baseDelayMs: 0,
        action: () async => list,
      );
      expect(result, same(list));
    });
  });

  group('runWithRetry — log content', () {
    test('warning includes tag, operation and attempt index', () async {
      try {
        await runWithRetry<void>(
          tag: 'NewsScreen',
          operation: 'swipe-delete[Movies]',
          attempts: 3,
          baseDelayMs: 1,
          action: () async => throw StateError('boom'),
        );
      } catch (_) {}

      final retries =
          observed.where((o) => o.level == 'warning').toList();
      expect(retries.length, 2);
      expect(retries[0].tag, 'NewsScreen');
      expect(retries[0].message,
          contains('Retry swipe-delete[Movies] attempt 1/3'));
      expect(retries[1].message,
          contains('Retry swipe-delete[Movies] attempt 2/3'));
    });
  });
}
