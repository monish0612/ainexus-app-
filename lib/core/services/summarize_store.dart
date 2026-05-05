import 'dart:async';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../data/services/tutor_ai_service.dart';
import '../../domain/entities/tutor_entities.dart';
import '../platform/platform_capabilities.dart';
import 'telegram_logger.dart';

/// Mutable state of a single URL summarize operation.
class SummarizeJob {
  bool loading = true;
  String stage = 'Connecting to URL\u2026';
  SummarizerResult? result;
  String? error;
}

class _SummarizeParams {
  _SummarizeParams({
    required this.url,
    required this.service,
    this.provider,
    this.xgrokModel,
  });

  final String url;
  final TutorAiService service;
  final String? provider;
  final String? xgrokModel;
}

/// Singleton store that executes URL summarizations in a background-resilient
/// way.
///
/// Survives widget disposal, shows system notifications when the app is
/// backgrounded, and auto-retries on resume after connection aborts caused by
/// Android Doze / app minimisation.
///
/// On resume, any in-flight requests that are stuck in Dio retry loops are
/// cancelled and immediately re-queued with a fresh connection, avoiding the
/// ~2 min dead-wait from stacked Dio retries with dead sockets.
class SummarizeStore with WidgetsBindingObserver {
  SummarizeStore._();
  static final instance = SummarizeStore._();

  final _jobs = <String, SummarizeJob>{};
  final _params = <String, _SummarizeParams>{};
  final _listeners = <String, VoidCallback>{};
  final _retryQueue = <String, _SummarizeParams>{};
  final _cancelTokens = <String, CancelToken>{};
  final _resumeRetryCount = <String, int>{};
  bool _appInBackground = false;
  bool _observerBound = false;

  static const _kMaxResumeRetries = 3;

  static const _kChannelId = 'nexus_ai_processing';
  static const _kChannelName = 'AI Processing';
  static const _kChannelDesc =
      'Shows progress when AI tasks run in the background';
  static const _kProcessingNotifId = 9400;
  static const _kCompletionNotifId = 9401;

  static FlutterLocalNotificationsPlugin? _notifPlugin;

  // ── Init ───────────────────────────────────────────────────────────────────

  void init() {
    if (!_observerBound) {
      _observerBound = true;
      WidgetsBinding.instance.addObserver(this);
    }
  }

  // ── Accessors ──────────────────────────────────────────────────────────────

  SummarizeJob? getJob(String key) => _jobs[key];

  bool isLoading(String key) => _jobs[key]?.loading ?? false;

  void addListener(String key, VoidCallback cb) => _listeners[key] = cb;

  void removeListener(String key, VoidCallback cb) {
    if (_listeners[key] == cb) _listeners.remove(key);
  }

  // ── Start summarize ────────────────────────────────────────────────────────

  String startSummarize({
    required String url,
    required TutorAiService service,
    String? provider,
    String? xgrokModel,
  }) {
    init();
    final key = url;

    _cancelTokens[key]?.cancel('Replaced');
    _retryQueue.remove(key);
    _resumeRetryCount.remove(key);

    final params = _SummarizeParams(
      url: url,
      service: service,
      provider: provider,
      xgrokModel: xgrokModel,
    );
    _params[key] = params;

    final job = SummarizeJob();
    _jobs[key] = job;
    final token = CancelToken();
    _cancelTokens[key] = token;

    unawaited(_executeSummarize(
      key: key,
      params: params,
      cancelToken: token,
    ));
    return key;
  }

  void cancel(String key) {
    _cancelTokens[key]?.cancel('User cancelled');
    _cancelTokens.remove(key);
    _retryQueue.remove(key);
    _resumeRetryCount.remove(key);
    final job = _jobs[key];
    if (job != null) {
      job
        ..loading = false
        ..stage = '';
    }
    _listeners[key]?.call();
    TLog.d('SummarizeStore', 'Cancelled summarize for key="${key.length > 50 ? '${key.substring(0, 50)}\u2026' : key}"');
  }

  void remove(String key) {
    cancel(key);
    _jobs.remove(key);
    _params.remove(key);
    _listeners.remove(key);
    _resumeRetryCount.remove(key);
  }

  // ── Core execution ─────────────────────────────────────────────────────────

  Future<void> _executeSummarize({
    required String key,
    required _SummarizeParams params,
    CancelToken? cancelToken,
    bool isRetry = false,
  }) async {
    final job = _jobs[key];
    if (job == null) return;

    final providerTag = params.provider == 'xgrok' ? 'xGrok' : 'Gemini';
    final sw = Stopwatch()..start();

    TLog.d(
      'SummarizeStore',
      '${isRetry ? 'RETRY' : 'START'} summarize \u2192 '
          '"${params.url.length > 60 ? '${params.url.substring(0, 57)}\u2026' : params.url}" '
          '[provider=$providerTag, inBackground=$_appInBackground]',
    );

    bool keepPending = false;

    try {
      job.stage = isRetry ? 'Reconnecting\u2026' : 'Connecting to URL\u2026';
      _listeners[key]?.call();

      _scheduleStageUpdate(key, 1500, 'Extracting page content\u2026');
      _scheduleStageUpdate(key, 4000, 'Analyzing with $providerTag\u2026');
      _scheduleStageUpdate(key, 8000, 'Generating detailed breakdown\u2026');
      _scheduleStageUpdate(key, 14000, 'Almost done\u2026');
      _scheduleStageUpdate(key, 25000, 'Still working (deep extraction)\u2026');

      try {
        if (cancelToken?.isCancelled ?? false) return;

        final result = await params.service.summarize(
          url: params.url,
          provider: params.provider,
          xgrokModel: params.xgrokModel,
          cancelToken: cancelToken,
        );

        if (!_jobs.containsKey(key)) return;
        if (cancelToken?.isCancelled ?? false) return;

        sw.stop();
        _resumeRetryCount.remove(key);

        if (result.fallback) {
          TLog.w('SummarizeStore',
              'Summarize \u2713 WITH FALLBACK: xGrok\u2192${result.providerUsed} '
              'model=${result.model} ${sw.elapsedMilliseconds}ms '
              'method=${result.extractionMethod} '
              'inBackground=$_appInBackground');
        } else {
          TLog.i('SummarizeStore',
              'Summarize \u2713 provider=${result.providerUsed} '
              'model=${result.model} method=${result.extractionMethod} '
              '${sw.elapsedMilliseconds}ms retry=$isRetry '
              'inBackground=$_appInBackground');
        }

        job
          ..result = result
          ..loading = false
          ..stage = '';
        return;
      } catch (e) {
        if (_isCancelled(e)) {
          // If cancelled because resume-handler is re-queuing, keep pending.
          if (_appInBackground || _retryQueue.containsKey(key)) {
            keepPending = true;
          }
          TLog.d('SummarizeStore',
              'Summarize cancelled ${sw.elapsedMilliseconds}ms '
              '(keepPending=$keepPending, inBackground=$_appInBackground)');
          return;
        }

        sw.stop();
        TLog.w('SummarizeStore',
            'Summarize FAILED ${sw.elapsedMilliseconds}ms '
            '(${e.runtimeType}): ${_errorSummary(e)} '
            '[inBackground=$_appInBackground, retry=$isRetry]');

        if (_isRetryableError(e) &&
            _appInBackground &&
            _jobs.containsKey(key)) {
          _retryQueue[key] = params;
          keepPending = true;
          job.stage = 'Will retry when connection restores\u2026';
          TLog.w('SummarizeStore',
              'Queued auto-retry on resume for "${params.url.length > 50 ? '${params.url.substring(0, 50)}\u2026' : params.url}"');
        } else if (_jobs.containsKey(key)) {
          final msg = e.toString();
          final userMsg = msg.contains('422') || msg.contains('extract')
              ? 'Could not extract content. Ensure the URL starts with '
                  'https:// and is publicly accessible.'
              : 'Summarization failed. Please check your connection and '
                  'try again.';
          job
            ..error = userMsg
            ..loading = false
            ..stage = '';
        }
      }
    } finally {
      _cancelTokens.remove(key);
      _listeners[key]?.call();

      if (_appInBackground && !keepPending && _jobs.containsKey(key)) {
        unawaited(_cancelProcessingNotification());
        final j = _jobs[key]!;
        if (j.error == null && j.result != null) {
          unawaited(_showCompletionNotification(params.url));
        }
      }
    }
  }

  void _scheduleStageUpdate(String key, int delayMs, String stage) {
    Future<void>.delayed(Duration(milliseconds: delayMs)).then((_) {
      final job = _jobs[key];
      if (job != null && job.loading && job.error == null) {
        job.stage = stage;
        _listeners[key]?.call();
      }
    });
  }

  // ── Error classification ──────────────────────────────────────────────────

  static String _errorSummary(Object? e) {
    if (e is DioException) {
      final status = e.response?.statusCode;
      if (status != null) return 'HTTP $status (${e.type})';
      return '${e.type}: ${e.message ?? e.error ?? 'no details'}';
    }
    final s = e.toString();
    return s.length > 120 ? '${s.substring(0, 120)}\u2026' : s;
  }

  static bool _isCancelled(Object? e) =>
      e is DioException && e.type == DioExceptionType.cancel;

  static bool _isRetryableError(Object? e) {
    if (e == null) return false;
    if (e is DioException) {
      if (e.type == DioExceptionType.cancel) return false;
      if (e.type != DioExceptionType.badResponse) return true;
    }
    final s = e.toString().toLowerCase();
    return s.contains('connection abort') ||
        s.contains('connection reset') ||
        s.contains('broken pipe') ||
        s.contains('network is unreachable') ||
        s.contains('socket') ||
        s.contains('timed out') ||
        s.contains('connection closed');
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // ── Going to background ──────────────────────────────────────────────
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      final inFlightKeys = _jobs.entries
          .where((e) => e.value.loading)
          .map((e) => e.key)
          .toList();

      if (!_appInBackground && inFlightKeys.isNotEmpty) {
        _appInBackground = true;
        TLog.d('SummarizeStore',
            'App \u2192 BACKGROUND with ${inFlightKeys.length} in-flight '
            'summarize(s): ${inFlightKeys.map((k) => k.length > 30 ? '${k.substring(0, 30)}\u2026' : k).join(', ')}');
        unawaited(_showProcessingNotification(inFlightKeys.first));
      }
      return;
    }

    // ── Returning to foreground ──────────────────────────────────────────
    if (state != AppLifecycleState.resumed) return;

    final wasInBackground = _appInBackground;
    _appInBackground = false;

    if (wasInBackground) {
      TLog.d('SummarizeStore', 'App \u2192 FOREGROUND (was in background)');
      unawaited(_cancelProcessingNotification());

      // Cancel any in-flight requests that are stuck in Dio retry loops.
      // Re-queue them for immediate retry with a fresh connection instead
      // of waiting ~2 min for stacked Dio retries to exhaust on dead sockets.
      for (final key in _jobs.keys.toList()) {
        final job = _jobs[key];
        if (job == null || !job.loading) continue;
        if (_retryQueue.containsKey(key)) continue;

        final p = _params[key];
        if (p == null) continue;

        final token = _cancelTokens[key];
        if (token != null && !token.isCancelled) {
          TLog.d('SummarizeStore',
              'Resume-cancel in-flight Dio request for "${p.url.length > 40 ? '${p.url.substring(0, 40)}\u2026' : p.url}"');
          token.cancel('resume-requeue');
        }
        _retryQueue[key] = p;
      }
    }

    for (final cb in List.of(_listeners.values)) {
      cb.call();
    }

    if (_retryQueue.isEmpty) return;
    final entries = Map.of(_retryQueue);
    _retryQueue.clear();

    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      for (final e in entries.entries) {
        final key = e.key;
        final p = e.value;
        final job = _jobs[key];
        if (job == null || !job.loading) continue;

        final attempts = (_resumeRetryCount[key] ?? 0) + 1;
        if (attempts > _kMaxResumeRetries) {
          TLog.e('SummarizeStore',
              'Max resume retries ($_kMaxResumeRetries) exhausted for '
              '"${p.url.length > 50 ? '${p.url.substring(0, 50)}\u2026' : p.url}"');
          job
            ..error = 'Connection could not be restored after '
                '$_kMaxResumeRetries attempts. Please try again.'
            ..loading = false
            ..stage = '';
          _resumeRetryCount.remove(key);
          _listeners[key]?.call();
          continue;
        }
        _resumeRetryCount[key] = attempts;

        TLog.i('SummarizeStore',
            'Resume retry $attempts/$_kMaxResumeRetries for '
            '"${p.url.length > 50 ? '${p.url.substring(0, 50)}\u2026' : p.url}"');

        job
          ..loading = true
          ..stage = 'Reconnecting\u2026'
          ..error = null
          ..result = null;
        _listeners[key]?.call();

        final token = CancelToken();
        _cancelTokens[key] = token;

        unawaited(_executeSummarize(
          key: key,
          params: p,
          cancelToken: token,
          isRetry: true,
        ));
      }
    });
  }

  // ── Notifications ─────────────────────────────────────────────────────────

  static Future<FlutterLocalNotificationsPlugin> _ensureNotifPlugin() async {
    if (_notifPlugin != null) return _notifPlugin!;
    _notifPlugin = FlutterLocalNotificationsPlugin();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notifPlugin!
        .initialize(const InitializationSettings(android: android));
    return _notifPlugin!;
  }

  Future<void> _showProcessingNotification(String url) async {
    if (!PlatformCapabilities.canUseNotifications) return;
    try {
      final fln = await _ensureNotifPlugin();
      final u = url.length > 50 ? '${url.substring(0, 50)}\u2026' : url;
      const details = AndroidNotificationDetails(
        _kChannelId,
        _kChannelName,
        channelDescription: _kChannelDesc,
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
        showProgress: true,
        indeterminate: true,
        category: AndroidNotificationCategory.progress,
        color: ui.Color(0xFF0D59F2),
      );
      await fln.show(
        _kProcessingNotifId,
        '\uD83D\uDCDD Summarizing\u2026',
        'Processing "$u"',
        const NotificationDetails(android: details),
      );
    } catch (e) {
      TLog.w('SummarizeStore', 'Failed to show processing notification',
          error: e);
    }
  }

  Future<void> _showCompletionNotification(String url) async {
    if (!PlatformCapabilities.canUseNotifications) return;
    try {
      final fln = await _ensureNotifPlugin();
      await fln.cancel(_kProcessingNotifId);
      final u = url.length > 50 ? '${url.substring(0, 50)}\u2026' : url;
      const details = AndroidNotificationDetails(
        _kChannelId,
        _kChannelName,
        channelDescription: _kChannelDesc,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.message,
        color: ui.Color(0xFF0D59F2),
      );
      await fln.show(
        _kCompletionNotifId,
        '\u2705 Summary ready',
        'Results ready for "$u"',
        const NotificationDetails(android: details),
        payload: 'tutor_tab',
      );
    } catch (e) {
      TLog.w('SummarizeStore', 'Failed to show completion notification',
          error: e);
    }
  }

  Future<void> _cancelProcessingNotification() async {
    if (!PlatformCapabilities.canUseNotifications) return;
    try {
      final fln = await _ensureNotifPlugin();
      await fln.cancel(_kProcessingNotifId);
    } catch (_) {}
  }
}
