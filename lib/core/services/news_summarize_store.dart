import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../data/repositories/news_repository.dart';
import '../../data/services/news_summarize_service.dart';
import '../../domain/entities/news_entities.dart';
import '../platform/platform_capabilities.dart';
import 'background_task_coordinator.dart';
import 'telegram_logger.dart';

/// Status of a single article inside an active summarize session.
enum SummaryStatus { pending, loading, ready, error }

/// Per-article state exposed to the reader UI.
@immutable
class SummaryArticleState {
  const SummaryArticleState({
    required this.status,
    this.summary,
    this.error,
  });

  const SummaryArticleState.pending() : this(status: SummaryStatus.pending);
  const SummaryArticleState.loading() : this(status: SummaryStatus.loading);
  const SummaryArticleState.ready(String summary)
      : this(status: SummaryStatus.ready, summary: summary);
  const SummaryArticleState.error(String error)
      : this(status: SummaryStatus.error, error: error);

  final SummaryStatus status;
  final String? summary;
  final String? error;
}

/// Aggregated progress used by the reader's sticky header and the foreground-
/// service notification.
@immutable
class SummaryProgress {
  const SummaryProgress({
    required this.total,
    required this.ready,
    required this.errored,
    required this.inFlight,
  });

  final int total;
  final int ready;
  final int errored;
  final int inFlight;

  bool get isComplete => ready + errored == total;
  double get fraction => total == 0 ? 1.0 : ready / total;
}

/// Singleton store that drives a "summarize my entire For You pile" session.
///
/// PRODUCTION DESIGN GOALS:
///   - **Background-first.** A session keeps running when the user closes the
///     reader, minimises the app, locks the phone, or turns off the screen.
///     We promote the session to an Android foreground service so the OS
///     cannot put us into Doze / App Standby mid-batch.
///   - **Resilient.** Each batch retries [kMaxAttempts] times with exponential
///     backoff; on app resume any stalled Dio sockets are cancelled and the
///     batch is re-queued with a fresh connection.
///   - **Throttled, observable progress.** A single low-priority foreground
///     notification updates as batches complete (throttled to ≤ 1 update per
///     second so we never spam Android's NotificationManager). On completion
///     the foreground service stops and a high-priority notification
///     announces the result; tapping it deep-links into the reader.
///   - **Cache-aware.** Articles that already carry a [Article.summaryShort]
///     are seeded as `ready` immediately. Successful summaries are persisted
///     to the local DB so re-opening the reader is instant.
///   - **Saved-article safe.** This store never marks anything as read; it
///     just produces summaries and persists them. The reader's "Done" button
///     is the only mutator of read-state and it explicitly excludes saved
///     articles — that contract lives in [NewsRepository.markManyRead] and
///     in the backend `/news/mark-all-read` endpoint.
class NewsSummarizeStore extends ChangeNotifier with WidgetsBindingObserver {
  NewsSummarizeStore._();
  static final NewsSummarizeStore instance = NewsSummarizeStore._();

  /// Articles per HTTP call. Backend hard-caps at 12; we use 10 for headroom.
  static const int kBatchSize = 10;

  /// Max concurrent batches in flight. 4 keeps the backend comfortable while
  /// still letting a 200-article pile finish in ~30 seconds on a healthy
  /// connection (200 / 10 / 4 ≈ 5 round-trips).
  static const int kMaxConcurrent = 4;

  /// Total attempts per batch (1 initial + 2 retries on transient errors).
  static const int kMaxAttempts = 3;

  /// Notification IDs for the foreground service handover and completion.
  /// We deliberately use a different range from `notification_service.dart`
  /// (9000-9100) and `summarize_store.dart` (9400-9401) to avoid collisions.
  static const int _kCompletionNotifId = 9500;

  static const String _kFlnChannelId = 'nexus_news_summarize_done';
  static const String _kFlnChannelName = 'News Summarize Updates';
  static const String _kFlnChannelDesc =
      'Tells you when your For You catch-up summary is ready';

  /// Payload routed through `notificationPayloadStream` when the user taps
  /// the completion notification — the app shell maps this to "open News tab
  /// and re-attach the summary reader".
  static const String kReopenPayload = 'news_summary';

  /// Coordinator slot id used while a session is active. The shared
  /// [BackgroundTaskCoordinator] owns the actual FG service; this store
  /// just registers/releases the slot and updates the label.
  static const String _kCoordSlotId = 'news_summarize';

  // ── Session state ────────────────────────────────────────────────────────

  NewsSummarizeService? _service;
  NewsRepository? _repository;
  String? _liteModel;
  int _sessionId = 0;
  String? _sessionKey;

  /// Articles currently being processed in this session, in their original
  /// reader order. `_state[id]` always exists for every article in this list.
  final List<Article> _articles = <Article>[];
  final Map<String, SummaryArticleState> _state =
      <String, SummaryArticleState>{};

  /// Cancel tokens keyed by batch index for the current session.
  final Map<int, CancelToken> _activeTokens = <int, CancelToken>{};

  /// Batches waiting for an open concurrency slot OR queued for resume retry.
  final Queue<List<Article>> _retryQueue = Queue<List<Article>>();

  /// Concurrency semaphore (counter, no extra package needed).
  int _activeCount = 0;

  /// True between [start] and the moment the last batch finishes / is
  /// cancelled. Reflects "there is non-trivial work happening / queued".
  bool _sessionActive = false;

  bool _appInBackground = false;
  bool _observerBound = false;
  bool _slotAcquired = false;

  /// Set by [requestReaderReopen] when a notification tap arrives faster
  /// than the News screen can mount to listen for it. The News screen
  /// consumes this flag on initState (and on every payload event) so the
  /// reader opens deterministically whether the app was warm-resumed or
  /// cold-started by the notification.
  bool _pendingReaderReopen = false;

  static FlutterLocalNotificationsPlugin? _flnPlugin;

  // ── Public API ───────────────────────────────────────────────────────────

  /// Stable key for the current session (joined article ids hashed). The
  /// reader uses this to detect "is this a fresh session" vs. resuming.
  String? get sessionKey => _sessionKey;

  List<Article> get articles => List.unmodifiable(_articles);

  /// True while a session is processing (in-flight batches or queued
  /// retries). Used by the For You tab to surface a "summary in progress"
  /// pill if the user closes the reader mid-pipeline.
  bool get hasActiveSession => _sessionActive;

  SummaryArticleState statusOf(String id) =>
      _state[id] ?? const SummaryArticleState.pending();

  SummaryProgress get progress {
    var ready = 0;
    var errored = 0;
    var inFlight = 0;
    for (final s in _state.values) {
      switch (s.status) {
        case SummaryStatus.ready:
          ready++;
          break;
        case SummaryStatus.error:
          errored++;
          break;
        case SummaryStatus.loading:
          inFlight++;
          break;
        case SummaryStatus.pending:
          break;
      }
    }
    return SummaryProgress(
      total: _articles.length,
      ready: ready,
      errored: errored,
      inFlight: inFlight,
    );
  }

  /// Starts (or resumes) a summarize session for [articles].
  ///
  /// Articles that already carry a [Article.summaryShort] are seeded as
  /// `ready` immediately — no LLM call needed. The remainder is split into
  /// batches and dispatched up to [kMaxConcurrent] at a time.
  ///
  /// If any pending work exists, this method also promotes the session to a
  /// foreground service so it survives backgrounding / screen-off.
  void start({
    required List<Article> articles,
    required NewsSummarizeService service,
    required NewsRepository repository,
    String? liteModel,
  }) {
    _bindObserver();
    _service = service;
    _repository = repository;
    _liteModel = liteModel;

    // Increment session id so any in-flight batch from a previous session
    // can detect it has been superseded and bail out cleanly.
    _sessionId++;
    final mySession = _sessionId;
    _sessionKey = _computeSessionKey(articles);

    // Tear down anything still running from a previous session.
    _cancelAllActive('Replaced by new session');
    _retryQueue.clear();
    _activeCount = 0;
    _articles
      ..clear()
      ..addAll(articles);
    _state.clear();

    final pending = <Article>[];
    for (final a in articles) {
      final cached = a.summaryShort;
      if (cached != null && cached.trim().isNotEmpty) {
        _state[a.id] = SummaryArticleState.ready(cached);
      } else {
        _state[a.id] = const SummaryArticleState.pending();
        pending.add(a);
      }
    }

    notifyListeners();

    if (pending.isEmpty) {
      _sessionActive = false;
      TLog.i('NewsSummarize',
          'start: all ${articles.length} cached, nothing to do');
      // Make sure no leftover service is hanging around from a prior session.
      unawaited(_stopForegroundService());
      return;
    }

    final batches = _chunk(pending, kBatchSize);
    TLog.i('NewsSummarize',
        'start session#$mySession total=${articles.length} '
        'cached=${articles.length - pending.length} '
        'pending=${pending.length} batches=${batches.length}');

    for (final batch in batches) {
      _retryQueue.add(batch);
    }
    _sessionActive = true;
    unawaited(_startForegroundService());
    _drainQueue(mySession);
  }

  /// Manual retry for a single article whose batch errored. Re-runs ONLY the
  /// affected batch (could include neighbors that errored in the same call).
  void retryArticle(String id) {
    final article = _articles.firstWhere(
      (a) => a.id == id,
      orElse: () => throw StateError('Article $id not in current session'),
    );
    if (_state[id]?.status == SummaryStatus.ready) return;

    _state[id] = const SummaryArticleState.pending();
    _retryQueue.add(<Article>[article]);
    _sessionActive = true;
    notifyListeners();
    if (!_slotAcquired) {
      unawaited(_startForegroundService());
    }
    _drainQueue(_sessionId);
  }

  /// Detaches the reader UI WITHOUT cancelling the session. The summarize
  /// pipeline keeps running in the background and the foreground-service
  /// notification stays visible so the user knows work is still happening.
  ///
  /// Use this for: close (X) button on the reader, accidental swipe-back,
  /// app suspended via task switcher, etc. The user can re-open the reader
  /// from the "Resume summary" pill in News > For You at any time.
  void detachReader() {
    // Nothing to do — listeners are managed via add/removeListener by the
    // reader's State.dispose. We just keep the session alive.
    TLog.d(
      'NewsSummarize',
      'reader detached — session continues '
      '(active=$_sessionActive, fg=$_slotAcquired)',
    );
  }

  /// Marks "the user wants the reader open ASAP" — fired from the
  /// notification-tap handler. The News screen polls and consumes this flag
  /// when it mounts, which avoids a race where the tap arrives before the
  /// screen has subscribed to [notificationPayloadStream].
  void requestReaderReopen() {
    if (_articles.isEmpty) {
      // Nothing to show; ignore (e.g., session was already cancelled).
      return;
    }
    _pendingReaderReopen = true;
    notifyListeners();
  }

  /// Returns `true` exactly once per [requestReaderReopen] call. The News
  /// screen reads this on every rebuild and uses it to push the reader.
  bool consumePendingReopen() {
    if (!_pendingReaderReopen) return false;
    _pendingReaderReopen = false;
    return true;
  }

  /// True if there is an in-flight session OR a recently-completed session
  /// that the user hasn't reopened yet. Drives the "Resume summary" pill on
  /// the For You tab.
  bool get hasReadableSession => _articles.isNotEmpty;

  /// Clears the "completed but not yet reopened" sticky state. Called by
  /// the reader's "Done" handler so the pill disappears once the user has
  /// actually consumed the catch-up summary. Does not touch the in-DB
  /// summary cache — those summaries remain available on individual
  /// articles forever.
  void dismissCompletedSession() {
    if (_sessionActive) return; // Don't accidentally cancel live work.
    if (_articles.isEmpty) return;
    final n = _articles.length;
    _articles.clear();
    _state.clear();
    _sessionKey = null;
    _pendingReaderReopen = false;
    notifyListeners();
    TLog.d('NewsSummarize', 'completed session dismissed (cleared $n cached UI rows)');
  }

  /// Cancels all in-flight batches and clears session state. The persisted
  /// `summaryShort` cache in the DB is NOT touched — re-running [start] with
  /// the same articles will pick the cached results up instantly.
  ///
  /// This is the only path that tears down the foreground service; callers
  /// outside the store should reach for [detachReader] instead.
  void cancelSession() {
    final wasActive = _sessionActive;
    final n = _articles.length;
    final pending = _retryQueue.length;
    _cancelAllActive('Session cancelled by caller');
    _retryQueue.clear();
    _articles.clear();
    _state.clear();
    _sessionKey = null;
    _activeCount = 0;
    _sessionActive = false;
    notifyListeners();
    unawaited(_stopForegroundService());
    // Info-level so an unexpected cancel during a long batch run is visible
    // alongside the batch SUCCESS / FAILURE pairs in the Telegram digest.
    TLog.i(
      'NewsSummarize',
      'session#$_sessionId cancelled (active=$wasActive articles=$n queuedBatches=$pending)',
    );
  }

  // ── Internals ────────────────────────────────────────────────────────────

  void _bindObserver() {
    if (_observerBound) return;
    _observerBound = true;
    WidgetsBinding.instance.addObserver(this);
  }

  void _drainQueue(int mySession) {
    while (_activeCount < kMaxConcurrent && _retryQueue.isNotEmpty) {
      final batch = _retryQueue.removeFirst();
      _activeCount++;
      // Mark the batch's articles as loading so the UI swaps from skeleton
      // shimmer to a "working" state.
      for (final a in batch) {
        _state[a.id] = const SummaryArticleState.loading();
      }
      notifyListeners();
      unawaited(_runBatch(batch, mySession));
    }
    _maybeFinishSession();
  }

  Future<void> _runBatch(List<Article> batch, int mySession) async {
    final batchIndex = _nextBatchKey();
    final service = _service;
    final repository = _repository;
    if (service == null || repository == null) {
      _activeCount = (_activeCount - 1).clamp(0, kMaxConcurrent);
      _maybeFinishSession();
      return;
    }

    final batchSw = Stopwatch()..start();
    Object? lastError;
    for (var attempt = 1; attempt <= kMaxAttempts; attempt++) {
      if (mySession != _sessionId) {
        TLog.d('NewsSummarize',
            'batch #$batchIndex superseded (session#$mySession != #$_sessionId)');
        _activeCount = (_activeCount - 1).clamp(0, kMaxConcurrent);
        _maybeFinishSession();
        return;
      }

      final token = CancelToken();
      _activeTokens[batchIndex] = token;

      try {
        if (attempt > 1) {
          // Exponential backoff: 500 ms → 1 s → 2 s. Fast enough to feel
          // responsive in the UI, slow enough to dodge a brief upstream blip.
          final delayMs = 500 * (1 << (attempt - 2));
          await Future<void>.delayed(Duration(milliseconds: delayMs));
          if (mySession != _sessionId) return;
        }

        final results = await service.summarizeBatch(
          articles: batch,
          liteModel: _liteModel,
          cancelToken: token,
        );

        if (mySession != _sessionId) return;

        // Persist + mark ready. Server guarantees every requested id is
        // present, but we still defensively handle gaps.
        var ready = 0;
        var missing = 0;
        for (final a in batch) {
          final summary = results[a.id];
          if (summary != null && summary.trim().isNotEmpty) {
            _state[a.id] = SummaryArticleState.ready(summary);
            unawaited(repository.setSummaryShort(a.id, summary));
            ready++;
          } else {
            _state[a.id] = const SummaryArticleState.error(
                'Could not generate summary');
            missing++;
          }
        }
        notifyListeners();
        _maybeUpdateForegroundNotification();
        batchSw.stop();
        // Per-batch success log so the Telegram digest shows the
        // distribution of batch sizes / latencies / partial misses in
        // production. Throttled implicitly by batch count (~25 per 200
        // articles), so well under the logger's queue cap.
        TLog.i(
          'NewsSummarize',
          'batch #$batchIndex ✓ session#$mySession size=${batch.length} ready=$ready missing=$missing attempt=$attempt ${batchSw.elapsedMilliseconds}ms',
        );
        return;
      } catch (e) {
        lastError = e;

        if (_isCancelled(e)) {
          // Either the user closed the reader explicitly OR the lifecycle
          // handler proactively cancelled because we resumed from a long
          // background. In the latter case the resume handler has already
          // re-queued this batch; in the former we drop quietly.
          TLog.d(
            'NewsSummarize',
            'batch #$batchIndex cancelled mid-flight (session#$mySession attempt=$attempt) — dropping',
          );
          _activeCount = (_activeCount - 1).clamp(0, kMaxConcurrent);
          _activeTokens.remove(batchIndex);
          _maybeFinishSession();
          return;
        }

        final retryable = _isRetryable(e);
        TLog.w('NewsSummarize',
            'batch #$batchIndex attempt $attempt/$kMaxAttempts failed (retryable=$retryable): ${e.toString().split('\n').first}',
            error: e);
        if (!retryable || attempt >= kMaxAttempts) break;
      } finally {
        _activeTokens.remove(batchIndex);
      }
    }

    // Final failure — surface error to every article in the batch with a
    // friendly message; the UI exposes a tap-to-retry pill.
    batchSw.stop();
    final msg = _userFacingError(lastError);
    // Error-level so this flushes to Telegram immediately. Includes the
    // batch shape so on-call can correlate with backend `/summarize-articles-batch`
    // logs from the same minute.
    TLog.e(
      'NewsSummarize',
      'batch #$batchIndex ✗ session#$mySession size=${batch.length} attempts=$kMaxAttempts ${batchSw.elapsedMilliseconds}ms — surfacing "$msg" to UI',
      error: lastError,
    );
    if (mySession == _sessionId) {
      for (final a in batch) {
        _state[a.id] = SummaryArticleState.error(msg);
      }
      notifyListeners();
      _maybeUpdateForegroundNotification();
    }

    _activeCount = (_activeCount - 1).clamp(0, kMaxConcurrent);
    _drainQueue(mySession);
  }

  void _cancelAllActive(String reason) {
    for (final t in _activeTokens.values) {
      if (!t.isCancelled) t.cancel(reason);
    }
    _activeTokens.clear();
  }

  int _batchKeyCounter = 0;
  int _nextBatchKey() => _batchKeyCounter++;

  static List<List<Article>> _chunk(List<Article> source, int size) {
    final out = <List<Article>>[];
    for (var i = 0; i < source.length; i += size) {
      out.add(source.sublist(i, (i + size).clamp(0, source.length)));
    }
    return out;
  }

  static String _computeSessionKey(List<Article> articles) {
    final ids = articles.map((a) => a.id).toList()..sort();
    return ids.join(',').hashCode.toString();
  }

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
    final s = e?.toString().toLowerCase() ?? '';
    return s.contains('timeout') ||
        s.contains('connection') ||
        s.contains('socket') ||
        s.contains('network');
  }

  static String _userFacingError(Object? e) {
    if (e is DioException) {
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
          return 'Could not summarize. Tap to retry.';
      }
    }
    return 'Could not summarize. Tap to retry.';
  }

  // ── Lifecycle ────────────────────────────────────────────────────────────
  //
  // The foreground service does the heavy lifting of keeping us alive across
  // backgrounding. The lifecycle handler is left in place to do ONE thing:
  // when the user comes back to the app after a long Doze window, in-flight
  // Dio sockets may be in a "happy path retry" loop on dead connections.
  // Cancelling them and re-queueing for a fresh connection on resume gets
  // the user to a finished session in seconds instead of waiting ~2 min for
  // stacked TCP retries to give up.

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (!_appInBackground && _activeCount > 0) {
        _appInBackground = true;
        TLog.d('NewsSummarize',
            'App → BACKGROUND with $_activeCount active batch(es) (foreground service handles wakelock)');
      }
      return;
    }

    if (state != AppLifecycleState.resumed) return;
    final wasBackground = _appInBackground;
    _appInBackground = false;
    if (!wasBackground || !_sessionActive || _activeCount == 0) return;

    TLog.d('NewsSummarize',
        'App → FOREGROUND, refreshing potentially-stuck batches');

    // Build the "stuck" list from articles still flagged loading. Those
    // sockets are almost certainly dead after a long Doze; cancelling and
    // requeueing with a fresh connection beats waiting ~2 minutes for
    // stacked TCP retries to give up.
    final stuckArticles = <Article>[
      for (final a in _articles)
        if (_state[a.id]?.status == SummaryStatus.loading) a,
    ];
    if (stuckArticles.isEmpty) {
      _cancelAllActive('App resumed — no stuck batches');
      return;
    }

    _cancelAllActive('App resumed — re-queueing for fresh connection');
    Future<void>.delayed(const Duration(milliseconds: 800), () {
      // Re-chunk so we don't waste round-trips on single-article batches.
      final regrouped = _chunk(stuckArticles, kBatchSize);
      for (final b in regrouped) {
        _retryQueue.add(b);
      }
      _activeCount = 0;
      _drainQueue(_sessionId);
    });
  }

  // ── Foreground service / notification ────────────────────────────────────
  //
  // Foreground-service ownership is delegated to
  // [BackgroundTaskCoordinator] so that this feature plays nicely with
  // every other long-running AI task (online search, URL summarize,
  // follow-up Q&A, expense OCR + smart-parse). The coordinator handles
  // start/stop and throttled label updates; we just acquire/release a
  // single named slot.

  Future<void> _startForegroundService() async {
    if (!PlatformCapabilities.canUseForegroundTask) return;
    if (_slotAcquired) return;
    _slotAcquired = true;
    final p = progress;
    await BackgroundTaskCoordinator.instance.acquire(
      _kCoordSlotId,
      label: '\u2728 Summarizing news \u00B7 ${_buildNotificationBody(p)}',
    );
    TLog.i('NewsSummarize',
        'coord slot acquired (total=${p.total})');
  }

  Future<void> _stopForegroundService() async {
    if (!PlatformCapabilities.canUseForegroundTask) return;
    if (!_slotAcquired) return;
    _slotAcquired = false;
    await BackgroundTaskCoordinator.instance.release(_kCoordSlotId);
    TLog.d('NewsSummarize', 'coord slot released');
  }

  void _maybeUpdateForegroundNotification() {
    if (!_slotAcquired) return;
    final p = progress;
    BackgroundTaskCoordinator.instance.updateLabel(
      _kCoordSlotId,
      '\u2728 Summarizing news \u00B7 ${_buildNotificationBody(p)}',
    );
  }

  String _buildNotificationBody(SummaryProgress p) {
    if (p.total == 0) return 'Working\u2026';
    final pct = (p.fraction * 100).clamp(0, 100).round();
    final inFlightStr = p.inFlight > 0 ? ' \u00B7 ${p.inFlight} in flight' : '';
    final errStr = p.errored > 0 ? ' \u00B7 ${p.errored} retry' : '';
    return '${p.ready} / ${p.total} ready ($pct%)$inFlightStr$errStr';
  }

  void _maybeFinishSession() {
    if (_activeCount > 0 || _retryQueue.isNotEmpty) return;
    if (!_sessionActive) return;
    _sessionActive = false;
    final p = progress;
    TLog.i('NewsSummarize',
        'session complete: ready=${p.ready} errored=${p.errored} total=${p.total}');
    unawaited(_finishSessionAsync(p));
  }

  Future<void> _finishSessionAsync(SummaryProgress p) async {
    await _stopForegroundService();
    if (p.total > 0) {
      await _showCompletionNotification(p);
    }
  }

  // ── Completion notification (high priority, deep-link payload) ──────────

  Future<FlutterLocalNotificationsPlugin> _ensureFln() async {
    if (_flnPlugin != null) return _flnPlugin!;
    _flnPlugin = FlutterLocalNotificationsPlugin();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _flnPlugin!
        .initialize(const InitializationSettings(android: android));
    return _flnPlugin!;
  }

  Future<void> _showCompletionNotification(SummaryProgress p) async {
    if (!PlatformCapabilities.canUseNotifications) return;
    try {
      final fln = await _ensureFln();
      final body = p.errored == 0
          ? 'All ${p.ready} summaries are ready. Tap to read.'
          : '${p.ready} ready \u00B7 ${p.errored} could not be summarized. Tap to read.';
      const details = AndroidNotificationDetails(
        _kFlnChannelId,
        _kFlnChannelName,
        channelDescription: _kFlnChannelDesc,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.message,
        color: ui.Color(0xFF8B5CF6),
        ledColor: ui.Color(0xFF8B5CF6),
        ledOnMs: 1000,
        ledOffMs: 500,
        enableLights: true,
      );
      await fln.show(
        _kCompletionNotifId,
        '\u2728 Your catch-up summary is ready',
        body,
        const NotificationDetails(android: details),
        payload: kReopenPayload,
      );
      TLog.i(
        'NewsSummarize',
        'completion notification posted (ready=${p.ready} errored=${p.errored} total=${p.total})',
      );
    } catch (e, st) {
      TLog.w('NewsSummarize', 'completion notification failed: $e',
          error: e, st: st);
    }
  }

  // No dispose: this is a process-lifetime singleton. The observer stays
  // bound for the life of the app so the resume handler always fires.
}
