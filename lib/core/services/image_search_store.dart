import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../data/services/tutor_ai_service.dart';
import '../../domain/entities/tutor_entities.dart';
import '../platform/platform_capabilities.dart';
import 'background_task_coordinator.dart';
import 'telegram_logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  ImageSearchStore — singleton background job for InsightAI vision search
// ─────────────────────────────────────────────────────────────────────────────
//
// Mirrors [OnlineSearchStore]'s architecture so the image upload path
// inherits every battle-tested behaviour of the text path:
//   • Single in-flight job (key=query) survives widget disposal so the
//     user can swap tabs / minimise / rotate without losing the request.
//   • System notification while the app is in the background; suppressed
//     in foreground so the in-app loading bubble owns the UI.
//   • Retry-on-resume: if Android Doze kills the socket while the app is
//     paused, we re-queue the request with a fresh connection on the
//     next foreground transition.
//   • CancelToken so the user can abort a stuck upload at any time.
//   • Foreground-service slot acquired/released via
//     [BackgroundTaskCoordinator] so the request keeps running with
//     screen off / app minimised.
//   • Robust TLog instrumentation at every state transition.

class ImageSearchJob {
  bool loading = true;
  String stage = 'Uploading image\u2026';
  GroundedSearchResponse? result;
  String? error;

  /// The compressed JPEG bytes used for this request — held in memory so
  /// the follow-up sheet can re-attach the exact same image to every
  /// turn (the most accurate stateless-backend pattern). NOT sent across
  /// devices; the cross-device path syncs only the tiny thumbnail.
  Uint8List? imageBytes;
  String imageMediaType = 'image/jpeg';

  /// Source thumb data URL (data:image/jpeg;base64,...) and original
  /// media type. Both ride along inside the saved-search responseJson
  /// for cross-device preview without bloating the wire.
  String thumbDataUrl = '';
  String originalMediaType = 'image/jpeg';

  /// Echo of the question the user typed — surfaced verbatim in the
  /// result widget and persisted alongside the thumbnail.
  String question = '';
}

class _ImageSearchParams {
  _ImageSearchParams({
    required this.query,
    required this.service,
    required this.imageBytes,
    required this.imageMediaType,
    required this.thumbDataUrl,
    required this.originalMediaType,
    required this.useXGrok,
    this.mode,
    this.deepModel,
    this.liteModel,
    this.xgrokLiteModel,
    this.xgrokDeepModel,
    this.xgrokThinkingModel,
  });

  final String query;
  final TutorAiService service;
  final Uint8List imageBytes;
  final String imageMediaType;
  final String thumbDataUrl;
  final String originalMediaType;
  final bool useXGrok;
  final String? mode;
  final String? deepModel;
  final String? liteModel;
  final String? xgrokLiteModel;
  final String? xgrokDeepModel;
  final String? xgrokThinkingModel;
}

class ImageSearchStore with WidgetsBindingObserver {
  ImageSearchStore._();
  static final instance = ImageSearchStore._();

  final _jobs = <String, ImageSearchJob>{};
  final _params = <String, _ImageSearchParams>{};
  final _listeners = <String, VoidCallback>{};
  final _retryQueue = <String, _ImageSearchParams>{};
  final _cancelTokens = <String, CancelToken>{};
  final _resumeRetryCount = <String, int>{};
  bool _appInBackground = false;
  bool _observerBound = false;

  static const _kMaxResumeRetries = 3;

  static const _kChannelId = 'nexus_ai_processing';
  static const _kChannelName = 'AI Processing';
  static const _kChannelDesc =
      'Shows progress when AI search runs in the background';
  static const _kProcessingNotifId = 9320;
  static const _kCompletionNotifId = 9321;

  static FlutterLocalNotificationsPlugin? _notifPlugin;

  // ── Init ───────────────────────────────────────────────────────────────────

  void init() {
    if (!_observerBound) {
      _observerBound = true;
      WidgetsBinding.instance.addObserver(this);
    }
  }

  // ── Accessors ──────────────────────────────────────────────────────────────

  ImageSearchJob? getJob(String queryKey) => _jobs[queryKey];

  bool isLoading(String queryKey) => _jobs[queryKey]?.loading ?? false;

  void addListener(String queryKey, VoidCallback cb) =>
      _listeners[queryKey] = cb;

  void removeListener(String queryKey, VoidCallback cb) {
    if (_listeners[queryKey] == cb) _listeners.remove(queryKey);
  }

  // ── Start search ──────────────────────────────────────────────────────────

  /// Kick off a single-shot image search. Returns the [queryKey] the
  /// caller can use to subscribe via [addListener]/[getJob]. The image
  /// bytes are kept in memory on the job so the follow-up sheet can
  /// pull them back out for every chat turn.
  ///
  /// Important: the [query] alone is NOT a stable identity for the job
  /// (the same query string can be searched twice with two different
  /// images). The caller passes a unique [sessionKey] that ties to the
  /// active session id on screen — that's what `key`s the job map.
  String startSearch({
    required String sessionKey,
    required String query,
    required Uint8List imageBytes,
    required String imageMediaType,
    required String thumbDataUrl,
    required String originalMediaType,
    required TutorAiService service,
    required bool useXGrok,
    String? mode,
    String? deepModel,
    String? liteModel,
    String? xgrokLiteModel,
    String? xgrokDeepModel,
    String? xgrokThinkingModel,
  }) {
    init();
    final queryKey = sessionKey;

    _cancelTokens[queryKey]?.cancel('Replaced');
    _retryQueue.remove(queryKey);
    _resumeRetryCount.remove(queryKey);

    final params = _ImageSearchParams(
      query: query,
      service: service,
      imageBytes: imageBytes,
      imageMediaType: imageMediaType,
      thumbDataUrl: thumbDataUrl,
      originalMediaType: originalMediaType,
      useXGrok: useXGrok,
      mode: mode,
      deepModel: deepModel,
      liteModel: liteModel,
      xgrokLiteModel: xgrokLiteModel,
      xgrokDeepModel: xgrokDeepModel,
      xgrokThinkingModel: xgrokThinkingModel,
    );
    _params[queryKey] = params;

    final job = ImageSearchJob()
      ..imageBytes = imageBytes
      ..imageMediaType = imageMediaType
      ..thumbDataUrl = thumbDataUrl
      ..originalMediaType = originalMediaType
      ..question = query;
    _jobs[queryKey] = job;
    final token = CancelToken();
    _cancelTokens[queryKey] = token;

    _acquireCoordSlot(queryKey, query);

    final providerTag = useXGrok ? 'xGrok' : 'Gemini';
    final modeTag = mode ?? 'lite';
    final sizeKB = (imageBytes.lengthInBytes / 1024).toStringAsFixed(0);
    TLog.i('ImageSearchStore',
        'START image search \u2192 "${query.length > 50 ? '${query.substring(0, 50)}\u2026' : query}" '
        '[provider=$providerTag mode=$modeTag image=${sizeKB}KB]');

    unawaited(_executeSearch(
      queryKey: queryKey,
      params: params,
      cancelToken: token,
    ));
    return queryKey;
  }

  void cancel(String queryKey) {
    _cancelTokens[queryKey]?.cancel('User cancelled');
    _cancelTokens.remove(queryKey);
    _retryQueue.remove(queryKey);
    _resumeRetryCount.remove(queryKey);
    final job = _jobs[queryKey];
    if (job != null) {
      job
        ..loading = false
        ..stage = '';
    }
    _releaseCoordSlot(queryKey);
    _listeners[queryKey]?.call();
    TLog.d('ImageSearchStore', 'Cancelled image search ($queryKey)');
  }

  void remove(String queryKey) {
    cancel(queryKey);
    _jobs.remove(queryKey);
    _params.remove(queryKey);
    _listeners.remove(queryKey);
    _resumeRetryCount.remove(queryKey);
  }

  /// Tears the singleton back to a clean slate. Used by widget/unit
  /// tests so each scenario starts from a deterministic state. Cancels
  /// any in-flight cancel tokens defensively.
  @visibleForTesting
  void debugResetForTests() {
    for (final t in _cancelTokens.values) {
      if (!t.isCancelled) t.cancel('test-reset');
    }
    _jobs.clear();
    _params.clear();
    _listeners.clear();
    _retryQueue.clear();
    _cancelTokens.clear();
    _resumeRetryCount.clear();
    _appInBackground = false;
  }

  // ── Foreground-service slot management ────────────────────────────────

  static String _coordSlotId(String queryKey) =>
      'image_search:${queryKey.hashCode.toUnsigned(32)}';

  void _acquireCoordSlot(String queryKey, String query) {
    if (!PlatformCapabilities.canUseForegroundTask) return;
    final preview =
        query.length > 40 ? '${query.substring(0, 37)}\u2026' : query;
    unawaited(BackgroundTaskCoordinator.instance.acquire(
      _coordSlotId(queryKey),
      label: '\uD83D\uDCF7 Analyzing image: ${preview.isEmpty ? '(no question)' : preview}',
    ));
  }

  void _releaseCoordSlot(String queryKey) {
    if (!PlatformCapabilities.canUseForegroundTask) return;
    unawaited(
      BackgroundTaskCoordinator.instance.release(_coordSlotId(queryKey)),
    );
  }

  // ── Core execution ────────────────────────────────────────────────────────

  Future<void> _executeSearch({
    required String queryKey,
    required _ImageSearchParams params,
    CancelToken? cancelToken,
    bool isRetry = false,
  }) async {
    final job = _jobs[queryKey];
    if (job == null) return;

    final providerTag = params.useXGrok ? 'xGrok' : 'Gemini';
    final modeTag = params.mode ?? 'lite';
    final sw = Stopwatch()..start();

    bool keepPending = false;

    try {
      job.stage = isRetry
          ? 'Reconnecting\u2026'
          : (params.query.isEmpty
              ? 'Analyzing image\u2026'
              : 'Analyzing image + query\u2026');
      _listeners[queryKey]?.call();

      _scheduleStageUpdate(queryKey, 3000, 'Examining details\u2026');
      _scheduleStageUpdate(queryKey, 8000, 'Composing answer\u2026');
      _scheduleStageUpdate(queryKey, 18000, 'Almost there\u2026');

      try {
        if (cancelToken?.isCancelled ?? false) return;

        final result = await params.service.imageSearch(
          query: params.query,
          imageBytes: params.imageBytes,
          imageMediaType: params.imageMediaType,
          provider: params.useXGrok ? 'xgrok' : null,
          mode: params.mode,
          deepModel: params.useXGrok ? null : params.deepModel,
          liteModel: params.useXGrok ? null : params.liteModel,
          xgrokLiteModel:
              params.useXGrok ? params.xgrokLiteModel : null,
          xgrokDeepModel:
              params.useXGrok ? params.xgrokDeepModel : null,
          xgrokThinkingModel:
              params.useXGrok ? params.xgrokThinkingModel : null,
          cancelToken: cancelToken,
        );
        if (!_jobs.containsKey(queryKey)) return;
        if (cancelToken?.isCancelled ?? false) return;

        sw.stop();
        _resumeRetryCount.remove(queryKey);
        TLog.i('ImageSearchStore',
            'Image search \u2713 provider=$providerTag mode=$modeTag '
            'model=${result.model} sources=${result.sources.length} '
            '${sw.elapsedMilliseconds}ms retry=$isRetry inBackground=$_appInBackground');

        job
          ..result = result
          ..loading = false
          ..stage = '';
        return;
      } catch (e) {
        if (_isCancelled(e)) {
          if (_appInBackground || _retryQueue.containsKey(queryKey)) {
            keepPending = true;
          }
          TLog.d('ImageSearchStore',
              'Image search cancelled ${sw.elapsedMilliseconds}ms '
              '(keepPending=$keepPending)');
          return;
        }
        sw.stop();
        TLog.w('ImageSearchStore',
            '$providerTag image search [$modeTag] failed ${sw.elapsedMilliseconds}ms '
            '(${e.runtimeType}): ${_errorSummary(e)}');

        if (_isRetryableError(e) &&
            _appInBackground &&
            _jobs.containsKey(queryKey)) {
          _retryQueue[queryKey] = params;
          keepPending = true;
          job.stage = 'Will retry when connection restores\u2026';
          TLog.w('ImageSearchStore',
              'Image search failed with retryable error (app in background) '
              '\u2014 queued auto-retry on resume');
        } else if (_jobs.containsKey(queryKey)) {
          TLog.e('ImageSearchStore',
              'Image search FAILED ${sw.elapsedMilliseconds}ms '
              '(inBackground=$_appInBackground retryable=${_isRetryableError(e)})',
              error: e);
          job
            ..error = _friendlyError(e)
            ..loading = false
            ..stage = '';
        }
      }
    } finally {
      final isStillActive =
          identical(_cancelTokens[queryKey], cancelToken);

      if (isStillActive) {
        _cancelTokens.remove(queryKey);
        if (!keepPending) {
          _releaseCoordSlot(queryKey);
        }
        _listeners[queryKey]?.call();

        if (_appInBackground &&
            !keepPending &&
            _jobs.containsKey(queryKey)) {
          unawaited(_cancelProcessingNotification());
          final j = _jobs[queryKey]!;
          if (j.error == null && j.result != null) {
            unawaited(_showCompletionNotification(params.query));
          }
        }
      }
    }
  }

  void _scheduleStageUpdate(String queryKey, int delayMs, String stage) {
    Future<void>.delayed(Duration(milliseconds: delayMs)).then((_) {
      final job = _jobs[queryKey];
      if (job != null && job.loading && job.error == null) {
        job.stage = stage;
        _listeners[queryKey]?.call();
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

  static String _friendlyError(Object? e) {
    if (e is DioException) {
      final status = e.response?.statusCode;
      if (status == 413) {
        return 'Image too large for the AI model. Try a smaller picture.';
      }
      if (status != null && status >= 500) {
        return 'The AI service is temporarily unavailable. Please try again.';
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        return 'Upload timed out. Please check your connection and try again.';
      }
      if (e.type == DioExceptionType.connectionError) {
        return 'No internet connection. Please reconnect and try again.';
      }
    }
    return 'Image analysis failed. Please try again.';
  }

  static bool _isCancelled(Object? e) =>
      e is DioException && e.type == DioExceptionType.cancel;

  static bool _isRetryableError(Object? e) {
    if (e == null) return false;
    if (e is DioException) {
      if (e.type == DioExceptionType.cancel) return false;
      if (e.type != DioExceptionType.badResponse) return true;
      // 5xx are retryable; 4xx (incl. 413 too large) are not.
      final s = e.response?.statusCode;
      if (s != null && s >= 500) return true;
      return false;
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
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      final inFlightKeys = _jobs.entries
          .where((e) => e.value.loading)
          .map((e) => e.key)
          .toList();

      if (!_appInBackground && inFlightKeys.isNotEmpty) {
        _appInBackground = true;
        TLog.d('ImageSearchStore',
            'App \u2192 BACKGROUND with ${inFlightKeys.length} in-flight image search(es)');
        final firstParams = _params[inFlightKeys.first];
        unawaited(_showProcessingNotification(firstParams?.query ?? ''));
      }
      return;
    }

    if (state != AppLifecycleState.resumed) return;

    final wasInBackground = _appInBackground;
    _appInBackground = false;

    if (wasInBackground) {
      TLog.d('ImageSearchStore',
          'App \u2192 FOREGROUND (was in background)');
      unawaited(_cancelProcessingNotification());

      for (final queryKey in _jobs.keys.toList()) {
        final job = _jobs[queryKey];
        if (job == null || !job.loading) continue;
        if (_retryQueue.containsKey(queryKey)) continue;

        final p = _params[queryKey];
        if (p == null) continue;

        final token = _cancelTokens[queryKey];
        if (token != null && !token.isCancelled) {
          TLog.d('ImageSearchStore',
              'Resume-cancel in-flight Dio request for image search');
          token.cancel('resume-requeue');
        }
        _retryQueue[queryKey] = p;
      }
    }

    for (final cb in List.of(_listeners.values)) {
      cb.call();
    }

    if (_retryQueue.isEmpty) return;
    final pendingKeys = _retryQueue.keys.toList();

    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      for (final queryKey in pendingKeys) {
        final p = _retryQueue.remove(queryKey);
        if (p == null) continue;
        final job = _jobs[queryKey];
        if (job == null || !job.loading) continue;

        final attempts = (_resumeRetryCount[queryKey] ?? 0) + 1;
        if (attempts > _kMaxResumeRetries) {
          TLog.e('ImageSearchStore',
              'Max resume retries ($_kMaxResumeRetries) exhausted for image search');
          job
            ..error =
                'Connection could not be restored after $_kMaxResumeRetries attempts. '
                    'Please try again.'
            ..loading = false
            ..stage = '';
          _resumeRetryCount.remove(queryKey);
          _releaseCoordSlot(queryKey);
          _listeners[queryKey]?.call();
          continue;
        }
        _resumeRetryCount[queryKey] = attempts;

        TLog.i('ImageSearchStore',
            'Resume retry $attempts/$_kMaxResumeRetries for image search');

        job
          ..loading = true
          ..stage = 'Reconnecting\u2026'
          ..error = null
          ..result = null;
        _listeners[queryKey]?.call();

        final token = CancelToken();
        _cancelTokens[queryKey] = token;
        _acquireCoordSlot(queryKey, p.query);

        unawaited(_executeSearch(
          queryKey: queryKey,
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

  Future<void> _showProcessingNotification(String query) async {
    if (!PlatformCapabilities.canUseNotifications) return;
    try {
      final fln = await _ensureNotifPlugin();
      final q = query.isEmpty
          ? 'your photo'
          : (query.length > 50 ? '${query.substring(0, 50)}\u2026' : query);
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
        '\uD83D\uDCF7 Analyzing image\u2026',
        'Working on $q',
        const NotificationDetails(android: details),
      );
    } catch (e) {
      TLog.w('ImageSearchStore', 'Failed to show processing notification',
          error: e);
    }
  }

  Future<void> _showCompletionNotification(String query) async {
    if (!PlatformCapabilities.canUseNotifications) return;
    try {
      final fln = await _ensureNotifPlugin();
      await fln.cancel(_kProcessingNotifId);
      final q = query.isEmpty
          ? 'your photo'
          : (query.length > 50 ? '${query.substring(0, 50)}\u2026' : query);
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
        '\u2705 Image analyzed',
        'Result ready for $q',
        const NotificationDetails(android: details),
        payload: 'tutor_tab',
      );
    } catch (e) {
      TLog.w('ImageSearchStore', 'Failed to show completion notification',
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
