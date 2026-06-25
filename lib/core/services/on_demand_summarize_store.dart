import 'dart:async';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../data/repositories/news_repository.dart';
import '../../data/services/news_summarize_service.dart';
import '../../domain/entities/news_entities.dart';
import '../network/ai_error.dart';
import '../platform/platform_capabilities.dart';
import 'background_task_coordinator.dart';
import 'telegram_logger.dart';

/// Status of a single article's on-demand AI summary.
enum OnDemandStatus { idle, loading, ready, error }

/// Immutable per-article state exposed to [ArticleDetailModal].
@immutable
class OnDemandSummaryState {
  const OnDemandSummaryState({
    required this.status,
    this.summary,
    this.error,
  });

  const OnDemandSummaryState.idle() : this(status: OnDemandStatus.idle);
  const OnDemandSummaryState.loading() : this(status: OnDemandStatus.loading);
  const OnDemandSummaryState.ready(String summary)
      : this(status: OnDemandStatus.ready, summary: summary);
  const OnDemandSummaryState.error(String error)
      : this(status: OnDemandStatus.error, error: error);

  final OnDemandStatus status;
  final String? summary;
  final String? error;

  bool get isLoading => status == OnDemandStatus.loading;
}

/// Drives the per-article **"AI Summarize"** button in the article reader as a
/// background-robust job — the production-grade sibling of the follow-up chat
/// flow ([ArticleFollowUpStore]) and the For You batch flow
/// ([NewsSummarizeStore]).
///
/// ## Why this exists
/// The old in-modal `await service.summarizeBatch(...)` died the moment the
/// user minimised the app (Android Doze killed the socket within ~60 s) or
/// closed the modal (`if (!mounted) return;` dropped the result). This store
/// fixes both:
///
///   - **Background-survivable.** While a summary is generating it holds a
///     [BackgroundTaskCoordinator] slot, promoting the process to a foreground
///     service so the OS keeps the in-flight HTTP call alive when the app is
///     minimised / the screen is off.
///   - **Lifecycle-independent.** Work runs on the singleton, NOT the widget.
///     Closing the modal can't lose the result — it's persisted to the local
///     DB ([NewsRepository.setSummaryShort]) and kept in `_state` keyed by
///     articleId, so re-opening shows it instantly.
///   - **Resilient.** Each request retries [_kMaxAttempts] times with
///     exponential backoff. On app-resume any socket left "loading" through a
///     long Doze is cancelled and re-fired on a fresh connection instead of
///     waiting ~2 min for stacked TCP retries.
///   - **Observable.** A high-priority completion notification fires when a
///     summary finishes while the app was backgrounded; tapping it returns to
///     the app.
///
/// ## Isolation
/// Deliberately independent of [NewsSummarizeStore]: it uses its OWN
/// coordinator slot and notification ids, so summarizing one article never
/// touches / cancels a running "Summarize my For You pile" session, and never
/// raises the For You "Resume summary" pill.
class OnDemandSummarizeStore with WidgetsBindingObserver {
  OnDemandSummarizeStore._();
  static final OnDemandSummarizeStore instance = OnDemandSummarizeStore._();

  /// Total attempts per article (1 initial + 2 retries on transient errors).
  static const int _kMaxAttempts = 3;

  /// Shared FG-service slot id. Distinct from every other feature's slot so
  /// the coordinator's reference counting stays correct.
  static const String _kCoordSlotId = 'news_ondemand_summarize';

  /// Notification id / channel for the "summary ready" completion alert.
  /// 9600 range — clear of notification_service (9000-9100), chat store
  /// (9200-9201), summarize_store (9400-9401) and NewsSummarizeStore (9500).
  static const int _kCompletionNotifId = 9600;
  static const String _kFlnChannelId = 'nexus_news_ondemand_done';
  static const String _kFlnChannelName = 'Article Summary Ready';
  static const String _kFlnChannelDesc =
      'Tells you when an article summary you requested is ready';

  NewsSummarizeService? _service;
  NewsRepository? _repository;
  bool _observerBound = false;
  bool _appInBackground = false;
  bool _slotAcquired = false;

  static FlutterLocalNotificationsPlugin? _flnPlugin;

  /// Per-article state. Absent → [OnDemandStatus.idle].
  final Map<String, OnDemandSummaryState> _state =
      <String, OnDemandSummaryState>{};

  /// UI refresh callbacks keyed by articleId (the open modal subscribes).
  final Map<String, Set<VoidCallback>> _listeners =
      <String, Set<VoidCallback>>{};

  /// Active Dio cancel token per article (for resume-retry / dispose-safety).
  final Map<String, CancelToken> _tokens = <String, CancelToken>{};

  /// Re-run context per in-flight article, so a resume can re-fire it.
  final Map<String, _PendingSummary> _pending = <String, _PendingSummary>{};

  /// Human-readable titles for the foreground-service label.
  final Map<String, String> _titles = <String, String>{};

  // ── Wiring ────────────────────────────────────────────────────────────────

  /// Binds the data dependencies. Safe to call repeatedly (the modal calls it
  /// lazily the first time the user taps "AI Summarize"). Also binds the
  /// app-lifecycle observer exactly once so resume-retry works.
  void init(NewsSummarizeService service, NewsRepository repository) {
    _service = service;
    _repository = repository;
    if (!_observerBound) {
      _observerBound = true;
      WidgetsBinding.instance.addObserver(this);
    }
  }

  OnDemandSummaryState stateOf(String articleId) =>
      _state[articleId] ?? const OnDemandSummaryState.idle();

  void addListener(String articleId, VoidCallback cb) {
    _listeners.putIfAbsent(articleId, () => <VoidCallback>{}).add(cb);
  }

  void removeListener(String articleId, VoidCallback cb) {
    final set = _listeners[articleId];
    if (set == null) return;
    set.remove(cb);
    if (set.isEmpty) _listeners.remove(articleId);
  }

  void _emit(String articleId) {
    final set = _listeners[articleId];
    if (set == null) return;
    for (final cb in set.toList()) {
      cb();
    }
  }

  // ── Public API ──────────────────────────────────────────────────────────

  /// Start (or no-op if already running / ready) an on-demand summary for
  /// [article]. The result lands in `_state[article.id]` and is persisted to
  /// the DB; subscribers are notified on every transition.
  void summarize({required Article article, String? liteModel}) {
    final id = article.id;
    final current = stateOf(id);
    if (current.status == OnDemandStatus.loading) {
      return; // already in flight
    }
    if (current.status == OnDemandStatus.ready &&
        (current.summary?.trim().isNotEmpty ?? false)) {
      return; // already have it
    }

    final cached = article.summaryShort?.trim();
    if (cached != null && cached.isNotEmpty) {
      // Cheap path: a cached summary already exists; surface it without AI.
      _state[id] = OnDemandSummaryState.ready(cached);
      _emit(id);
      return;
    }

    _state[id] = const OnDemandSummaryState.loading();
    _titles[id] = article.title;
    _pending[id] = _PendingSummary(article: article, liteModel: liteModel);
    _emit(id);

    unawaited(_acquireSlot());
    unawaited(_run(id));
  }

  /// Manual retry from the error card.
  void retry(String articleId) {
    final p = _pending[articleId];
    if (p == null) return;
    if (stateOf(articleId).status == OnDemandStatus.loading) return;
    _state[articleId] = const OnDemandSummaryState.loading();
    _emit(articleId);
    unawaited(_acquireSlot());
    unawaited(_run(articleId));
  }

  // ── Worker ────────────────────────────────────────────────────────────────

  Future<void> _run(String id) async {
    final service = _service;
    final repository = _repository;
    final p = _pending[id];
    if (service == null || repository == null || p == null) {
      _state[id] = const OnDemandSummaryState.error(
          'Could not summarize this article right now. Please try again.');
      _emit(id);
      await _finish(id, success: false);
      return;
    }

    final sw = Stopwatch()..start();
    Object? lastError;

    for (var attempt = 1; attempt <= _kMaxAttempts; attempt++) {
      final token = CancelToken();
      _tokens[id] = token;
      try {
        if (attempt > 1) {
          // 500ms → 1s backoff before re-firing on a transient failure.
          final delayMs = 500 * (1 << (attempt - 2));
          await Future<void>.delayed(Duration(milliseconds: delayMs));
        }

        final results = await service.summarizeBatch(
          articles: [p.article],
          liteModel: p.liteModel,
          cancelToken: token,
        );
        final summary = (results[id] ?? '').trim();
        if (summary.isEmpty) {
          throw StateError('Empty summary for $id');
        }

        // Persist FIRST so the result survives even if the UI is gone.
        await repository.setSummaryShort(id, summary);
        _state[id] = OnDemandSummaryState.ready(summary);
        _emit(id);
        sw.stop();
        TLog.i('OnDemandSummarize',
            '✓ id=$id attempt=$attempt ${sw.elapsedMilliseconds}ms');
        await _finish(id, success: true);
        return;
      } catch (e) {
        lastError = e;
        if (_isCancelled(e)) {
          // A resume-retry cancelled this attempt and already re-queued the
          // work, OR the article was explicitly dropped. Either way bail
          // quietly without surfacing an error.
          TLog.d('OnDemandSummarize',
              'id=$id attempt=$attempt cancelled — dropping');
          _tokens.remove(id);
          return;
        }
        final retryable = _isRetryable(e);
        TLog.w(
          'OnDemandSummarize',
          'id=$id attempt $attempt/$_kMaxAttempts failed '
              '(retryable=$retryable): ${e.toString().split('\n').first}',
          error: e,
        );
        if (!retryable || attempt >= _kMaxAttempts) break;
      } finally {
        if (identical(_tokens[id], token)) _tokens.remove(id);
      }
    }

    sw.stop();
    final msg = _userFacingError(lastError);
    TLog.e('OnDemandSummarize',
        '✗ id=$id attempts=$_kMaxAttempts ${sw.elapsedMilliseconds}ms — "$msg"',
        error: lastError);
    _state[id] = OnDemandSummaryState.error(msg);
    _emit(id);
    await _finish(id, success: false);
  }

  /// Releases the in-flight bookkeeping for [id] and, if nothing else is
  /// running, drops the foreground-service slot. Posts a completion
  /// notification when the app was backgrounded during a successful run.
  Future<void> _finish(String id, {required bool success}) async {
    final title = _titles[id];
    _pending.remove(id);
    _tokens.remove(id);

    final stillBusy = _state.values.any((s) => s.isLoading);
    if (!stillBusy) {
      await _releaseSlot();
    } else {
      _updateSlotLabel();
    }

    if (success && _appInBackground) {
      await _showCompletionNotification(title);
    }
    _titles.remove(id);
  }

  // ── Lifecycle: resume-retry ─────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _appInBackground = true;
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    _appInBackground = false;

    // Cancel + re-fire any sockets stuck "loading" through a Doze window so
    // the user gets a finished summary in seconds rather than waiting for
    // stacked TCP timeouts.
    final stuck = <String>[
      for (final entry in _state.entries)
        if (entry.value.isLoading && _pending.containsKey(entry.key))
          entry.key,
    ];
    if (stuck.isEmpty) return;

    TLog.d('OnDemandSummarize',
        'App resumed — refreshing ${stuck.length} stuck summary request(s)');
    for (final id in stuck) {
      _tokens[id]?.cancel('App resumed — re-firing on fresh connection');
      _tokens.remove(id);
    }
    Future<void>.delayed(const Duration(milliseconds: 800), () {
      for (final id in stuck) {
        if (_state[id]?.isLoading == true && _pending.containsKey(id)) {
          unawaited(_run(id));
        }
      }
    });
  }

  // ── Foreground service slot ──────────────────────────────────────────────

  Future<void> _acquireSlot() async {
    if (!PlatformCapabilities.canUseForegroundTask) return;
    if (_slotAcquired) {
      _updateSlotLabel();
      return;
    }
    _slotAcquired = true;
    await BackgroundTaskCoordinator.instance
        .acquire(_kCoordSlotId, label: _slotLabel());
    TLog.i('OnDemandSummarize', 'coord slot acquired');
  }

  Future<void> _releaseSlot() async {
    if (!PlatformCapabilities.canUseForegroundTask) return;
    if (!_slotAcquired) return;
    _slotAcquired = false;
    await BackgroundTaskCoordinator.instance.release(_kCoordSlotId);
    TLog.d('OnDemandSummarize', 'coord slot released');
  }

  void _updateSlotLabel() {
    if (!_slotAcquired) return;
    BackgroundTaskCoordinator.instance.updateLabel(_kCoordSlotId, _slotLabel());
  }

  String _slotLabel() {
    final loadingTitles = <String>[
      for (final entry in _state.entries)
        if (entry.value.isLoading && _titles[entry.key] != null)
          _titles[entry.key]!,
    ];
    if (loadingTitles.length == 1) {
      final t = loadingTitles.first;
      final clipped = t.length > 40 ? '${t.substring(0, 40)}\u2026' : t;
      return '\u2728 Summarizing \u00B7 $clipped';
    }
    if (loadingTitles.length > 1) {
      return '\u2728 Summarizing ${loadingTitles.length} articles';
    }
    return '\u2728 Summarizing article\u2026';
  }

  // ── Completion notification ──────────────────────────────────────────────

  Future<FlutterLocalNotificationsPlugin> _ensureFln() async {
    if (_flnPlugin != null) return _flnPlugin!;
    _flnPlugin = FlutterLocalNotificationsPlugin();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _flnPlugin!
        .initialize(const InitializationSettings(android: android));
    return _flnPlugin!;
  }

  Future<void> _showCompletionNotification(String? articleTitle) async {
    if (!PlatformCapabilities.canUseNotifications) return;
    try {
      final fln = await _ensureFln();
      final t = (articleTitle ?? 'your article');
      final clipped = t.length > 50 ? '${t.substring(0, 50)}\u2026' : t;
      const details = AndroidNotificationDetails(
        _kFlnChannelId,
        _kFlnChannelName,
        channelDescription: _kFlnChannelDesc,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.message,
        color: ui.Color(0xFF8B5CF6),
      );
      await fln.show(
        _kCompletionNotifId,
        '\u2728 Summary ready',
        'Your AI summary of "$clipped" is ready to read.',
        const NotificationDetails(android: details),
        payload: 'news_tab',
      );
    } catch (e, st) {
      TLog.w('OnDemandSummarize', 'completion notification failed: $e',
          error: e, st: st);
    }
  }

  // ── Error classification (mirrors NewsSummarizeStore) ────────────────────

  static bool _isCancelled(Object? e) =>
      e is DioException && e.type == DioExceptionType.cancel;

  static bool _isRetryable(Object? e) {
    if (e is DioException) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
        case DioExceptionType.unknown:
          return true;
        case DioExceptionType.badResponse:
          final code = e.response?.statusCode ?? 0;
          return code >= 500 && code < 600;
        case DioExceptionType.cancel:
        case DioExceptionType.badCertificate:
          return false;
      }
    }
    // StateError("Empty summary") and friends are worth one more shot.
    final s = e?.toString().toLowerCase() ?? '';
    return s.contains('timeout') ||
        s.contains('connection') ||
        s.contains('socket') ||
        s.contains('network') ||
        s.contains('empty summary');
  }

  static String _userFacingError(Object? e) {
    if (e is DioException) {
      final aiErr = AiError.fromDio(e);
      if (aiErr.code == 'MODEL_NOT_FOUND' ||
          aiErr.code == 'INVALID_MODEL' ||
          aiErr.code == 'CONFIG' ||
          aiErr.code == 'BLOCKED') {
        return aiErr.toastMessage;
      }
      final code = e.response?.statusCode;
      if (code != null) {
        return code >= 500
            ? 'Service is busy. Tap to retry.'
            : 'Could not summarize (HTTP $code). Tap to retry.';
      }
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Request timed out. Tap to retry.';
        case DioExceptionType.connectionError:
          return 'No internet connection. Tap to retry.';
        default:
          return 'Could not summarize this article right now. Please try again.';
      }
    }
    return 'Could not summarize this article right now. Please try again.';
  }
}

@immutable
class _PendingSummary {
  const _PendingSummary({required this.article, this.liteModel});
  final Article article;
  final String? liteModel;
}
