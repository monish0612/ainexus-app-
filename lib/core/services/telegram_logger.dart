import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Production-grade, non-blocking Telegram logger with exponential backoff.
///
/// All log calls are fire-and-forget. Messages are batched and sent every
/// [_batchInterval] to avoid spamming the Telegram API. Errors / fatals are
/// flushed immediately. The entire send path is wrapped in try-catch so a
/// Telegram outage can never crash the app.
///
/// Retry strategy: exponential backoff with jitter (base 2s, max 30s).
/// Queue is capped at [_maxQueueSize] — oldest non-critical entries are
/// dropped when the cap is reached.
///
/// Usage:
/// ```dart
/// TLog.d('ExpenseRepo', 'Synced 5 expenses');
/// TLog.e('ApiClient', 'Request failed', error: e, st: st);
/// ```
class TLog {
  TLog._();

  static const _botToken = '5837094484:AAHLHOPIWIW7vuktHFB1zSYeJrUS8I8PFQE';
  static const _chatId = '671766797';
  static const _apiUrl =
      'https://api.telegram.org/bot$_botToken/sendMessage';

  static const _batchInterval = Duration(seconds: 3);
  static const _maxBatchSize = 8;
  static const _maxMessageLength = 4000;
  static const _maxSendAttempts = 4;
  static const _maxQueueSize = 200;
  static const _baseRetryDelay = Duration(seconds: 2);
  static const _maxRetryDelay = Duration(seconds: 30);

  static Dio? _dio;
  static final _queue = Queue<_LogEntry>();
  static Timer? _batchTimer;
  static bool _flushing = false;
  static bool _initialized = false;
  static int _consecutiveFailures = 0;
  static final _random = Random();

  // ── Public API ──────────────────────────────────────────────────────────

  static void init() {
    if (_initialized) return;
    _initialized = true;
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 10),
      ),
    );
    i('App', 'Nexus AI started');
  }

  /// Debug — routine operations, data flow.
  static void d(String tag, String message) =>
      _enqueue('🔵', tag, message, level: _LogLevel.debug);

  /// Info — notable events (sync complete, screen opened, etc.).
  static void i(String tag, String message) =>
      _enqueue('🟢', tag, message, level: _LogLevel.info);

  /// Warning — recoverable issues (sync failed, fallback used, etc.).
  static void w(
    String tag,
    String message, {
    Object? error,
    StackTrace? st,
  }) =>
      _enqueue('🟡', tag, message,
          error: error, st: st, level: _LogLevel.warning);

  /// Error — critical failures. Flushed immediately.
  static void e(
    String tag,
    String message, {
    Object? error,
    StackTrace? st,
  }) =>
      _enqueue('🔴', tag, message,
          error: error, st: st, immediate: true, level: _LogLevel.error);

  /// Fatal — uncaught/framework errors. Flushed immediately.
  static void fatal(
    String tag,
    String message, {
    Object? error,
    StackTrace? st,
  }) =>
      _enqueue('💀', tag, message,
          error: error, st: st, immediate: true, level: _LogLevel.fatal);

  /// Gracefully drain remaining logs (call from app lifecycle if needed).
  static Future<void> drain() async {
    _batchTimer?.cancel();
    if (_queue.isNotEmpty) {
      await _flush();
    }
  }

  // ── Internals ───────────────────────────────────────────────────────────

  static void _enqueue(
    String emoji,
    String tag,
    String message, {
    Object? error,
    StackTrace? st,
    bool immediate = false,
    _LogLevel level = _LogLevel.debug,
  }) {
    if (kDebugMode) {
      debugPrint('[$emoji $tag] $message'
          '${error != null ? '\n  ⤷ $error' : ''}');
    }

    if (_queue.length >= _maxQueueSize) {
      _evictLowestPriority();
    }

    _queue.add(
      _LogEntry(
        emoji: emoji,
        tag: tag,
        message: message,
        error: error?.toString(),
        stackTrace: _trimStack(st),
        timestamp: DateTime.now(),
        level: level,
      ),
    );

    if (immediate || _queue.length >= _maxBatchSize) {
      unawaited(_flush());
    } else if (_dio != null) {
      // Only schedule a batch flush if Telegram dispatch is actually wired
      // up. In tests (and pre-`init()` startup) `_dio` is null, in which
      // case the periodic flush timer is pure overhead — and worse, it
      // trips the test framework's "pending timer" guard during widget
      // disposal. Logs still accumulate in `_queue` and drain naturally
      // once `init()` runs.
      _scheduleBatch();
    }
  }

  /// When queue is full, drop the oldest debug-level entry first, then info,
  /// then warning. Error and fatal entries are preserved as long as possible.
  static void _evictLowestPriority() {
    for (final level in _LogLevel.values) {
      for (var i = 0; i < _queue.length; i++) {
        final entries = _queue.toList();
        if (entries[i].level == level) {
          _queue.remove(entries[i]);
          return;
        }
      }
    }
    _queue.removeFirst();
  }

  static void _scheduleBatch() {
    _batchTimer?.cancel();
    final delay = _consecutiveFailures > 0
        ? _retryDelay(_consecutiveFailures)
        : _batchInterval;
    _batchTimer = Timer(delay, () => unawaited(_flush()));
  }

  static Duration _retryDelay(int attempt) {
    final baseMs = _baseRetryDelay.inMilliseconds * pow(2, attempt - 1);
    final cappedMs = min(baseMs.toInt(), _maxRetryDelay.inMilliseconds);
    final jitterMs = _random.nextInt((cappedMs * 0.3).toInt().clamp(1, 9000));
    return Duration(milliseconds: cappedMs + jitterMs);
  }

  static Future<void> _flush() async {
    if (_flushing || _queue.isEmpty || _dio == null) return;
    _flushing = true;

    final batch = <_LogEntry>[];
    try {
      while (_queue.isNotEmpty && batch.length < _maxBatchSize) {
        batch.add(_queue.removeFirst());
      }

      final text = _formatBatch(batch);
      final chunks = _splitMessage(text);
      final failedChunkEntries = <_LogEntry>[];
      var anySuccess = false;

      for (var ci = 0; ci < chunks.length; ci++) {
        final ok = await _sendChunkWithRetry(chunks[ci]);
        if (ok) {
          anySuccess = true;
        } else {
          final start = (ci * _maxBatchSize ~/ chunks.length)
              .clamp(0, batch.length);
          final end = ((ci + 1) * _maxBatchSize ~/ chunks.length)
              .clamp(start, batch.length);
          for (var i = start; i < end; i++) {
            failedChunkEntries.add(batch[i]);
          }
        }
      }

      if (anySuccess) {
        _consecutiveFailures = 0;
      }

      for (final entry in failedChunkEntries.reversed) {
        entry.sendAttempts++;
        if (entry.sendAttempts < _maxSendAttempts) {
          _queue.addFirst(entry);
        } else if (kDebugMode) {
          debugPrint('[TLog] Dropped after $_maxSendAttempts attempts: '
              '${entry.tag} — ${entry.message}');
        }
      }

      if (!anySuccess && failedChunkEntries.isNotEmpty) {
        _consecutiveFailures++;
        if (kDebugMode) {
          debugPrint('[TLog] Flush failed (consecutive: $_consecutiveFailures). '
              'Next retry in ${_retryDelay(_consecutiveFailures).inSeconds}s');
        }
      }
    } catch (ex) {
      _consecutiveFailures++;
      for (final entry in batch.reversed) {
        entry.sendAttempts++;
        if (entry.sendAttempts < _maxSendAttempts) {
          _queue.addFirst(entry);
        }
      }
      if (kDebugMode) {
        debugPrint('[TLog] Flush exception: $ex');
      }
    } finally {
      _flushing = false;
    }

    if (_queue.isNotEmpty) {
      _scheduleBatch();
    }
  }

  /// Sends a single Telegram message chunk with one inline retry.
  static Future<bool> _sendChunkWithRetry(String chunk) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await _dio!.post<Map<String, dynamic>>(
          _apiUrl,
          data: <String, dynamic>{
            'chat_id': _chatId,
            'text': chunk,
            'parse_mode': 'HTML',
            'disable_notification': true,
          },
        );

        if (response.statusCode == 200) return true;

        if (response.statusCode == 429) {
          final retryAfter = response.data?['parameters']?['retry_after'];
          final waitSec = (retryAfter is int) ? retryAfter : 5;
          await Future<void>.delayed(Duration(seconds: waitSec));
          continue;
        }

        if (kDebugMode) {
          debugPrint('[TLog] Telegram API returned ${response.statusCode}');
        }
      } on DioException catch (e) {
        if (attempt == 0 && _isRetryable(e)) {
          await Future<void>.delayed(const Duration(seconds: 1));
          continue;
        }
        if (kDebugMode) {
          debugPrint('[TLog] Dio send error: ${e.type} — ${e.message}');
        }
      } catch (ex) {
        if (kDebugMode) {
          debugPrint('[TLog] Unexpected send error: $ex');
        }
      }
      break;
    }
    return false;
  }

  static bool _isRetryable(DioException e) {
    return e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError ||
        (e.response?.statusCode != null && e.response!.statusCode! >= 500);
  }

  static String _formatBatch(List<_LogEntry> batch) {
    final buf = StringBuffer();
    buf.writeln('📱 <b>Nexus AI</b>');
    buf.writeln('');

    for (final e in batch) {
      final time = _formatTime(e.timestamp);
      buf.writeln('${e.emoji} <b>[${_esc(e.tag)}]</b>  <i>$time</i>');
      buf.writeln('<code>${_esc(e.message)}</code>');

      if (e.error != null) {
        buf.writeln('⚠️ <pre>${_esc(e.error!)}</pre>');
      }
      if (e.stackTrace != null) {
        buf.writeln('<pre>${_esc(e.stackTrace!)}</pre>');
      }
      buf.writeln('─────────');
    }

    return buf.toString();
  }

  static List<String> _splitMessage(String text) {
    if (text.length <= _maxMessageLength) return [text];

    final chunks = <String>[];
    var remaining = text;
    while (remaining.isNotEmpty) {
      if (remaining.length <= _maxMessageLength) {
        chunks.add(remaining);
        break;
      }
      var splitAt = remaining.lastIndexOf('\n', _maxMessageLength);
      if (splitAt <= 0) splitAt = _maxMessageLength;
      chunks.add(remaining.substring(0, splitAt));
      remaining = remaining.substring(splitAt);
    }
    return chunks;
  }

  static String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  static String? _trimStack(StackTrace? st) {
    if (st == null) return null;
    final lines = st.toString().split('\n');
    final trimmed = lines.take(8).join('\n');
    return trimmed.isEmpty ? null : trimmed;
  }

  static String _esc(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }
}

enum _LogLevel { debug, info, warning, error, fatal }

class _LogEntry {
  _LogEntry({
    required this.emoji,
    required this.tag,
    required this.message,
    this.error,
    this.stackTrace,
    required this.timestamp,
    this.level = _LogLevel.debug,
  });

  final String emoji;
  final String tag;
  final String message;
  final String? error;
  final String? stackTrace;
  final DateTime timestamp;
  final _LogLevel level;
  int sendAttempts = 0;
}
