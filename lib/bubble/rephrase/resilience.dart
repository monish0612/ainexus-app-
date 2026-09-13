import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';

/// Error taxonomy — decides retry vs surface vs fallback.
enum BubbleErrorKind { transient, permanent, offline, timeout, busy }

class BubbleError implements Exception {
  BubbleError(this.kind, this.message);

  final BubbleErrorKind kind;
  final String message;

  bool get retryable =>
      kind == BubbleErrorKind.transient || kind == BubbleErrorKind.timeout;

  /// Short enough for the panel's status line.
  String get display => switch (kind) {
        BubbleErrorKind.offline => 'No network',
        BubbleErrorKind.busy => 'Service busy — try shortly',
        BubbleErrorKind.timeout => 'Timed out — tap to retry',
        _ => message,
      };

  @override
  String toString() => 'BubbleError($kind): $message';
}

/// Maps a Dio failure onto the taxonomy. Auth and validation errors are
/// permanent; connectivity and 5xx/429 are worth another go.
BubbleError classify(Object error) {
  if (error is BubbleError) return error;
  if (error is TimeoutException) {
    return BubbleError(BubbleErrorKind.timeout, 'Timed out');
  }
  if (error is DioException) {
    final status = error.response?.statusCode;
    if (status != null) {
      if (status == 422 && _isRefusalEnvelope(error.response?.data)) {
        return BubbleError(
          BubbleErrorKind.permanent,
          'Blocked — try another tone',
        );
      }
      if (status == 429 || status >= 500) {
        return BubbleError(BubbleErrorKind.transient, 'Server busy ($status)');
      }
      if (status == 401 || status == 403) {
        return BubbleError(BubbleErrorKind.permanent, 'Sign in again in the app');
      }
      return BubbleError(BubbleErrorKind.permanent, 'Request failed ($status)');
    }
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        BubbleError(BubbleErrorKind.timeout, 'Timed out'),
      DioExceptionType.connectionError =>
        BubbleError(BubbleErrorKind.offline, 'No network'),
      DioExceptionType.cancel =>
        BubbleError(BubbleErrorKind.permanent, 'Cancelled'),
      _ => BubbleError(BubbleErrorKind.transient, 'Network hiccup'),
    };
  }
  return BubbleError(BubbleErrorKind.permanent, 'Rephrase failed');
}

bool _isRefusalEnvelope(Object? data) {
  if (data is Map) {
    final err = data['error'];
    if (err is Map) {
      final code = err['code']?.toString().toUpperCase();
      final message = err['message']?.toString().toLowerCase() ?? '';
      if (code == 'REFUSAL') return true;
      if (message.contains('blocked')) return true;
    } else if (err is String && err.toLowerCase().contains('blocked')) {
      return true;
    }
  }
  return false;
}

/// SwiftSlate-style head-only refusal check. Inspect the first 200 chars
/// only — a missed refusal is worse than a false negative on a long rewrite,
/// but pasting a safety rant into WhatsApp is worse than either.
bool isModelRefusal(String text) {
  final raw = text.trim();
  if (raw.isEmpty) return false;
  final head = raw
      .substring(0, raw.length < 200 ? raw.length : 200)
      .toLowerCase()
      .replaceAll(RegExp('[\u2018\u2019\u201A\u201B]'), "'");
  return _kRefusalPhrases.any(head.contains);
}

const _kRefusalPhrases = <String>[
  "i can't help with that",
  'i cannot help with that',
  "i can't help you with that",
  'i cannot help you with that',
  "i can't assist with that",
  'i cannot assist with that',
  "i can't comply",
  'i cannot comply',
  "i can't generate that",
  'i cannot generate that',
  "i won't be able to help with that",
  "i'm unable to help with that",
  'i am unable to help with that',
  "i'm not able to help with that",
  'i am not able to help with that',
  "can't fulfill the request",
  'cannot fulfill the request',
  "can't fulfill this request",
  'cannot fulfill this request',
  "can't fulfill your request",
  'cannot fulfill your request',
  'unable to fulfill the request',
  'unable to fulfill this request',
  'unable to fulfill your request',
  'as an ai,',
  'as an ai language model',
  'as an ai assistant',
  'violates safety guidelines',
  'violates our safety',
  'violates our content polic',
  'violates our usage polic',
  'against our safety guidelines',
  'against my safety guidelines',
  'goes against my guidelines',
];

/// Retry with exponential backoff plus jitter, transient failures only.
Future<T> retryWithBackoff<T>(
  Future<T> Function() task, {
  int maxAttempts = 2,
  Duration base = const Duration(milliseconds: 400),
  double factor = 2.0,
  Duration cap = const Duration(seconds: 6),
}) async {
  final rng = Random();
  var attempt = 0;
  while (true) {
    try {
      return await task();
    } catch (e) {
      final failure = classify(e);
      attempt++;
      if (attempt >= maxAttempts || !failure.retryable) throw failure;
      final backoffMs =
          (base.inMilliseconds * pow(factor, attempt - 1)).toInt();
      final cappedMs = min(backoffMs, cap.inMilliseconds);
      final jitterMs = rng.nextInt((cappedMs ~/ 2) + 1);
      await Future<void>.delayed(Duration(milliseconds: cappedMs + jitterMs));
    }
  }
}

/// After [threshold] consecutive failures the breaker opens for [cooldown]; the
/// first call after that is a half-open trial.
class CircuitBreaker {
  CircuitBreaker({
    this.threshold = 5,
    this.cooldown = const Duration(seconds: 45),
  });

  final int threshold;
  final Duration cooldown;

  int _failures = 0;
  DateTime? _openedAt;

  bool get isOpen {
    final openedAt = _openedAt;
    if (openedAt == null) return false;
    return DateTime.now().difference(openedAt) < cooldown;
  }

  Future<T> run<T>(Future<T> Function() task) async {
    if (isOpen) {
      throw BubbleError(BubbleErrorKind.busy, 'Service busy — try shortly');
    }
    try {
      final result = await task();
      _failures = 0;
      _openedAt = null;
      return result;
    } catch (e) {
      _failures++;
      if (_failures >= threshold) _openedAt = DateTime.now();
      rethrow;
    }
  }
}

/// Hard ceiling per call so the bubble can never freeze on a hung request.
Future<T> withTimeoutOr<T>(
  Future<T> Function() task, {
  Duration limit = const Duration(seconds: 15),
}) =>
    task().timeout(
      limit,
      onTimeout: () => throw BubbleError(BubbleErrorKind.timeout, 'Timed out'),
    );
