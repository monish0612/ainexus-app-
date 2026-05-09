import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/database/app_database.dart';
import '../../domain/entities/saved_search.dart';
import '../../domain/entities/tutor_entities.dart';
import '../network/api_client.dart';
import '../network/api_endpoints.dart';
import 'telegram_logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  SavedSearchStore — persistence + sync for InsightAI bookmarked searches
// ─────────────────────────────────────────────────────────────────────────────
//
// Mirrors the proven ArticleFollowUpStore semantics:
//
//   • Local-first: every write hits Drift first; the user-visible UI reacts
//     to Drift's `.watch()` stream so it never blocks on the network.
//   • Fire-and-forget remote sync: every write enqueues a server push that
//     runs in the background. Failures land in `_retryQueue` and are
//     replayed on app `resumed` lifecycle events with a 1500 ms grace.
//   • Soft-delete: `delete()` sets `deletedAt` locally and POSTs DELETE to
//     the server. The row is hard-deleted from Drift only after the
//     server acknowledges (or after a 7-day TTL when the server is
//     unreachable, to avoid unbounded local growth).
//   • GC sweeper: orphaned chat messages (rows whose `searchId` does not
//     match any `SavedSearches` row AND are older than 1 hour) are pruned
//     on every foreground transition. Keeps the DB tidy if the user runs
//     many searches without saving.
//
// All errors are funneled through TLog with structured tags so Telegram
// observability is uniform with the rest of the app.

/// One pending server write that failed and is queued for resume retry.
class _RetryItem {
  _RetryItem({
    required this.action,
    required this.payload,
    this.searchId,
  });

  final String action; // 'create' | 'delete' | 'append' | 'summary'
  final Map<String, dynamic> payload;
  final String? searchId;
  int attempts = 0;
}

class SavedSearchStore with WidgetsBindingObserver {
  SavedSearchStore._();
  static final instance = SavedSearchStore._();

  static const _tag = 'SavedSearchStore';
  static const _gcTag = 'SavedSearchGC';
  static const _kMaxResumeRetries = 3;
  static const _kOrphanTtl = Duration(hours: 1);
  static const _kHardDeleteTtl = Duration(days: 7);
  static const _uuid = Uuid();

  /// Hard cap on the in-flight retry queue. If the user does many writes
  /// while offline, we bound memory growth by evicting the oldest entries
  /// once we exceed this. The local Drift state is unaffected — only the
  /// server push for the dropped entries is given up on.
  static const _kMaxRetryQueueSize = 200;

  AppDatabase? _db;
  ApiClient? _api;
  bool _observerBound = false;
  bool _initialFetchDone = false;
  Timer? _gcTimer;

  // Keyed on a stable retry-id (uuid), one entry per pending operation.
  final _retryQueue = <String, _RetryItem>{};

  /// Test-only accessor for the size of the in-flight retry queue.
  @visibleForTesting
  int debugRetryQueueLength() => _retryQueue.length;

  /// Test-only reset — clears all wired state and the lifecycle observer so
  /// successive tests start from a clean slate. Production code never calls
  /// this; the singleton lives for the app's lifetime.
  @visibleForTesting
  void debugResetForTests() {
    _db = null;
    _api = null;
    _retryQueue.clear();
    _initialFetchDone = false;
    _gcTimer?.cancel();
    _gcTimer = null;
    if (_observerBound) {
      WidgetsBinding.instance.removeObserver(this);
      _observerBound = false;
    }
  }

  /// Test-only invocation of the GC sweeper.
  @visibleForTesting
  Future<void> debugRunGc() => _runGc();

  // ── Initialisation ─────────────────────────────────────────────────────────

  /// Wires Drift + ApiClient. Idempotent — calling multiple times is a no-op
  /// after the first wiring. Lifecycle observer is registered exactly once.
  ///
  /// [api] is intentionally nullable so unit tests can exercise the local
  /// Drift paths in isolation; in production the Riverpod provider always
  /// supplies a real [ApiClient]. When [api] is null the periodic GC timer
  /// and the eager index pull are also skipped so widget tests don't trip
  /// the framework's "pending timers" guard.
  void init(AppDatabase db, ApiClient? api) {
    _db = db;
    _api = api;
    if (!_observerBound) {
      _observerBound = true;
      WidgetsBinding.instance.addObserver(this);
    }
    // Background work — only spin these up when an API client is present.
    // Tests pass a null api to keep the store synchronous and timer-free.
    if (api != null) {
      _gcTimer ??= Timer.periodic(const Duration(minutes: 30), (_) {
        unawaited(_runGc());
      });
      if (!_initialFetchDone) {
        _initialFetchDone = true;
        unawaited(_pullIndexFromServer());
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Drain the retry queue + run GC + pull fresh server index. All three
    // are best-effort; failures are logged but never thrown.
    unawaited(_runGc());
    unawaited(_pullIndexFromServer());
    if (_retryQueue.isEmpty) return;
    final keys = _retryQueue.keys.toList();
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      for (final k in keys) {
        final item = _retryQueue.remove(k);
        if (item == null) continue;
        TLog.d(_tag,
            'Resume → retry ${item.action} (attempt ${item.attempts + 1}/$_kMaxResumeRetries)');
        unawaited(_executeRetry(k, item));
      }
    });
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Live stream of all non-deleted saved searches, newest activity first.
  /// Driven by Drift's `.watch()` so UI updates without polling.
  Stream<List<SavedSearchEntry>> watchAll() {
    final db = _db;
    if (db == null) {
      TLog.w(_tag, 'watchAll() called before init() — returning empty stream');
      return const Stream<List<SavedSearchEntry>>.empty();
    }
    final query = db.select(db.savedSearches)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => drift.OrderingTerm.desc(t.updatedAt)]);
    return query.watch().map(
        (rows) => rows.map(SavedSearchEntry.fromDrift).toList(growable: false));
  }

  /// One-shot fetch (for non-stream callers).
  Future<List<SavedSearchEntry>> listAll() async {
    final db = _db;
    if (db == null) return const [];
    final rows = await (db.select(db.savedSearches)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => drift.OrderingTerm.desc(t.updatedAt)]))
        .get();
    return rows.map(SavedSearchEntry.fromDrift).toList(growable: false);
  }

  /// Returns true if a row with [id] exists and is not soft-deleted.
  Future<bool> isSaved(String id) async {
    final db = _db;
    if (db == null) return false;
    final row = await (db.select(db.savedSearches)
          ..where((t) => t.id.equals(id) & t.deletedAt.isNull())
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  /// Persist a new saved search snapshot. Returns the persisted entry.
  ///
  /// Behaviour:
  ///   1. Build canonical entry (server-style camelCase JSON for
  ///      `responseJson`).
  ///   2. Upsert into Drift — survives even if the server push fails.
  ///   3. Fire-and-forget POST to the server. On failure → retry queue.
  Future<SavedSearchEntry> saveResult({
    required String kind,
    required String query,
    required Object result,
    String? id,
    String? provider,
    String? mode,
  }) async {
    final db = _db;
    if (db == null) {
      throw StateError('SavedSearchStore.saveResult called before init()');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final entryId = id ?? _uuid.v4();
    final responseType = _responseTypeOf(result);
    final responseJson = _serializeResult(result);
    final model = _modelOf(result);
    final title = SavedSearchEntry.deriveTitle(kind: kind, query: query);

    final entry = SavedSearchEntry(
      id: entryId,
      kind: kind,
      query: query,
      title: title,
      responseType: responseType,
      responseJson: responseJson,
      model: model,
      provider: provider ?? '',
      mode: mode ?? '',
      savedAt: now,
      updatedAt: now,
    );

    try {
      await db.into(db.savedSearches).insertOnConflictUpdate(
            SavedSearchesCompanion.insert(
              id: entry.id,
              kind: entry.kind,
              query: entry.query,
              title: entry.title,
              responseType: entry.responseType,
              responseJson: entry.responseJson,
              model: drift.Value(entry.model),
              provider: drift.Value(entry.provider),
              mode: drift.Value(entry.mode),
              savedAt: entry.savedAt,
              updatedAt: entry.updatedAt,
            ),
          );
      TLog.d(_tag, 'save → ${entry.id} ($responseType)');
    } catch (e) {
      TLog.e(_tag, 'Drift insert failed for ${entry.id}', error: e);
      rethrow;
    }

    unawaited(_pushSave(entry));
    return entry;
  }

  /// Soft-delete locally, then DELETE remotely. The local row stays as a
  /// tombstone until the remote DELETE returns 200 (or until the 7-day
  /// hard-delete TTL kicks in via GC).
  Future<void> delete(String id) async {
    final db = _db;
    if (db == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      await (db.update(db.savedSearches)..where((t) => t.id.equals(id))).write(
        SavedSearchesCompanion(deletedAt: drift.Value(now)),
      );
      TLog.d(_tag, 'soft-delete → $id');
    } catch (e) {
      TLog.e(_tag, 'soft-delete failed for $id', error: e);
    }
    unawaited(_pushDelete(id));
  }

  /// Re-saves an entry that was previously soft-deleted (user undo).
  Future<void> undelete(String id) async {
    final db = _db;
    if (db == null) return;
    try {
      await (db.update(db.savedSearches)..where((t) => t.id.equals(id))).write(
        const SavedSearchesCompanion(deletedAt: drift.Value(null)),
      );
      TLog.d(_tag, 'undelete → $id');
      // Re-push to server so the previously sent DELETE is re-asserted as
      // a re-create. The server may need to handle this idempotently.
      final entry = await getById(id);
      if (entry != null) unawaited(_pushSave(entry));
    } catch (e) {
      TLog.e(_tag, 'undelete failed for $id', error: e);
    }
  }

  /// Fetch a single entry (including soft-deleted). Returns null if absent.
  Future<SavedSearchEntry?> getById(String id) async {
    final db = _db;
    if (db == null) return null;
    final row = await (db.select(db.savedSearches)
          ..where((t) => t.id.equals(id))
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : SavedSearchEntry.fromDrift(row);
  }

  // ── Chat persistence ──────────────────────────────────────────────────────

  /// Append a chat message to a saved search. Persists to Drift first, then
  /// fires-and-forgets a POST to the server. Bumps the parent
  /// `SavedSearches.updatedAt` so the History list re-orders.
  Future<void> appendMessage({
    required String searchId,
    required String messageId,
    required String role,
    required String text,
    String model = '',
    List<GroundedSource> sources = const [],
    String? createdAt,
  }) async {
    final db = _db;
    if (db == null) return;
    final ts = createdAt ?? DateTime.now().toUtc().toIso8601String();
    final sourcesJson = sources.isEmpty
        ? '[]'
        : jsonEncode(sources.map((s) => s.toJson()).toList());

    try {
      await db.into(db.savedSearchChatMessages).insertOnConflictUpdate(
            SavedSearchChatMessagesCompanion.insert(
              id: messageId,
              searchId: searchId,
              role: role,
              msgText: text,
              model: drift.Value(model),
              sourcesJson: drift.Value(sourcesJson),
              createdAt: ts,
            ),
          );
      // Bump the parent updatedAt so the History list re-sorts by activity.
      await (db.update(db.savedSearches)
            ..where((t) => t.id.equals(searchId)))
          .write(SavedSearchesCompanion(updatedAt: drift.Value(ts)));
      TLog.d(_tag, 'append → $searchId:$messageId ($role)');
    } catch (e) {
      TLog.e(_tag, 'append failed for $messageId', error: e);
    }

    unawaited(_pushAppend(searchId, messageId, role, text, model, sourcesJson, ts));
  }

  /// Returns all persisted messages for [searchId], oldest first.
  Future<List<PersistedChatMessage>> loadMessages(String searchId) async {
    final db = _db;
    if (db == null) return const [];
    try {
      final rows = await (db.select(db.savedSearchChatMessages)
            ..where((t) => t.searchId.equals(searchId))
            ..orderBy([(t) => drift.OrderingTerm.asc(t.createdAt)]))
          .get();
      return rows.map(PersistedChatMessage.fromDrift).toList(growable: false);
    } catch (e) {
      TLog.e(_tag, 'loadMessages failed for $searchId', error: e);
      return const [];
    }
  }

  /// Live stream of messages for a saved search, oldest first.
  Stream<List<PersistedChatMessage>> watchMessages(String searchId) {
    final db = _db;
    if (db == null) {
      return const Stream<List<PersistedChatMessage>>.empty();
    }
    final query = db.select(db.savedSearchChatMessages)
      ..where((t) => t.searchId.equals(searchId))
      ..orderBy([(t) => drift.OrderingTerm.asc(t.createdAt)]);
    return query.watch().map(
        (rows) => rows.map(PersistedChatMessage.fromDrift).toList(growable: false));
  }

  /// Pulls server-side messages for [searchId] and merges by id.
  Future<void> pullMessagesFromServer(String searchId) async {
    final db = _db;
    final api = _api;
    if (db == null || api == null) return;
    try {
      final response =
          await api.get<Object?>(ApiEndpoints.savedSearchChats(searchId));
      final data = response.data;
      if (data is! List) return;

      // Insert any rows we don't already have. Idempotent via upsert.
      for (final item in data) {
        if (item is! Map) continue;
        final raw = item.map((k, v) => MapEntry(k.toString(), v));
        final id = raw['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        await db.into(db.savedSearchChatMessages).insertOnConflictUpdate(
              SavedSearchChatMessagesCompanion.insert(
                id: id,
                searchId: searchId,
                role: raw['role']?.toString() ?? 'assistant',
                msgText: raw['text']?.toString() ?? raw['msgText']?.toString() ?? '',
                model: drift.Value(raw['model']?.toString() ?? ''),
                sourcesJson: drift.Value(
                    raw['sources_json']?.toString() ??
                        raw['sourcesJson']?.toString() ??
                        '[]'),
                createdAt: raw['created_at']?.toString() ??
                    raw['createdAt']?.toString() ??
                    DateTime.now().toUtc().toIso8601String(),
              ),
            );
      }
    } on DioException catch (e) {
      // 404 = backend hasn't deployed the endpoint yet OR no rows for this id;
      // either way, drop silently.
      if (e.response?.statusCode != 404) {
        TLog.w(_tag, 'pullMessages failed for $searchId', error: e);
      }
    } catch (e) {
      TLog.w(_tag, 'pullMessages parse failed for $searchId', error: e);
    }
  }

  // ── Server push paths ─────────────────────────────────────────────────────

  Future<void> _pushSave(SavedSearchEntry entry) async {
    final api = _api;
    if (api == null) return;
    try {
      await api.post<Object?>(ApiEndpoints.savedSearches, data: entry.toJson());
      TLog.d(_tag, 'POST ✓ ${entry.id}');
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        TLog.w(_tag, 'POST 404 — backend endpoint not deployed yet (id=${entry.id})');
        return;
      }
      _enqueueRetry(_RetryItem(
        action: 'create',
        payload: entry.toJson(),
        searchId: entry.id,
      ));
      TLog.w(_tag, 'POST failed for ${entry.id} — queued for retry', error: e);
    } catch (e) {
      _enqueueRetry(_RetryItem(
        action: 'create',
        payload: entry.toJson(),
        searchId: entry.id,
      ));
      TLog.w(_tag, 'POST failed for ${entry.id} — queued for retry', error: e);
    }
  }

  Future<void> _pushDelete(String id) async {
    final api = _api;
    final db = _db;
    if (api == null || db == null) return;
    try {
      await api.delete<Object?>(ApiEndpoints.savedSearch(id));
      await _hardDeleteLocal(db, id);
      TLog.d(_tag, 'DELETE ✓ $id');
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        // Server doesn't know about this entry — safe to hard-delete.
        await _hardDeleteLocal(db, id);
        TLog.d(_tag, 'DELETE 404 (treated as ok) — hard-deleted $id locally');
        return;
      }
      _enqueueRetry(_RetryItem(
        action: 'delete',
        payload: const {},
        searchId: id,
      ));
      TLog.w(_tag, 'DELETE failed for $id — queued for retry', error: e);
    } catch (e) {
      _enqueueRetry(_RetryItem(
        action: 'delete',
        payload: const {},
        searchId: id,
      ));
      TLog.w(_tag, 'DELETE failed for $id — queued for retry', error: e);
    }
  }

  /// Purges the saved-search row plus all its associated chat messages and
  /// summaries. Called from every successful (or 404) DELETE path so we
  /// never leak orphaned chat rows after the parent goes away.
  Future<void> _hardDeleteLocal(AppDatabase db, String id) async {
    await (db.delete(db.savedSearches)..where((t) => t.id.equals(id))).go();
    await (db.delete(db.savedSearchChatMessages)
          ..where((t) => t.searchId.equals(id)))
        .go();
    await (db.delete(db.savedSearchChatSummaries)
          ..where((t) => t.searchId.equals(id)))
        .go();
  }

  Future<void> _pushAppend(
    String searchId,
    String messageId,
    String role,
    String text,
    String model,
    String sourcesJson,
    String createdAt,
  ) async {
    final api = _api;
    if (api == null) return;
    final body = <String, dynamic>{
      'id': messageId,
      'role': role,
      'text': text,
      'model': model,
      'sourcesJson': sourcesJson,
      'createdAt': createdAt,
    };
    try {
      await api.post<Object?>(
        ApiEndpoints.savedSearchChats(searchId),
        data: body,
      );
      TLog.d(_tag, 'POST chat ✓ $searchId:$messageId');
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        TLog.w(_tag, 'POST chat 404 — endpoint not deployed (msg=$messageId)');
        return;
      }
      _enqueueRetry(_RetryItem(
        action: 'append',
        payload: body,
        searchId: searchId,
      ));
      TLog.w(_tag, 'POST chat failed for $messageId — queued for retry',
          error: e);
    } catch (e) {
      _enqueueRetry(_RetryItem(
        action: 'append',
        payload: body,
        searchId: searchId,
      ));
      TLog.w(_tag, 'POST chat failed for $messageId — queued for retry',
          error: e);
    }
  }

  Future<void> _pullIndexFromServer() async {
    final api = _api;
    final db = _db;
    if (api == null || db == null) return;
    try {
      final response = await api.get<Object?>(ApiEndpoints.savedSearches);
      final data = response.data;
      if (data is! List) return;

      for (final item in data) {
        if (item is! Map) continue;
        final raw = item.map((k, v) => MapEntry(k.toString(), v));
        final entry = SavedSearchEntry.fromJson(raw);
        if (entry.id.isEmpty) continue;
        // Skip rows the user has soft-deleted locally — local intent wins
        // until the DELETE round-trip completes.
        final existing = await getById(entry.id);
        if (existing != null && existing.deletedAt != null) continue;

        await db.into(db.savedSearches).insertOnConflictUpdate(
              SavedSearchesCompanion.insert(
                id: entry.id,
                kind: entry.kind,
                query: entry.query,
                title: entry.title,
                responseType: entry.responseType,
                responseJson: entry.responseJson,
                model: drift.Value(entry.model),
                provider: drift.Value(entry.provider),
                mode: drift.Value(entry.mode),
                savedAt: entry.savedAt,
                updatedAt: entry.updatedAt,
                pinned: drift.Value(entry.pinned),
              ),
            );
      }
      TLog.i(_tag, 'index pull ✓ (${data.length} rows)');
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) {
        TLog.w(_tag, 'index pull failed', error: e);
      }
    } catch (e) {
      TLog.w(_tag, 'index pull parse error', error: e);
    }
  }

  // ── Retry queue execution ─────────────────────────────────────────────────

  void _enqueueRetry(_RetryItem item) {
    // Bound memory if the user piles up writes while persistently offline.
    // We drop the OLDEST entry first — fresh writes are more likely to be
    // worth retrying than stale ones.
    while (_retryQueue.length >= _kMaxRetryQueueSize) {
      final oldestKey = _retryQueue.keys.first;
      final dropped = _retryQueue.remove(oldestKey);
      if (dropped != null) {
        TLog.w(_tag,
            'retry queue full ($_kMaxRetryQueueSize) → dropping oldest ${dropped.action}');
      }
    }
    final key = _uuid.v4();
    _retryQueue[key] = item;
  }

  Future<void> _executeRetry(String key, _RetryItem item) async {
    final api = _api;
    final db = _db;
    if (api == null || db == null) return;
    if (item.attempts >= _kMaxResumeRetries) {
      TLog.e(_tag, 'Retry exhausted for ${item.action} → giving up');
      return;
    }
    item.attempts++;
    try {
      switch (item.action) {
        case 'create':
          await api.post<Object?>(ApiEndpoints.savedSearches, data: item.payload);
          TLog.d(_tag, 'retry create ✓ ${item.searchId}');
          return;
        case 'delete':
          final id = item.searchId;
          if (id == null) return;
          await api.delete<Object?>(ApiEndpoints.savedSearch(id));
          await _hardDeleteLocal(db, id);
          TLog.d(_tag, 'retry delete ✓ $id');
          return;
        case 'append':
          final id = item.searchId;
          if (id == null) return;
          await api.post<Object?>(
            ApiEndpoints.savedSearchChats(id),
            data: item.payload,
          );
          TLog.d(_tag, 'retry append ✓ $id');
          return;
        case 'summary':
          final id = item.searchId;
          if (id == null) return;
          await api.put<Object?>(
            ApiEndpoints.savedSearchChatSummary(id),
            data: item.payload,
          );
          return;
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        TLog.w(_tag, 'retry ${item.action} 404 — dropping');
        return;
      }
      // Re-enqueue under a fresh key so future resume cycles can try again.
      _retryQueue[key] = item;
      TLog.w(_tag,
          'retry ${item.action} failed (attempt ${item.attempts}/$_kMaxResumeRetries)',
          error: e);
    } catch (e) {
      _retryQueue[key] = item;
      TLog.w(_tag,
          'retry ${item.action} failed (attempt ${item.attempts}/$_kMaxResumeRetries)',
          error: e);
    }
  }

  // ── Garbage collection ────────────────────────────────────────────────────

  /// Sweeper run periodically + on app foreground:
  ///   1. Drops any SavedSearchChatMessages whose searchId has no parent row
  ///      AND createdAt is older than 1 hour. This cleans up after sessions
  ///      where the user explored several searches without saving any.
  ///   2. Hard-deletes soft-deleted rows older than 7 days regardless of
  ///      remote DELETE status (eventual consistency safety net).
  Future<void> _runGc() async {
    final db = _db;
    if (db == null) return;
    try {
      final cutoffOrphan =
          DateTime.now().toUtc().subtract(_kOrphanTtl).toIso8601String();
      // Use a sub-select to find rows whose searchId is not in SavedSearches.
      // customUpdate returns the affected row count, unlike customStatement
      // which is statement-only and returns void.
      final orphans = await db.customUpdate(
        '''
        DELETE FROM saved_search_chat_messages
        WHERE created_at < ?
          AND search_id NOT IN (SELECT id FROM saved_searches)
        ''',
        variables: [drift.Variable<String>(cutoffOrphan)],
        updates: {db.savedSearchChatMessages},
      );
      if (orphans > 0) {
        TLog.w(_gcTag, 'pruned $orphans orphaned chat message(s)');
      }

      // Stale soft-deletes: hard-delete after 7 days even if the remote
      // DELETE never landed. Bounds DB growth on persistent network loss.
      final cutoffStale =
          DateTime.now().toUtc().subtract(_kHardDeleteTtl).toIso8601String();
      final stale = await (db.delete(db.savedSearches)
            ..where((t) =>
                t.deletedAt.isNotNull() &
                t.deletedAt.isSmallerThanValue(cutoffStale)))
          .go();
      if (stale > 0) {
        TLog.w(_gcTag, 'hard-deleted $stale stale soft-deleted row(s)');
      }
    } catch (e) {
      TLog.w(_gcTag, 'gc cycle failed', error: e);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _responseTypeOf(Object result) {
    if (result is SummarizerResult) return SavedSearchResponseType.summarizer;
    if (result is GroundedSearchResponse) {
      return SavedSearchResponseType.grounded;
    }
    if (result is TavilySearchResponse) return SavedSearchResponseType.tavily;
    throw ArgumentError(
        'Unsupported result type for saved-search: ${result.runtimeType}');
  }

  static String _serializeResult(Object result) {
    if (result is SummarizerResult) return jsonEncode(result.toJson());
    if (result is GroundedSearchResponse) return jsonEncode(result.toJson());
    if (result is TavilySearchResponse) return jsonEncode(result.toJson());
    throw ArgumentError(
        'Unsupported result type for saved-search: ${result.runtimeType}');
  }

  static String _modelOf(Object result) {
    if (result is SummarizerResult) return result.model;
    if (result is GroundedSearchResponse) return result.model;
    return '';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PersistedChatMessage — typed view of a row from saved_search_chat_messages
// ─────────────────────────────────────────────────────────────────────────────

@immutable
class PersistedChatMessage {
  const PersistedChatMessage({
    required this.id,
    required this.searchId,
    required this.role,
    required this.text,
    required this.model,
    required this.sources,
    required this.createdAt,
  });

  final String id;
  final String searchId;
  final String role;
  final String text;
  final String model;
  final List<GroundedSource> sources;
  final String createdAt;

  factory PersistedChatMessage.fromDrift(SavedSearchChatMessage row) {
    return PersistedChatMessage(
      id: row.id,
      searchId: row.searchId,
      role: row.role,
      text: row.msgText,
      model: row.model,
      sources: _parseSources(row.sourcesJson),
      createdAt: row.createdAt,
    );
  }

  static List<GroundedSource> _parseSources(String raw) {
    if (raw.isEmpty || raw == '[]') return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((m) => GroundedSource.fromJson(
              m.map((k, v) => MapEntry(k.toString(), v))))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
