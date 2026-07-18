import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/injection.dart';
import '../../../core/services/telegram_logger.dart';
import '../../../domain/entities/news_entities.dart';
import '../../../data/repositories/news_repository.dart';

final newsControllerProvider =
    StateNotifierProvider<NewsController, AsyncValue<List<Article>>>((ref) {
  final controller = NewsController(ref.read(newsRepositoryProvider));
  controller.bootstrap();
  return controller;
});

class NewsController extends StateNotifier<AsyncValue<List<Article>>> {
  NewsController(this._repository) : super(const AsyncValue.loading()) {
    _subscription = _repository.watchArticles().listen(
      (articles) {
        if (articles.isEmpty && state.isLoading) {
          return;
        }
        state = AsyncValue.data(articles);
      },
      onError: (Object error, StackTrace stackTrace) {
        TLog.e('NewsCtrl', 'Article stream error', error: error);
        if ((state.valueOrNull ?? const <Article>[]).isEmpty) {
          state = AsyncValue.error(error, stackTrace);
        }
      },
    );
  }

  final NewsRepository _repository;
  StreamSubscription<List<Article>>? _subscription;

  Future<void> bootstrap() async {
    final cachedArticles = await _repository.watchArticles().first;
    if (cachedArticles.isNotEmpty && state.isLoading) {
      state = AsyncValue.data(cachedArticles);
    }

    try {
      await _repository.syncNews();
      TLog.i('NewsCtrl', 'News sync completed');
      if (state.isLoading) {
        state = AsyncValue.data(await _repository.watchArticles().first);
      }
    } catch (e, st) {
      TLog.w('NewsCtrl', 'News sync failed: $e', error: e);
      if ((state.valueOrNull ?? const <Article>[]).isEmpty) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  /// Returns the number of new articles fetched.
  Future<int> refresh() async {
    try {
      return await _repository.syncNews(refreshRemote: true);
    } catch (e) {
      TLog.w('NewsCtrl', 'News refresh failed: $e', error: e);
      rethrow;
    }
  }

  Future<void> toggleSaved(String id) {
    return _repository.toggleSaved(id);
  }

  Future<void> markRead(String id) {
    return _repository.markRead(id);
  }

  /// Permanently removes an article (local row + server delete + tombstone).
  /// Used by the Saved-tab trash button and the Movies/General swipe-delete.
  Future<void> deleteArticle(String id) {
    return _repository.deleteArticle(id);
  }

  /// Easter-egg "nuke": deletes EVERY article including saved ones, locally
  /// and on the server. Returns the local count removed + server confirmation.
  Future<({int removed, bool serverOk})> clearAllNews() {
    return _repository.clearAllNews();
  }

  /// Bulk mark-as-read for the For You "Clear All" / summary "Done" flows.
  /// The repository updates local DB synchronously and fires a best-effort
  /// remote bulk request in the background — this future resolves once the
  /// local update is committed.
  Future<int> markManyRead(List<String> ids) {
    return _repository.markManyRead(ids);
  }

  Future<Article?> loadArticle(String id) async {
    return await _repository.fetchArticleDetail(id) ??
        await _repository.getArticle(id);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
