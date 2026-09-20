import 'dart:async';

import 'package:ai_nexus/bubble/rephrase/resilience.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// The bubble is a floating UI over someone else's app: it must never hang and
/// never hammer a failing backend. These tests pin down both guarantees.
void main() {
  DioException dio(int status) => DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: status,
        ),
      );

  group('classify', () {
    test('5xx and 429 are retryable', () {
      expect(classify(dio(500)).kind, BubbleErrorKind.transient);
      expect(classify(dio(503)).kind, BubbleErrorKind.transient);
      expect(classify(dio(429)).kind, BubbleErrorKind.transient);
      expect(classify(dio(500)).retryable, isTrue);
    });

    test('auth and validation failures are permanent', () {
      expect(classify(dio(401)).kind, BubbleErrorKind.permanent);
      expect(classify(dio(403)).kind, BubbleErrorKind.permanent);
      expect(classify(dio(400)).kind, BubbleErrorKind.permanent);
      expect(classify(dio(404)).retryable, isFalse);
    });

    test('a 422 refusal envelope is a short permanent message', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 422,
          data: {
            'error': {'code': 'REFUSAL', 'message': 'Blocked — try another tone'},
          },
        ),
      );
      final classified = classify(error);
      expect(classified.kind, BubbleErrorKind.permanent);
      expect(classified.display, 'Blocked — try another tone');
      expect(classified.display.length, lessThan(48));
    });

    test('connectivity maps to offline and timeouts to timeout', () {
      expect(
        classify(
          DioException(
            requestOptions: RequestOptions(path: '/x'),
            type: DioExceptionType.connectionError,
          ),
        ).kind,
        BubbleErrorKind.offline,
      );
      expect(
        classify(
          DioException(
            requestOptions: RequestOptions(path: '/x'),
            type: DioExceptionType.receiveTimeout,
          ),
        ).kind,
        BubbleErrorKind.timeout,
      );
      expect(classify(TimeoutException('x')).kind, BubbleErrorKind.timeout);
    });

    test('messages stay short enough for the panel status line', () {
      for (final error in [dio(500), dio(401), TimeoutException('x')]) {
        expect(classify(error).display.length, lessThan(48));
      }
    });

    test('an already-classified error passes straight through', () {
      final original = BubbleError(BubbleErrorKind.busy, 'busy');
      expect(classify(original), same(original));
    });
  });

  group('retryWithBackoff', () {
    test('gives up after maxAttempts on transient failures', () async {
      var calls = 0;
      await expectLater(
        retryWithBackoff(
          () {
            calls++;
            throw dio(503);
          },
          maxAttempts: 3,
          base: const Duration(milliseconds: 1),
        ),
        throwsA(isA<BubbleError>()),
      );
      expect(calls, 3);
    });

    test('does not retry a permanent failure', () async {
      var calls = 0;
      await expectLater(
        retryWithBackoff(
          () {
            calls++;
            throw dio(401);
          },
          maxAttempts: 4,
          base: const Duration(milliseconds: 1),
        ),
        throwsA(isA<BubbleError>()),
      );
      expect(calls, 1);
    });

    test('returns as soon as an attempt succeeds', () async {
      var calls = 0;
      final result = await retryWithBackoff(
        () async {
          calls++;
          if (calls < 2) throw dio(500);
          return 'ok';
        },
        base: const Duration(milliseconds: 1),
      );
      expect(result, 'ok');
      expect(calls, 2);
    });

    test('defaults to two attempts', () async {
      var calls = 0;
      await expectLater(
        retryWithBackoff(
          () {
            calls++;
            throw dio(503);
          },
          base: const Duration(milliseconds: 1),
        ),
        throwsA(isA<BubbleError>()),
      );
      expect(calls, 2);
    });
  });

  group('CircuitBreaker', () {
    test('opens after the threshold and then fails fast', () async {
      final breaker = CircuitBreaker(
        threshold: 2,
        cooldown: const Duration(seconds: 30),
      );
      var calls = 0;

      Future<void> boom() => breaker.run(() async {
            calls++;
            throw BubbleError(BubbleErrorKind.transient, 'boom');
          });

      await expectLater(boom(), throwsA(isA<BubbleError>()));
      await expectLater(boom(), throwsA(isA<BubbleError>()));
      expect(breaker.isOpen, isTrue);

      // Third call must not reach the task at all.
      await expectLater(
        boom(),
        throwsA(
          isA<BubbleError>()
              .having((e) => e.kind, 'kind', BubbleErrorKind.busy),
        ),
      );
      expect(calls, 2);
    });

    test('a success resets the failure count', () async {
      final breaker = CircuitBreaker(threshold: 2);
      await expectLater(
        breaker.run(() async => throw BubbleError(BubbleErrorKind.transient, 'x')),
        throwsA(isA<BubbleError>()),
      );
      expect(await breaker.run(() async => 'ok'), 'ok');
      expect(breaker.isOpen, isFalse);
    });

    test('reopens for trials once the cooldown has passed', () async {
      final breaker = CircuitBreaker(
        threshold: 1,
        cooldown: const Duration(milliseconds: 20),
      );
      await expectLater(
        breaker.run(() async => throw BubbleError(BubbleErrorKind.transient, 'x')),
        throwsA(isA<BubbleError>()),
      );
      expect(breaker.isOpen, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(breaker.isOpen, isFalse);
      expect(await breaker.run(() async => 'ok'), 'ok');
    });
  });

  group('withTimeoutOr', () {
    test('a hung request cannot freeze the panel', () async {
      await expectLater(
        withTimeoutOr(
          () => Completer<String>().future,
          limit: const Duration(milliseconds: 20),
        ),
        throwsA(
          isA<BubbleError>()
              .having((e) => e.kind, 'kind', BubbleErrorKind.timeout),
        ),
      );
    });

    test('a fast request passes through untouched', () async {
      expect(
        await withTimeoutOr(() async => 'quick', limit: const Duration(seconds: 5)),
        'quick',
      );
    });
  });

  group('isModelRefusal', () {
    test('matches qualified refusal phrases in the first 200 chars', () {
      expect(isModelRefusal("I can't help with that."), isTrue);
      expect(isModelRefusal('As an AI, I cannot assist with that.'), isTrue);
    });

    test('does not flag a normal rewrite', () {
      expect(isModelRefusal('hey, fancy grabbing lunch from Starbucks?'), isFalse);
      expect(isModelRefusal(''), isFalse);
    });

    test('ignores a refusal phrase after the 200-char head', () {
      final padded = '${'x' * 200}I cannot help with that.';
      expect(isModelRefusal(padded), isFalse);
    });

    test('normalises curly apostrophes before matching', () {
      expect(isModelRefusal('I can\u2019t help with that.'), isTrue);
    });
  });
}
