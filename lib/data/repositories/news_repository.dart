import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/services/telegram_logger.dart';
import '../../domain/entities/news_entities.dart' as domain;
import '../../presentation/screens/news/article_followup_sheet.dart';
import '../local/database/app_database.dart' as db;

class NewsRepository {
  NewsRepository(this._db, this._apiClient);

  final db.AppDatabase _db;
  final ApiClient _apiClient;

  Stream<List<domain.Article>> watchArticles() {
    return _db.select(_db.newsArticles).watch().map((rows) {
      final articles = rows.map(_rowToArticle).toList()..sort(_compareArticles);
      return articles;
    });
  }

  /// Returns the number of NEW articles that weren't in the local DB before.
  Future<int> syncNews({bool refreshRemote = false}) async {
    try {
      // Snapshot local IDs and fetch server data in parallel
      late final List<db.NewsArticle> localRowsBefore;
      late final List<Map<String, dynamic>> articles;

      if (refreshRemote) {
        // Refresh response already contains updated articles — skip separate GET
        final results = await Future.wait([
          _db.select(_db.newsArticles).get(),
          _apiClient.post<Object?>(
            ApiEndpoints.newsRefresh,
            options: Options(receiveTimeout: const Duration(seconds: 60)),
          ),
        ]);
        localRowsBefore = results[0] as List<db.NewsArticle>;
        final refreshData = _asMap((results[1] as Response).data);
        articles = _asMapList(refreshData?['articles']);
      } else {
        final results = await Future.wait([
          _db.select(_db.newsArticles).get(),
          _apiClient.get<Object?>(ApiEndpoints.news),
        ]);
        localRowsBefore = results[0] as List<db.NewsArticle>;
        final data = _asMap((results[1] as Response).data);
        articles = _asMapList(data?['articles']);
      }

      final localIdsBefore = <String>{for (final r in localRowsBefore) r.id};

      final serverIds = <String>{
        for (final a in articles)
          if (_stringOrNull(a['id']) case final id? when id.isNotEmpty) id,
      };
      final newCount = serverIds.difference(localIdsBefore).length;

      // Upsert and stale cleanup can overlap
      final upsertFuture = _upsertArticles(articles);

      if (serverIds.isNotEmpty) {
        final staleIds = localRowsBefore
            .where((r) => !serverIds.contains(r.id) && !r.isSaved)
            .map((r) => r.id)
            .toList();
        if (staleIds.isNotEmpty) {
          await upsertFuture;
          await (_db.delete(_db.newsArticles)
                ..where((t) => t.id.isIn(staleIds)))
              .go();
          for (final id in staleIds) {
            ArticleFollowUpStore.instance.clear(id);
          }
          TLog.d('NewsRepo', 'Removed ${staleIds.length} stale local articles');
        } else {
          await upsertFuture;
        }
      } else {
        await upsertFuture;
      }

      return newCount;
    } catch (e) {
      TLog.w('NewsRepo', 'syncNews failed: $e', error: e);
      rethrow;
    }
  }

  Future<domain.Article?> fetchArticleDetail(String id) async {
    try {
      final response = await _apiClient.get<Object?>(ApiEndpoints.article(id));
      final data = _asMap(response.data);
      final article = _asMap(data?['article']);
      if (article != null) {
        await _upsertArticles([article]);
      }
    } catch (e) {
      TLog.w('NewsRepo', 'fetchArticleDetail failed (using cached): $e', error: e);
    }
    return getArticle(id);
  }

  Future<domain.Article?> getArticle(String id) async {
    final row = await (_db.select(_db.newsArticles)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _rowToArticle(row);
  }

  Future<void> toggleSaved(String id) async {
    final row = await (_db.select(_db.newsArticles)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return;

    final newValue = !row.isSaved;
    await (_db.update(_db.newsArticles)..where((t) => t.id.equals(id)))
        .write(db.NewsArticlesCompanion(isSaved: Value(newValue)));

    try {
      final response =
          await _apiClient.post<Object?>(ApiEndpoints.articleSave(id));
      final data = _asMap(response.data);
      final article = _asMap(data?['article']);
      if (article != null) {
        await _upsertArticles([article]);
      }
    } catch (e) {
      TLog.w('NewsRepo', 'toggleSaved API failed (local toggle kept): $e', error: e);
    }
  }

  Future<void> markRead(String id) async {
    await (_db.update(_db.newsArticles)..where((t) => t.id.equals(id)))
        .write(const db.NewsArticlesCompanion(isRead: Value(true)));

    try {
      final response =
          await _apiClient.post<Object?>(ApiEndpoints.articleRead(id));
      final data = _asMap(response.data);
      final article = _asMap(data?['article']);
      if (article != null) {
        await _upsertArticles([article]);
      }
    } catch (e) {
      TLog.w('NewsRepo', 'markRead API failed (local update kept): $e', error: e);
    }
  }

  /// Bulk mark-as-read for the For You "Clear All" / summary "Done" flows.
  ///
  /// Local DB is updated first (single batched UPDATE) so the UI reacts
  /// instantly. The server bulk endpoint is fire-and-forget — a transient
  /// network failure must not block the user's catch-up flow because the
  /// local state is already correct and will reconcile on the next
  /// `syncNews()` round-trip. Saved articles are filtered server-side
  /// (`saved=FALSE` guard) and we mirror that filter locally.
  Future<int> markManyRead(List<String> ids) async {
    if (ids.isEmpty) return 0;

    final updated = await (_db.update(_db.newsArticles)
          ..where((t) => t.id.isIn(ids) & t.isSaved.equals(false)))
        .write(const db.NewsArticlesCompanion(isRead: Value(true)));

    TLog.d('NewsRepo', 'markManyRead local ✓ requested=${ids.length} updated=$updated');

    unawaited(() async {
      try {
        await _apiClient.post<Object?>(
          ApiEndpoints.newsMarkAllRead,
          data: <String, dynamic>{'ids': ids},
          options: Options(receiveTimeout: const Duration(seconds: 30)),
        );
        TLog.i('NewsRepo', 'markManyRead remote ✓ ${ids.length} ids');
      } catch (e) {
        TLog.w('NewsRepo',
            'markManyRead remote failed (local already updated): $e',
            error: e);
      }
    }());

    return updated;
  }

  /// Persists an AI-generated quick summary for the For You "Summarize"
  /// flow. Local-only (cache); the server has no notion of this — it would
  /// just regenerate on the next call. Gracefully no-ops if [summary] is
  /// empty.
  Future<void> setSummaryShort(String id, String summary) async {
    if (summary.trim().isEmpty) return;
    await (_db.update(_db.newsArticles)..where((t) => t.id.equals(id)))
        .write(db.NewsArticlesCompanion(summaryShort: Value(summary)));
  }

  Future<void> _upsertArticles(List<Map<String, dynamic>> apiArticles) async {
    if (apiArticles.isEmpty) {
      return;
    }

    final existingRows = await _db.select(_db.newsArticles).get();
    final existingById = {for (final row in existingRows) row.id: row};

    await _db.batch((batch) {
      for (final apiArticle in apiArticles) {
        final id = _stringOrNull(apiArticle['id']);
        if (id == null || id.isEmpty) {
          continue;
        }

        final companion = _apiArticleToCompanion(
          apiArticle,
          existingRow: existingById[id],
        );
        batch.insert(
          _db.newsArticles,
          companion,
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  db.NewsArticlesCompanion _apiArticleToCompanion(
    Map<String, dynamic> apiArticle, {
    db.NewsArticle? existingRow,
  }) {
    final existingMeta = existingRow == null
        ? <String, dynamic>{}
        : _decodeMeta(existingRow.blocksJson);
    final existingBlocks = _extractBlocksPayload(existingMeta);
    final incomingBlocks =
        _asList(apiArticle['blocks']) ?? _asList(apiArticle['content']);
    final summaryMarkdown = _stringOrNull(apiArticle['summaryMarkdown']) ??
        _stringOrNull(existingMeta['summaryMarkdown']);
    final originalUrl = _stringOrNull(apiArticle['originalUrl']) ??
        _stringOrNull(existingMeta['originalUrl']);
    final tag =
        _stringOrNull(apiArticle['tag']) ?? _stringOrNull(existingMeta['tag']);
    final timeAgo = _stringOrNull(apiArticle['timeAgo']) ??
        _stringOrNull(existingMeta['timeAgo']);
    final publishedAt = _stringOrNull(apiArticle['publishedAt']) ??
        _stringOrNull(existingMeta['publishedAt']);
    final isFeatured =
        _boolOr(apiArticle['isFeatured'], existingMeta['isFeatured'] == true);

    final meta = <String, dynamic>{
      if (summaryMarkdown != null && summaryMarkdown.isNotEmpty)
        'summaryMarkdown': summaryMarkdown,
      if (originalUrl != null && originalUrl.isNotEmpty)
        'originalUrl': originalUrl,
      if (tag != null && tag.isNotEmpty) 'tag': tag,
      if (timeAgo != null && timeAgo.isNotEmpty) 'timeAgo': timeAgo,
      if (publishedAt != null && publishedAt.isNotEmpty)
        'publishedAt': publishedAt,
      'isFeatured': isFeatured,
      'blocks': incomingBlocks ?? existingBlocks,
    };

    // Preserve the locally-cached AI quick summary across server upserts.
    // The server is unaware of this field so we always carry over whatever
    // we already have (NULL stays NULL until the user runs Summarize).
    final preservedSummaryShort = existingRow?.summaryShort;

    return db.NewsArticlesCompanion.insert(
      id: _stringOrNull(apiArticle['id']) ?? existingRow?.id ?? '',
      title: _stringOrNull(apiArticle['title']) ??
          existingRow?.title ??
          'Untitled',
      excerpt: _stringOrNull(apiArticle['excerpt']) ??
          existingRow?.excerpt ??
          'New article available.',
      source: _stringOrNull(apiArticle['source']) ??
          existingRow?.source ??
          'Source',
      category: _stringOrNull(apiArticle['category']) ??
          existingRow?.category ??
          'Technology',
      imageUrl:
          _stringOrNull(apiArticle['imageUrl']) ?? existingRow?.imageUrl ?? '',
      readTime: _intOr(apiArticle['readTime'], existingRow?.readTime ?? 1),
      date: _stringOrNull(apiArticle['date']) ?? existingRow?.date ?? '',
      blocksJson: jsonEncode(meta),
      isSaved:
          Value(_boolOr(apiArticle['isSaved'], existingRow?.isSaved ?? false)),
      isRead:
          Value(_boolOr(apiArticle['isRead'], existingRow?.isRead ?? false)),
      summaryShort: preservedSummaryShort == null
          ? const Value.absent()
          : Value(preservedSummaryShort),
    );
  }

  domain.Article _rowToArticle(db.NewsArticle row) {
    final meta = _decodeMeta(row.blocksJson);
    final publishedAtRaw = _stringOrNull(meta['publishedAt']);

    return domain.Article(
      id: row.id,
      title: row.title,
      excerpt: row.excerpt,
      source: row.source,
      category: row.category,
      imageUrl: row.imageUrl,
      readTime: row.readTime,
      date: row.date,
      blocks: _parseBlocks(meta['blocks']),
      summaryMarkdown: _stringOrNull(meta['summaryMarkdown']),
      summaryShort: _stringOrNull(row.summaryShort),
      originalUrl: _stringOrNull(meta['originalUrl']),
      tag: _stringOrNull(meta['tag']),
      timeAgo: _stringOrNull(meta['timeAgo']),
      isFeatured: meta['isFeatured'] == true,
      publishedAt:
          publishedAtRaw == null ? null : DateTime.tryParse(publishedAtRaw),
      isSaved: row.isSaved,
      isRead: row.isRead,
    );
  }

  Map<String, dynamic> _decodeMeta(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      if (decoded is List) {
        return <String, dynamic>{'blocks': decoded};
      }
    } catch (e) {
      TLog.w('NewsRepo', 'Failed to decode meta JSON: $e');
    }
    return <String, dynamic>{};
  }

  List<dynamic> _extractBlocksPayload(Map<String, dynamic> meta) {
    final value = meta['blocks'];
    return _asList(value) ?? const <dynamic>[];
  }

  List<domain.ArticleBlock> _parseBlocks(Object? rawBlocks) {
    final rawList = _asList(rawBlocks);
    if (rawList == null || rawList.isEmpty) {
      return const <domain.ArticleBlock>[];
    }

    final blocks = <domain.ArticleBlock>[];
    for (final item in rawList) {
      final map = _asMap(item);
      if (map == null) {
        continue;
      }

      final type = _stringOrNull(map['type']) ?? 'paragraph';
      if (type == 'stat') {
        final statItems = _asList(map['items']);
        if (statItems != null && statItems.isNotEmpty) {
          for (final stat in statItems) {
            final statMap = _asMap(stat);
            if (statMap == null) {
              continue;
            }
            blocks.add(
              domain.ArticleBlock(
                type: 'stat',
                content: _stringOrNull(statMap['value']) ?? '',
                label: _stringOrNull(statMap['label']),
              ),
            );
          }
          continue;
        }
      }

      final quoteLabelParts = <String>[
        if (_stringOrNull(map['label']) case final label? when label.isNotEmpty)
          label,
        if (_stringOrNull(map['author']) case final author?
            when author.isNotEmpty)
          author,
        if (_stringOrNull(map['role']) case final role? when role.isNotEmpty)
          role,
      ];

      blocks.add(
        domain.ArticleBlock(
          type: type,
          content: _stringOrNull(map['content']) ??
              _stringOrNull(map['text']) ??
              _stringOrNull(map['value']) ??
              '',
          label: quoteLabelParts.isEmpty ? null : quoteLabelParts.join(', '),
        ),
      );
    }

    return blocks;
  }

  int _compareArticles(domain.Article a, domain.Article b) {
    if (a.isFeatured != b.isFeatured) {
      return a.isFeatured ? -1 : 1;
    }

    final aMillis = a.publishedAt?.millisecondsSinceEpoch ?? 0;
    final bMillis = b.publishedAt?.millisecondsSinceEpoch ?? 0;
    return bMillis.compareTo(aMillis);
  }

  Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }

  List<Map<String, dynamic>> _asMapList(Object? value) {
    if (value is! List) {
      return const <Map<String, dynamic>>[];
    }

    return value
        .map(_asMap)
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }

  List<dynamic>? _asList(Object? value) {
    if (value is List) {
      return value;
    }
    return null;
  }

  String? _stringOrNull(Object? value) {
    if (value == null) {
      return null;
    }
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  int _intOr(Object? value, int fallback) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  bool _boolOr(Object? value, bool fallback) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }

    final normalized = value?.toString().trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') {
      return true;
    }
    if (normalized == 'false' || normalized == '0') {
      return false;
    }

    return fallback;
  }
}
