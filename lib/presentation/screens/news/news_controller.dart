import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/app_token_store.dart';
import '../../../core/di/injection.dart';
import '../../../core/services/telegram_logger.dart';
import '../../../domain/entities/news_entities.dart';
import '../../../data/repositories/news_repository.dart';
import '../../../data/services/narration_audio_handler.dart';

final newsControllerProvider =
    StateNotifierProvider<NewsController, AsyncValue<List<Article>>>((ref) {
  final controller = NewsController(ref.read(newsRepositoryProvider));
  unawaited(controller.bootstrap());
  return controller;
});

class NewsController extends StateNotifier<AsyncValue<List<Article>>> {
  NewsController(this._repository) : super(const AsyncValue.loading()) {
    _subscription = _repository.watchArticles().listen(
      (articles) {
        if (!mounted) return;
        // Empty Drift emissions before the first successful (or exhausted)
        // sync must not paint "No articles in this category". That is what
        // made every News chip look dead until the user pulled to refresh:
        // GET /news raced the post-first-frame JWT, 401'd, then the empty
        // watch replaced loading/error with data([]).
        //
        // Once the feed has rows (or bootstrap finished), empty is real —
        // last swipe-delete, Clear All, nuke — and must paint.
        final current = state.valueOrNull ?? const <Article>[];
        if (articles.isEmpty &&
            current.isEmpty &&
            (!_bootstrapDone || state.hasError)) {
          return;
        }
        state = AsyncValue.data(articles);
      },
      onError: (Object error, StackTrace stackTrace) {
        TLog.e('NewsCtrl', 'Article stream error', error: error);
        if (!mounted) return;
        if ((state.valueOrNull ?? const <Article>[]).isEmpty) {
          state = AsyncValue.error(error, stackTrace);
        }
      },
    );
  }

  final NewsRepository _repository;
  StreamSubscription<List<Article>>? _subscription;
  bool _bootstrapDone = false;

  /// How long [bootstrap] waits for [AppTokenStore.markStartupReady].
  @visibleForTesting
  static Duration authGateTimeout = const Duration(seconds: 12);

  /// Backoff between [syncNews] attempts after a failed GET (401 / offline).
  @visibleForTesting
  static List<Duration> syncRetryDelays = const <Duration>[
    Duration.zero,
    Duration(milliseconds: 350),
    Duration(milliseconds: 900),
  ];

  /// After the fast GET, also POST /news/refresh so the feed is current
  /// without the user pulling down. Tests that seed a fake API turn this off.
  @visibleForTesting
  static bool autoRemoteRefresh = true;

  /// Skip a second RSS refresh if one just finished.
  @visibleForTesting
  static Duration minAutoRefreshInterval = const Duration(seconds: 90);

  /// Even a forced refresh (News tab tap / resume) waits this long so
  /// bouncing between tabs cannot stampede `/news/refresh`.
  @visibleForTesting
  static Duration minForcedRefreshInterval = const Duration(seconds: 20);

  DateTime? _lastRemoteRefresh;
  Future<void>? _remoteRefreshOp;

  @visibleForTesting
  static void debugResetPolicy() {
    authGateTimeout = const Duration(seconds: 12);
    syncRetryDelays = const <Duration>[
      Duration.zero,
      Duration(milliseconds: 350),
      Duration(milliseconds: 900),
    ];
    autoRemoteRefresh = true;
    minAutoRefreshInterval = const Duration(seconds: 90);
    minForcedRefreshInterval = const Duration(seconds: 20);
  }

  Future<void> bootstrap() async {
    await _paintCache();
    await _awaitAuthGate();
    if (!mounted) return;
    await _syncWithRetry(refreshRemote: false);
    if (autoRemoteRefresh) {
      unawaited(ensureFresh(force: true));
    }
  }

  /// Cheap GET if the feed is empty, then a background RSS refresh so
  /// opening News always shows the latest articles without requiring
  /// pull-to-refresh. Pull-to-refresh remains a manual secondary path
  /// via [refresh].
  ///
  /// [force] skips the 90s quiet window (used when the user opens the News
  /// tab or the app resumes). Tests set [autoRemoteRefresh] to false so
  /// this never POSTs `/news/refresh`, even when [force] is true.
  Future<void> ensureFresh({bool force = false}) async {
    await _awaitAuthGate();
    if (!mounted) return;
    final hasRows = (state.valueOrNull ?? const <Article>[]).isNotEmpty;
    if (!hasRows) {
      await _syncWithRetry(refreshRemote: false);
    }
    if (!autoRemoteRefresh) return;
    final minInterval =
        force ? minForcedRefreshInterval : minAutoRefreshInterval;
    if (_lastRemoteRefresh != null &&
        DateTime.now().difference(_lastRemoteRefresh!) < minInterval) {
      return;
    }
    final inFlight = _remoteRefreshOp;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    final op = _quietRemoteRefresh();
    _remoteRefreshOp = op;
    try {
      await op;
    } finally {
      if (identical(_remoteRefreshOp, op)) {
        _remoteRefreshOp = null;
      }
    }
  }

  /// Returns the number of new articles fetched.
  Future<int> refresh() async {
    await _awaitAuthGate();
    if (!mounted) return 0;
    try {
      final newCount = await _repository.syncNews(refreshRemote: true);
      _lastRemoteRefresh = DateTime.now();
      await _publishSnapshot();
      _bootstrapDone = true;
      return newCount;
    } catch (e) {
      TLog.w('NewsCtrl', 'News refresh failed: $e', error: e);
      rethrow;
    }
  }

  Future<void> _quietRemoteRefresh() async {
    try {
      final newCount = await _repository.syncNews(refreshRemote: true);
      if (!mounted) return;
      _lastRemoteRefresh = DateTime.now();
      await _publishSnapshot();
      if (!mounted) return;
      TLog.i(
        'NewsCtrl',
        'Background RSS refresh new=$newCount total=${state.valueOrNull?.length ?? 0}',
      );
    } catch (e) {
      if (!mounted) return;
      TLog.w('NewsCtrl', 'Background RSS refresh failed: $e', error: e);
    }
  }

  Future<void> toggleSaved(String id) {
    return _repository.toggleSaved(id);
  }

  Future<void> markRead(String id) {
    return _repository.markRead(id);
  }

  /// Permanently removes an article (local row + server delete + tombstone).
  /// Used by the Saved-tab trash button and For You swipe-to-delete
  /// (All, AI News, Finance, Movies, General).
  Future<void> deleteArticle(String id) {
    unawaited(dropNarrationFor([id]));
    return _repository.deleteArticle(id);
  }

  /// Easter-egg "nuke": deletes EVERY article including saved ones, locally
  /// and on the server. Returns the local count removed + server confirmation.
  Future<({int removed, bool serverOk})> clearAllNews() {
    final ids = [for (final a in state.valueOrNull ?? const <Article>[]) a.id];
    unawaited(dropNarrationFor(ids));
    return _repository.clearAllNews();
  }

  /// Bulk mark-as-read for the For You "Clear All" / summary "Done" flows.
  /// The repository updates local DB synchronously and fires a best-effort
  /// remote bulk request in the background — this future resolves once the
  /// local update is committed. Audio drop happens in the repository after
  /// the saved-row filter so Saved-tab audio is never tombstoned.
  Future<int> markManyRead(List<String> ids) {
    return _repository.markManyRead(ids);
  }

  Future<Article?> loadArticle(String id) async {
    return await _repository.fetchArticleDetail(id) ??
        await _repository.getArticle(id);
  }

  Future<void> _paintCache() async {
    try {
      final cached = await _repository.getArticles();
      if (!mounted) return;
      if (cached.isNotEmpty) {
        state = AsyncValue.data(cached);
        TLog.i('NewsCtrl', 'Painted ${cached.length} cached article(s)');
      }
    } catch (e) {
      TLog.w('NewsCtrl', 'Cache read failed: $e', error: e);
    }
  }

  Future<void> _awaitAuthGate() async {
    if (AppTokenStore.instance.hasToken &&
        AppTokenStore.instance.refresher != null) {
      return;
    }
    if (AppTokenStore.instance.isStartupReady) return;
    final timeout = authGateTimeout;
    if (timeout <= Duration.zero) return;
    try {
      await AppTokenStore.instance.startupReady.timeout(timeout);
    } on TimeoutException {
      TLog.w('NewsCtrl', 'Auth gate timed out — syncing news anyway');
    }
  }

  Future<void> _syncWithRetry({required bool refreshRemote}) async {
    Object? lastError;
    StackTrace? lastSt;
    final delays = syncRetryDelays;
    for (var i = 0; i < delays.length; i++) {
      final wait = delays[i];
      if (wait > Duration.zero) {
        await Future<void>.delayed(wait);
      }
      if (!mounted) return;
      try {
        final newCount =
            await _repository.syncNews(refreshRemote: refreshRemote);
        await _publishSnapshot();
        _bootstrapDone = true;
        TLog.i(
          'NewsCtrl',
          'News sync completed new=$newCount total=${state.valueOrNull?.length ?? 0}',
        );
        return;
      } catch (e, st) {
        lastError = e;
        lastSt = st;
        TLog.w(
          'NewsCtrl',
          'News sync attempt ${i + 1}/${delays.length} failed: $e',
          error: e,
        );
      }
    }
    _bootstrapDone = true;
    if (!mounted) return;
    if ((state.valueOrNull ?? const <Article>[]).isEmpty) {
      state = AsyncValue.error(
        lastError ?? StateError('News sync failed'),
        lastSt ?? StackTrace.current,
      );
    }
  }

  Future<void> _publishSnapshot() async {
    if (!mounted) return;
    final latest = await _repository.getArticles();
    if (!mounted) return;
    state = AsyncValue.data(latest);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
