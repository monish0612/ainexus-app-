import 'dart:async';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../data/services/tutor_ai_service.dart';
import '../../domain/entities/tutor_entities.dart';
import '../platform/platform_capabilities.dart';
import 'background_task_coordinator.dart';
import 'telegram_logger.dart';

/// Holds the mutable state of a single online search operation.
class SearchJob {
  bool loading = true;
  String stage = 'Searching the web\u2026';
  GroundedSearchResponse? groundedResult;
  TavilySearchResponse? tavilyResult;
  String? error;
}

class _SearchParams {
  _SearchParams({
    required this.query,
    required this.service,
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
  final bool useXGrok;

  /// 'lite' (fast, default) or 'deep' (thorough). When null the backend
  /// defaults to 'lite' for backward compatibility.
  final String? mode;

  /// Gemini deep model — only relevant when mode == 'deep'.
  final String? deepModel;

  /// Gemini lite model — only relevant when mode == 'lite' and not xGrok.
  /// Forwarded as `liteModel` so the backend pins the user-configured
  /// Flash/Lite version (synced cross-device via user_preferences).
  final String? liteModel;

  /// xGrok model overrides per depth — only relevant when useXGrok is true.
  final String? xgrokLiteModel;
  final String? xgrokDeepModel;
  final String? xgrokThinkingModel;
}

/// Singleton store that executes online searches (grounded → Tavily fallback)
/// in a background-resilient way.
///
/// Survives widget disposal, shows system notifications when the app is
/// backgrounded, and auto-retries on resume after connection aborts caused by
/// Android screen-off / app minimisation.
///
/// On resume, any in-flight requests that are stuck in Dio retry loops are
/// cancelled and immediately re-queued with a fresh connection, avoiding the
/// ~2 min dead-wait from stacked Dio retries with dead sockets.
class OnlineSearchStore with WidgetsBindingObserver {
  OnlineSearchStore._();
  static final instance = OnlineSearchStore._();

  final _jobs = <String, SearchJob>{};
  final _params = <String, _SearchParams>{};
  final _listeners = <String, VoidCallback>{};
  final _retryQueue = <String, _SearchParams>{};
  final _cancelTokens = <String, CancelToken>{};
  final _resumeRetryCount = <String, int>{};
  bool _appInBackground = false;
  bool _observerBound = false;

  static const _kMaxResumeRetries = 3;

  static const _kChannelId = 'nexus_ai_processing';
  static const _kChannelName = 'AI Processing';
  static const _kChannelDesc =
      'Shows progress when AI search runs in the background';
  static const _kProcessingNotifId = 9300;
  static const _kCompletionNotifId = 9301;

  static FlutterLocalNotificationsPlugin? _notifPlugin;

  // ── Init ───────────────────────────────────────────────────────────────────

  void init() {
    if (!_observerBound) {
      _observerBound = true;
      WidgetsBinding.instance.addObserver(this);
    }
  }

  // ── Accessors ──────────────────────────────────────────────────────────────

  SearchJob? getJob(String queryKey) => _jobs[queryKey];

  bool isLoading(String queryKey) => _jobs[queryKey]?.loading ?? false;

  void addListener(String queryKey, VoidCallback cb) =>
      _listeners[queryKey] = cb;

  void removeListener(String queryKey, VoidCallback cb) {
    if (_listeners[queryKey] == cb) _listeners.remove(queryKey);
  }

  // ── Start search ──────────────────────────────────────────────────────────

  /// Start a grounded search with Tavily fallback. The search runs via
  /// [unawaited] and survives widget disposal. Returns the query key so the
  /// caller can [addListener] and [getJob].
  ///
  /// [mode] selects depth — 'lite' (fast, default) or 'deep' (thorough). When
  /// null the backend treats it as 'lite' for backward compatibility.
  ///
  /// The model hints are only forwarded when their respective provider/mode
  /// pair is active on the backend (e.g. [deepModel] is consulted only when
  /// mode='deep' and useXGrok=false).
  String startSearch({
    required String query,
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
    final queryKey = query;

    _cancelTokens[queryKey]?.cancel('Replaced');
    _retryQueue.remove(queryKey);
    _resumeRetryCount.remove(queryKey);

    final params = _SearchParams(
      query: query,
      service: service,
      useXGrok: useXGrok,
      mode: mode,
      deepModel: deepModel,
      liteModel: liteModel,
      xgrokLiteModel: xgrokLiteModel,
      xgrokDeepModel: xgrokDeepModel,
      xgrokThinkingModel: xgrokThinkingModel,
    );
    _params[queryKey] = params;

    final job = SearchJob();
    _jobs[queryKey] = job;
    final token = CancelToken();
    _cancelTokens[queryKey] = token;

    _acquireCoordSlot(queryKey, query);

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
    TLog.d('SearchStore', 'Cancelled search for key="${queryKey.length > 50 ? '${queryKey.substring(0, 50)}\u2026' : queryKey}"');
  }

  void remove(String queryKey) {
    cancel(queryKey);
    _jobs.remove(queryKey);
    _params.remove(queryKey);
    _listeners.remove(queryKey);
    _resumeRetryCount.remove(queryKey);
  }

  // ── Foreground-service slot management ────────────────────────────────

  /// Slot ids used with [BackgroundTaskCoordinator] are scoped to this
  /// store so two queries with identical text don't collide with a slot
  /// owned by another store (URL summarize, follow-up Q&A, etc).
  static String _coordSlotId(String queryKey) =>
      'online_search:${queryKey.hashCode.toUnsigned(32)}';

  void _acquireCoordSlot(String queryKey, String query) {
    if (!PlatformCapabilities.canUseForegroundTask) return;
    final preview =
        query.length > 40 ? '${query.substring(0, 37)}\u2026' : query;
    unawaited(BackgroundTaskCoordinator.instance.acquire(
      _coordSlotId(queryKey),
      label: '\uD83D\uDD0D Searching: $preview',
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
    required _SearchParams params,
    CancelToken? cancelToken,
    bool isRetry = false,
  }) async {
    final job = _jobs[queryKey];
    if (job == null) return;

    final providerTag = params.useXGrok ? 'xGrok' : 'Gemini';
    final modeTag = params.mode ?? 'lite';
    final sw = Stopwatch()..start();

    TLog.d(
      'SearchStore',
      '${isRetry ? 'RETRY' : 'START'} search \u2192 '
          '"${params.query.length > 60 ? '${params.query.substring(0, 57)}\u2026' : params.query}" '
          '[provider=$providerTag, mode=$modeTag, inBackground=$_appInBackground]',
    );

    bool keepPending = false;

    try {
      // ── Phase 1: Grounded search ────────────────────────────────────────
      // The service layer (TutorAiService.groundedSearch) already has 3×
      // retry with exponential backoff, and the Dio interceptor adds 3×
      // HTTP-level retry. We do NOT add another retry loop here to avoid
      // stacking (3 × 3 × 3 = 27 calls with dead connection). Instead we
      // attempt once per phase and rely on the resume-retry queue for
      // persistent connection loss.
      job.stage = isRetry ? 'Reconnecting\u2026' : 'Searching the web\u2026';
      _listeners[queryKey]?.call();

      _scheduleStageUpdate(queryKey, 2000, 'Analyzing results\u2026');
      _scheduleStageUpdate(queryKey, 5000, 'Preparing answer\u2026');
      _scheduleStageUpdate(queryKey, 12000, 'Almost there\u2026');

      Object? groundedError;

      try {
        if (cancelToken?.isCancelled ?? false) return;

        final result = await params.service.groundedSearch(
          query: params.query,
          provider: params.useXGrok ? 'xgrok' : null,
          mode: params.mode,
          deepModel: params.useXGrok ? null : params.deepModel,
          liteModel: params.useXGrok ? null : params.liteModel,
          xgrokLiteModel: params.useXGrok ? params.xgrokLiteModel : null,
          xgrokDeepModel: params.useXGrok ? params.xgrokDeepModel : null,
          xgrokThinkingModel: params.useXGrok ? params.xgrokThinkingModel : null,
          cancelToken: cancelToken,
        );
        if (!_jobs.containsKey(queryKey)) return;
        if (cancelToken?.isCancelled ?? false) return;

        sw.stop();
        _resumeRetryCount.remove(queryKey);
        TLog.i('SearchStore',
            'Search \u2713 provider=$providerTag mode=$modeTag model=${result.model} '
            'sources=${result.sources.length} ${sw.elapsedMilliseconds}ms '
            'retry=$isRetry inBackground=$_appInBackground');

        job
          ..groundedResult = result
          ..loading = false
          ..stage = '';
        return;
      } catch (e) {
        if (_isCancelled(e)) {
          if (_appInBackground || _retryQueue.containsKey(queryKey)) {
            keepPending = true;
          }
          TLog.d('SearchStore',
              'Grounded search cancelled ${sw.elapsedMilliseconds}ms '
              '(keepPending=$keepPending)');
          return;
        }
        groundedError = e;
        TLog.w('SearchStore',
            '$providerTag grounded search [$modeTag] failed ${sw.elapsedMilliseconds}ms '
            '(${e.runtimeType}): ${_errorSummary(e)}');
      }

      // ── Phase 2: Tavily fallback ────────────────────────────────────────
      if (cancelToken?.isCancelled ?? false) {
        if (_appInBackground || _retryQueue.containsKey(queryKey)) {
          keepPending = true;
        }
        return;
      }
      if (!_jobs.containsKey(queryKey)) return;

      TLog.d('SearchStore', 'Falling back to Tavily search');

      job.stage = 'Trying backup search\u2026';
      _listeners[queryKey]?.call();

      Object? tavilyError;

      try {
        if (cancelToken?.isCancelled ?? false) return;

        final result = await params.service.search(
          query: params.query,
          cancelToken: cancelToken,
        );
        if (!_jobs.containsKey(queryKey)) return;
        if (cancelToken?.isCancelled ?? false) return;

        sw.stop();
        _resumeRetryCount.remove(queryKey);
        TLog.i('SearchStore',
            'Tavily fallback \u2713 results=${result.results.length} '
            '${sw.elapsedMilliseconds}ms retry=$isRetry '
            'inBackground=$_appInBackground');

        job
          ..tavilyResult = result
          ..loading = false
          ..stage = '';
        return;
      } catch (e) {
        if (_isCancelled(e)) {
          if (_appInBackground || _retryQueue.containsKey(queryKey)) {
            keepPending = true;
          }
          TLog.d('SearchStore',
              'Tavily search cancelled ${sw.elapsedMilliseconds}ms '
              '(keepPending=$keepPending)');
          return;
        }
        tavilyError = e;
        TLog.w('SearchStore',
            'Tavily fallback also failed ${sw.elapsedMilliseconds}ms '
            '(${e.runtimeType}): ${_errorSummary(e)}');
      }

      // ── Both failed ─────────────────────────────────────────────────────
      final finalError = tavilyError ?? groundedError;

      if (finalError != null &&
          _isRetryableError(finalError) &&
          _appInBackground &&
          _jobs.containsKey(queryKey)) {
        _retryQueue[queryKey] = params;
        keepPending = true;
        job.stage = 'Will retry when connection restores\u2026';
        TLog.w('SearchStore',
            'All providers failed with retryable error (app in background) '
            '\u2014 queued auto-retry on resume for "${params.query}"');
      } else if (_jobs.containsKey(queryKey)) {
        sw.stop();
        TLog.e('SearchStore',
            'All search providers FAILED '
            '${sw.elapsedMilliseconds}ms '
            '(inBackground=$_appInBackground '
            'retryable=${finalError != null && _isRetryableError(finalError)})',
            error: finalError);
        job
          ..error =
              'Search failed. Please check your connection and try again.'
          ..loading = false
          ..stage = '';
      }
    } finally {
      // Only finalise state if THIS execution is still the active one. A
      // concurrent startSearch ("Retry") or resume-retry replaces
      // `_cancelTokens[queryKey]` with a newer token; in that case the
      // newer execution owns the slot + token entry and we must leave
      // them alone — otherwise we'd kill the FG service mid-retry and
      // remove the live cancel-token from the map.
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
          if (j.error == null &&
              (j.groundedResult != null || j.tavilyResult != null)) {
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

  static bool _isCancelled(Object? e) =>
      e is DioException && e.type == DioExceptionType.cancel;

  /// Any Dio transport-level error (timeout, socket kill, connection reset,
  /// unknown) is retryable. HTTP response errors (4xx/5xx) are not — those
  /// are already retried by the Dio interceptor.
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
        TLog.d('SearchStore',
            'App \u2192 BACKGROUND with ${inFlightKeys.length} in-flight '
            'search(es)');
        unawaited(_showProcessingNotification(inFlightKeys.first));
      }
      return;
    }

    // ── Returning to foreground ──────────────────────────────────────────
    if (state != AppLifecycleState.resumed) return;

    final wasInBackground = _appInBackground;
    _appInBackground = false;

    if (wasInBackground) {
      TLog.d('SearchStore', 'App \u2192 FOREGROUND (was in background)');
      unawaited(_cancelProcessingNotification());

      // Cancel any in-flight requests stuck in Dio retry loops and re-queue
      // them for immediate retry with a fresh connection.
      for (final queryKey in _jobs.keys.toList()) {
        final job = _jobs[queryKey];
        if (job == null || !job.loading) continue;
        if (_retryQueue.containsKey(queryKey)) continue;

        final p = _params[queryKey];
        if (p == null) continue;

        final token = _cancelTokens[queryKey];
        if (token != null && !token.isCancelled) {
          TLog.d('SearchStore',
              'Resume-cancel in-flight Dio request for "${p.query.length > 40 ? '${p.query.substring(0, 40)}\u2026' : p.query}"');
          token.cancel('resume-requeue');
        }
        _retryQueue[queryKey] = p;
      }
    }

    for (final cb in List.of(_listeners.values)) {
      cb.call();
    }

    if (_retryQueue.isEmpty) return;
    // Snapshot the keys but DO NOT clear the queue yet. Leaving entries in
    // place across the 1500ms reconnect delay keeps the in-flight cancel
    // catch's `keepPending` check (`_retryQueue.containsKey(queryKey)`)
    // correct, so the FG-service slot is not released during the gap.
    final pendingKeys = _retryQueue.keys.toList();

    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      for (final queryKey in pendingKeys) {
        final p = _retryQueue.remove(queryKey);
        if (p == null) continue; // cancelled / replaced while delayed
        final job = _jobs[queryKey];
        if (job == null || !job.loading) continue;

        final attempts = (_resumeRetryCount[queryKey] ?? 0) + 1;
        if (attempts > _kMaxResumeRetries) {
          TLog.e('SearchStore',
              'Max resume retries ($_kMaxResumeRetries) exhausted for '
              '"${p.query.length > 50 ? '${p.query.substring(0, 50)}\u2026' : p.query}"');
          job
            ..error = 'Connection could not be restored after '
                '$_kMaxResumeRetries attempts. Please try again.'
            ..loading = false
            ..stage = '';
          _resumeRetryCount.remove(queryKey);
          // The previous attempt held the FG-service slot via keepPending;
          // since we're giving up, drop it so the OS can settle.
          _releaseCoordSlot(queryKey);
          _listeners[queryKey]?.call();
          continue;
        }
        _resumeRetryCount[queryKey] = attempts;

        TLog.i('SearchStore',
            'Resume retry $attempts/$_kMaxResumeRetries for '
            '"${p.query.length > 50 ? '${p.query.substring(0, 50)}\u2026' : p.query}"');

        job
          ..loading = true
          ..stage = 'Reconnecting\u2026'
          ..error = null
          ..groundedResult = null
          ..tavilyResult = null;
        _listeners[queryKey]?.call();

        final token = CancelToken();
        _cancelTokens[queryKey] = token;

        // Re-acquire the FG-service slot before firing the request so the
        // retry itself is also Doze-protected.
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
      final q = query.length > 50 ? '${query.substring(0, 50)}\u2026' : query;
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
        '\uD83D\uDD0D Searching\u2026',
        'Looking up "$q"',
        const NotificationDetails(android: details),
      );
    } catch (e) {
      TLog.w('SearchStore', 'Failed to show processing notification',
          error: e);
    }
  }

  Future<void> _showCompletionNotification(String query) async {
    if (!PlatformCapabilities.canUseNotifications) return;
    try {
      final fln = await _ensureNotifPlugin();
      await fln.cancel(_kProcessingNotifId);
      final q = query.length > 50 ? '${query.substring(0, 50)}\u2026' : query;
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
        '\u2705 Search complete',
        'Results ready for "$q"',
        const NotificationDetails(android: details),
        payload: 'tutor_tab',
      );
    } catch (e) {
      TLog.w('SearchStore', 'Failed to show completion notification',
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
