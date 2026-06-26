import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  /// SharedPreferences key for the cross-device delete-sync watermark.
  /// Stores the ISO-8601 timestamp of the most recent tombstone seen so
  /// the next /tombstones GET only returns the delta. Persisted across
  /// app restarts.
  static const _kTombstoneWatermarkKey =
      'savedSearchStore.lastTombstonePullAt';

  /// SharedPreferences flag set when a full-reset ("nuke") cloud clear failed
  /// (offline). Checked at the start of every sync so the server wipe self-heals
  /// before the index pull can re-hydrate the locally-wiped rows.
  static const _kPendingClearKey = 'savedSearchStore.pendingFullClear';

  /// In-memory mirror of the watermark, populated lazily on first pull.
  /// Falls back to null (i.e. "give me all tombstones since the dawn of
  /// time, capped at server-side LIMIT 1000") when SharedPreferences
  /// hasn't been initialized yet.
  String? _tombstoneWatermark;

  /// Drafts that have been abandoned (user navigated away / killed app
  /// without saving or clearing) are hard-deleted after this window. The
  /// 24-hour value is generous enough that a user who minimises their
  /// phone overnight won't lose an in-progress draft on the next morning,
  /// but tight enough that the DB doesn't grow unboundedly with stale
  /// drafts when a user runs many one-off searches.
  static const _kDraftTtl = Duration(hours: 24);

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

  /// In-memory mirror of the persisted [_kPendingClearKey] flag. Kept as a
  /// plain bool so the hot sync path can skip the pending-clear retry with a
  /// zero-cost check (no per-sync SharedPreferences read) in the overwhelmingly
  /// common case where no nuke is pending.
  bool _pendingFullClear = false;

  Timer? _gcTimer;

  /// Periodic foreground sync — fires every [_kForegroundSyncInterval] while
  /// the app is in the foreground (resumed). Catches the "user has the app
  /// open while another device deletes a row" scenario without requiring
  /// the user to background+foreground the app to trigger a resume sync.
  Timer? _foregroundSyncTimer;
  static const _kForegroundSyncInterval = Duration(seconds: 30);

  /// Test-only knob — when true, [init] skips installing the periodic
  /// foreground sync timer. Production always leaves this false; tests
  /// flip it on so the 30 s [Timer.periodic] doesn't keep firing in
  /// real time during widget tests and pollute the test clock with
  /// stale syncNow() invocations.
  @visibleForTesting
  static bool debugDisablePeriodicSync = false;

  /// Re-entrancy guard for syncNow — coalesces multiple concurrent callers
  /// (sheet-open + sheet-rebuild + lifecycle-resume firing nearly together)
  /// into a single network round-trip. Without this, the user opening the
  /// History sheet while the app resumes could fire 3+ identical syncs.
  Future<void>? _inFlightSync;

  /// Last time syncNow actually issued a network call. Used to debounce
  /// rapid repeated calls (e.g. tab switches in quick succession).
  DateTime _lastSyncAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const _kSyncDebounce = Duration(milliseconds: 500);

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
    _pendingFullClear = false;
    _tombstoneWatermark = null;
    _gcTimer?.cancel();
    _gcTimer = null;
    _foregroundSyncTimer?.cancel();
    _foregroundSyncTimer = null;
    _inFlightSync = null;
    _lastSyncAt = DateTime.fromMillisecondsSinceEpoch(0);
    if (_observerBound) {
      WidgetsBinding.instance.removeObserver(this);
      _observerBound = false;
    }
  }

  /// Test-only invocation of the tombstone pull. Production code calls
  /// it from [_pullIndexFromServer]. Exposed so the cross-device delete
  /// sync E2E test can drive it deterministically.
  @visibleForTesting
  Future<void> debugPullTombstones() => _pullTombstonesFromServer();

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
      // Periodic foreground sync — pulls the index + tombstones every
      // 30 s while the app is in the foreground. This is what makes
      // cross-device delete sync feel REAL-TIME without needing the
      // user to background+foreground the app: if Device B deletes a
      // row, Device A picks it up within 30 s while still on screen.
      // Tests can disable this via [debugDisablePeriodicSync] so the
      // real-time periodic firing doesn't escape the testWidgets clock.
      if (!debugDisablePeriodicSync) {
        _foregroundSyncTimer ??=
            Timer.periodic(_kForegroundSyncInterval, (_) {
          unawaited(syncNow(reason: 'periodic-foreground'));
        });
      }
      if (!_initialFetchDone) {
        _initialFetchDone = true;
        // Eager sweep on cold launch. The lifecycle observer's `resumed`
        // path only fires on a foreground TRANSITION — when the user
        // re-launches the app after Android killed the process, there's
        // no transition to observe, so abandoned drafts from the prior
        // session would otherwise sit in Drift for up to 30 min until
        // the periodic timer fires. Running GC here closes that gap so
        // a "close → reopen 25h later" cold launch leaves the local DB
        // exactly as clean as the user's mental model expects.
        unawaited(_runGc());
        unawaited(syncNow(reason: 'cold-start'));
      }
    }
  }

  /// Explicit cold-start hook (invoked from the Riverpod provider, NOT from
  /// [init], so unit tests that call [init] directly are unaffected): hydrate
  /// the persisted pending-clear flag and, if an offline nuke from a prior
  /// session never finished, complete the server clear so the rows don't
  /// re-hydrate on the next index pull.
  Future<void> retryPendingFullClearOnStartup() async {
    await _loadPendingClearFlag();
    await _retryPendingFullClear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Drain the retry queue + run GC + pull fresh server index. All three
    // are best-effort; failures are logged but never thrown.
    unawaited(_runGc());
    // force=true: when the user comes back from background, they
    // expect immediately-fresh data. Skip the debounce that would
    // otherwise no-op if a periodic sync just happened seconds ago.
    unawaited(syncNow(reason: 'lifecycle-resumed', force: true));
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

  // ── Public sync entrypoint ─────────────────────────────────────────────

  /// Pull the saved-search index AND tombstones from the server, in
  /// parallel. Safe to call from anywhere; multiple concurrent callers
  /// coalesce into a single network round-trip.
  ///
  /// Call this:
  ///   • On cold start (already done in [init])
  ///   • On app resume (already done in [didChangeAppLifecycleState])
  ///   • Every 30 s while the app is foreground (periodic timer in [init])
  ///   • When the user opens the History sheet (instant cross-device
  ///     freshness when they navigate to the view)
  ///   • When the user opens a saved-search detail (so a stale row that
  ///     was deleted on another device tears down the sheet)
  ///
  /// [reason] is a short tag included in TLog for debuggability. Pass
  /// e.g. 'sheet-open', 'lifecycle-resumed', 'periodic-foreground'.
  ///
  /// [force]=true bypasses the debounce — use for explicit user-initiated
  /// actions where the user expects immediate fresh data (e.g. lifecycle
  /// resume from a long background, manual pull-to-refresh).
  Future<void> syncNow({String reason = 'manual', bool force = false}) async {
    final api = _api;
    final db = _db;
    if (api == null || db == null) return;

    // Coalesce concurrent callers into a single in-flight Future. If
    // another sync is mid-flight, await its completion instead of
    // issuing a duplicate. This guard is unconditional — even `force`
    // callers should join the in-flight Future rather than fire a
    // second redundant round-trip.
    final pending = _inFlightSync;
    if (pending != null) return pending;

    // Debounce rapid-fire calls (e.g. open sheet → tap row → open detail
    // all within 200 ms). The 500 ms debounce is short enough that the
    // user perceives "instant" but long enough to coalesce navigation
    // bursts into a single round-trip. `force` skips this entirely.
    final now = DateTime.now();
    if (!force && now.difference(_lastSyncAt) < _kSyncDebounce) {
      return;
    }
    _lastSyncAt = now;

    final f = _runParallelSync(reason);
    _inFlightSync = f;
    try {
      await f;
    } finally {
      _inFlightSync = null;
    }
  }

  /// Internal helper: runs the index pull and tombstone pull in PARALLEL
  /// (Future.wait), so total wall-time is `max(t_index, t_tombstones)`
  /// instead of `t_index + t_tombstones`. With a 200 ms backend round-trip
  /// each, that cuts the sync from ~400 ms to ~200 ms — feels instant on
  /// the user's "open History sheet" tap.
  Future<void> _runParallelSync(String reason) async {
    final stopwatch = Stopwatch()..start();
    try {
      // A pending full-reset clear MUST resolve BEFORE the index pull — else a
      // resume/periodic sync would re-hydrate the locally-wiped rows straight
      // back from a server we never finished clearing. Gated on a cheap
      // in-memory bool so the common (no-nuke) path adds zero async work.
      if (_pendingFullClear) await _retryPendingFullClear();

      // Both calls are individually try/catch'd inside the method bodies
      // so one failing won't poison the other. Future.wait completes
      // when BOTH are done.
      await Future.wait<void>([
        _pullIndexFromServer(),
        _pullTombstonesFromServer(),
      ]);
      TLog.d(_tag, 'syncNow($reason) ✓ in ${stopwatch.elapsedMilliseconds}ms');
    } catch (e) {
      TLog.w(_tag, 'syncNow($reason) failed', error: e);
    }
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Live stream of SAVED entries (pinned=true), newest activity first.
  /// Drafts (pinned=false) are intentionally excluded so they never leak
  /// into the History sheet. Driven by Drift's `.watch()` so UI updates
  /// without polling.
  Stream<List<SavedSearchEntry>> watchAll() {
    final db = _db;
    if (db == null) {
      TLog.w(_tag, 'watchAll() called before init() — returning empty stream');
      return const Stream<List<SavedSearchEntry>>.empty();
    }
    final query = db.select(db.savedSearches)
      ..where((t) => t.deletedAt.isNull() & t.pinned.equals(true))
      ..orderBy([(t) => drift.OrderingTerm.desc(t.updatedAt)]);
    return query.watch().map(
        (rows) => rows.map(SavedSearchEntry.fromDrift).toList(growable: false));
  }

  /// One-shot fetch of SAVED entries (for non-stream callers). Mirrors
  /// the [watchAll] filter so callers see exactly the same list either way.
  Future<List<SavedSearchEntry>> listAll() async {
    final db = _db;
    if (db == null) return const [];
    final rows = await (db.select(db.savedSearches)
          ..where((t) => t.deletedAt.isNull() & t.pinned.equals(true))
          ..orderBy([(t) => drift.OrderingTerm.desc(t.updatedAt)]))
        .get();
    return rows.map(SavedSearchEntry.fromDrift).toList(growable: false);
  }

  /// Returns true ONLY for explicitly saved rows (pinned=true) that are
  /// not soft-deleted. Drafts return false — the bookmark icon in the UI
  /// uses this to render the "outline" (unsaved) state for an in-flight
  /// draft, even though the row already exists in Drift.
  Future<bool> isSaved(String id) async {
    final db = _db;
    if (db == null) return false;
    final row = await (db.select(db.savedSearches)
          ..where((t) =>
              t.id.equals(id) &
              t.deletedAt.isNull() &
              t.pinned.equals(true))
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

  // ── Draft lifecycle ──────────────────────────────────────────────────────
  //
  // Every InsightAI search result and URL summary lands in Drift as a draft
  // BEFORE the user explicitly bookmarks it, so all follow-up chat messages
  // can be persisted under a stable id from message #1. Drafts have
  // pinned=false and are excluded from [watchAll] / [listAll] / [isSaved],
  // so they never leak into the History sheet.
  //
  // Lifecycle:
  //   1. Search/summary result lands  → [startDraft] inserts row,
  //                                      pinned=false. Caller stores the
  //                                      returned id as the active session.
  //   2. User asks follow-up Qs       → [appendMessage] persists each
  //                                      finalized turn under the draft id.
  //   3. User taps "Save" (bookmark)  → [promoteToSaved] flips pinned=true.
  //                                      The same row now appears in History.
  //   4. User taps "Clear" / "Search  → [discardDraftIfAny] hard-deletes
  //      Again" without saving             the row + all its chat messages.
  //   5. App killed mid-draft         → row stays as pinned=false. The
  //                                      [_runGc] sweeper hard-deletes any
  //                                      draft older than _kDraftTtl on the
  //                                      next foreground transition.
  //
  // Saved entries are NEVER reachable from this draft API — [promoteToSaved]
  // is idempotent and [discardDraftIfAny] is a no-op when pinned=true.

  /// Persist a result snapshot as a DRAFT (pinned=false, hidden from the
  /// History sheet). Returns the entry whose [SavedSearchEntry.id] is the
  /// stable session id the caller should use as the parent for any
  /// follow-up chat messages.
  ///
  /// Behaviour:
  ///   • Allocates a fresh UUID id.
  ///   • Upserts a Drift row with pinned=false.
  ///   • DOES NOT push to the server. The server only learns about a row
  ///     when the user explicitly saves it (via [promoteToSaved]); drafts
  ///     are local-only by design so a user who never saves can't leak
  ///     their search history into the cloud.
  Future<SavedSearchEntry> startDraft({
    required String kind,
    required String query,
    required Object result,
    String? provider,
    String? mode,
  }) async {
    final db = _db;
    if (db == null) {
      throw StateError('SavedSearchStore.startDraft called before init()');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final entryId = _uuid.v4();
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
      await db.into(db.savedSearches).insert(
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
              pinned: const drift.Value(false),
            ),
          );
      TLog.d(_tag, 'draft → ${entry.id} ($responseType)');
    } catch (e) {
      TLog.e(_tag, 'Drift draft insert failed for ${entry.id}', error: e);
      rethrow;
    }

    return entry;
  }

  /// Promote an existing draft (pinned=false) to a saved entry (pinned=true)
  /// AND fire-and-forget the server push. Idempotent: if the row is already
  /// saved (or doesn't exist) this is a no-op. Returns true when a row was
  /// actually flipped, false otherwise.
  ///
  /// The server push is deferred until promotion (rather than at draft
  /// time) so unsaved local drafts never reach the cloud. This matches the
  /// privacy model the user expects when they see the bookmark icon as the
  /// boundary between "ephemeral" and "persisted across devices".
  Future<bool> promoteToSaved(String id) async {
    final db = _db;
    if (db == null) return false;
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final affected = await (db.update(db.savedSearches)
            ..where((t) => t.id.equals(id) & t.pinned.equals(false)))
          .write(SavedSearchesCompanion(
        pinned: const drift.Value(true),
        // Bump updatedAt on promote so the History list shows the entry
        // at the top — it's the most recent user-meaningful event.
        updatedAt: drift.Value(now),
        // Clear any soft-delete tombstone left over from a prior cycle
        // (defensive — in practice promote-then-delete-then-promote is
        // rare but we want it to behave correctly when it happens).
        deletedAt: const drift.Value(null),
      ));
      if (affected == 0) {
        TLog.d(_tag, 'promoteToSaved: no draft row to promote ($id)');
        return false;
      }
      TLog.d(_tag, 'promote draft → saved → $id');
    } catch (e) {
      TLog.e(_tag, 'promoteToSaved failed for $id', error: e);
      return false;
    }

    // Fire-and-forget server push so the saved entry appears on other
    // devices via the index pull.
    final entry = await getById(id);
    if (entry != null) {
      unawaited(_pushSave(entry));
    }
    return true;
  }

  /// Hard-delete a draft row (pinned=false) AND its chat messages. Called
  /// when the user taps "Clear" / "Search Again" without saving — leaving
  /// the draft in Drift would otherwise pollute the local DB until the
  /// 24-hour GC sweeper picks it up.
  ///
  /// Saved rows (pinned=true) are NEVER touched by this method — they go
  /// through the soft-delete path ([delete]) so the undo-snackbar works.
  /// Returns true when a draft was actually discarded, false otherwise.
  Future<bool> discardDraftIfAny(String id) async {
    final db = _db;
    if (db == null) return false;
    try {
      // Snapshot the draft state BEFORE deleting so we can decide whether
      // to also nuke chat messages. A non-draft (pinned=true) row should
      // never be hard-deleted by this method.
      final row = await (db.select(db.savedSearches)
            ..where((t) => t.id.equals(id))
            ..limit(1))
          .getSingleOrNull();
      if (row == null || row.pinned) {
        return false;
      }

      // Cascade: drop all chat messages + the rolling summary first so
      // there's never a moment where messages are visible without their
      // parent row.
      await (db.delete(db.savedSearchChatMessages)
            ..where((t) => t.searchId.equals(id)))
          .go();
      await (db.delete(db.savedSearchChatSummaries)
            ..where((t) => t.searchId.equals(id)))
          .go();
      await (db.delete(db.savedSearches)..where((t) => t.id.equals(id))).go();
      TLog.d(_tag, 'discard draft → $id');
      return true;
    } catch (e) {
      TLog.e(_tag, 'discardDraftIfAny failed for $id', error: e);
      return false;
    }
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

  /// Live watch of a single entry. Emits null when the row no longer
  /// exists in Drift (i.e. hard-deleted by GC, by the user on this
  /// device, or by a tombstone arriving from a remote device's delete).
  ///
  /// Used by [SavedSearchDetailSheet] to auto-pop itself when the
  /// underlying row disappears mid-view — gives the user a real-time
  /// "this got deleted on your other phone" experience instead of a
  /// stuck sheet showing stale content.
  Stream<SavedSearchEntry?> watchById(String id) {
    final db = _db;
    if (db == null) {
      return const Stream<SavedSearchEntry?>.empty();
    }
    final query = db.select(db.savedSearches)
      ..where((t) => t.id.equals(id))
      ..limit(1);
    return query.watch().map((rows) {
      if (rows.isEmpty) return null;
      return SavedSearchEntry.fromDrift(rows.first);
    });
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
      // ── Defensive guard ────────────────────────────────────────────────
      // If a row with this messageId already exists under a DIFFERENT
      // searchId, refuse to overwrite. This protects saved entries from
      // having their chat history "stolen" if the in-memory FAB cache is
      // mirror-written to a brand-new draft for the same query (e.g.
      // user does: search X → save → clear → re-search X → opens FAB →
      // cache replays the same message ids against the new draft id).
      // Without this guard, `insertOnConflictUpdate` would atomically
      // move every prior message off the saved entry, leaving it empty.
      final existing = await (db.select(db.savedSearchChatMessages)
            ..where((t) => t.id.equals(messageId))
            ..limit(1))
          .getSingleOrNull();
      if (existing != null && existing.searchId != searchId) {
        TLog.w(
            _tag,
            'append skipped: $messageId already belongs to '
            '${existing.searchId} (got $searchId)');
        return;
      }

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
      return;
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

  /// Cross-device delete sync. Pulls the server-side tombstone log of
  /// saved-searches that have been deleted on any device, applies them
  /// locally (hard-delete + cascade chat/summaries), and advances the
  /// per-install watermark so the next call only ships the delta.
  ///
  /// Robustness:
  ///   • Idempotent — applying the same tombstone twice is a no-op.
  ///   • Watermark advances ONLY after a successful local apply, so a
  ///     mid-sync crash never loses tombstones (we'll re-fetch them).
  ///   • A 404 (endpoint not deployed) is downgraded to a TLog.w one-
  ///     time message instead of a loud TLog.e — keeps Telegram clean
  ///     on older backends while still surfacing the diagnostic.
  ///   • All failures are swallowed (logged) and never propagated to
  ///     the UI — the rest of the app can carry on offline.
  Future<void> _pullTombstonesFromServer() async {
    final api = _api;
    final db = _db;
    if (api == null || db == null) return;
    try {
      final since = await _getTombstoneWatermark();
      final url = since == null
          ? ApiEndpoints.savedSearchTombstones
          : '${ApiEndpoints.savedSearchTombstones}?since=${Uri.encodeQueryComponent(since)}';
      final response = await api.get<Object?>(url);
      final data = response.data;
      if (data is! List) return;
      if (data.isEmpty) return;

      String maxDeletedAt = since ?? '';
      int applied = 0;
      for (final item in data) {
        if (item is! Map) continue;
        final raw = item.map((k, v) => MapEntry(k.toString(), v));
        final id = raw['id']?.toString() ?? '';
        final deletedAt =
            raw['deletedAt']?.toString() ?? raw['deleted_at']?.toString() ?? '';
        if (id.isEmpty) continue;

        // Apply the tombstone locally — hard-delete the row + cascade
        // chat messages + summaries. _hardDeleteLocal is idempotent so
        // a tombstone for an id we don't have locally is a no-op.
        await _hardDeleteLocal(db, id);
        applied++;

        if (deletedAt.compareTo(maxDeletedAt) > 0) {
          maxDeletedAt = deletedAt;
        }
      }

      if (maxDeletedAt.isNotEmpty && maxDeletedAt != since) {
        await _setTombstoneWatermark(maxDeletedAt);
      }
      if (applied > 0) {
        TLog.i(_tag,
            'tombstones ✓ ($applied applied, watermark=$maxDeletedAt)');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        TLog.w(_tag, 'tombstones 404 — endpoint not deployed yet');
        return;
      }
      TLog.w(_tag, 'tombstones pull failed', error: e);
    } catch (e) {
      TLog.w(_tag, 'tombstones parse error', error: e);
    }
  }

  Future<String?> _getTombstoneWatermark() async {
    if (_tombstoneWatermark != null) return _tombstoneWatermark;
    try {
      final prefs = await SharedPreferences.getInstance();
      _tombstoneWatermark = prefs.getString(_kTombstoneWatermarkKey);
    } catch (e) {
      // Prefs failure shouldn't block sync — fall back to "since=null"
      // (i.e. ask the server for everything, capped at LIMIT 1000).
      TLog.w(_tag, 'tombstone watermark read failed', error: e);
      _tombstoneWatermark = null;
    }
    return _tombstoneWatermark;
  }

  Future<void> _setTombstoneWatermark(String value) async {
    _tombstoneWatermark = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kTombstoneWatermarkKey, value);
    } catch (e) {
      TLog.w(_tag, 'tombstone watermark write failed', error: e);
    }
  }

  // ── Full reset ("nuke") ────────────────────────────────────────────────────

  /// Clears every saved search (+ its chats/summaries) on the **server** for a
  /// full-app reset. The local rows are wiped separately by the nuke's atomic
  /// DB wipe; this method exists so they don't re-hydrate from the cloud on the
  /// next index pull. The backend bulk-DELETE writes tombstones for every id so
  /// other devices sync the deletions too.
  ///
  /// Returns `true` when the server confirmed the clear. On failure a pending
  /// flag is persisted and [_retryPendingFullClear] finishes the job before the
  /// next sync's index pull.
  Future<bool> clearAllRemote() async {
    // Drop any queued create/append pushes — they'd re-create rows we're wiping.
    _retryQueue.clear();
    final ok = await _serverClearAllWithRetry();
    if (ok) {
      await _resetSyncWatermark();
    } else {
      await _setPendingClear(true);
      TLog.w(_tag, 'Flagged pending full clear for saved searches');
    }
    return ok;
  }

  Future<void> _retryPendingFullClear() async {
    if (!_pendingFullClear) return;
    TLog.i(_tag, 'Retrying pending saved-searches full clear');
    if (await _serverClearAllWithRetry()) {
      await _setPendingClear(false);
      await _resetSyncWatermark();
      TLog.i(_tag, 'Pending saved-searches full clear resolved');
    }
  }

  /// Hydrate [_pendingFullClear] from prefs once on cold start, so an offline
  /// nuke from a previous session still self-heals on the next sync.
  Future<void> _loadPendingClearFlag() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _pendingFullClear = prefs.getBool(_kPendingClearKey) ?? false;
    } catch (_) {/* prefs unavailable — leave as-is */}
  }

  Future<bool> _serverClearAllWithRetry({int maxAttempts = 3}) async {
    final api = _api;
    if (api == null) return false;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await api.delete<Object?>(ApiEndpoints.savedSearches);
        TLog.i(_tag, 'Saved searches cleared on server (attempt $attempt)');
        return true;
      } catch (e) {
        TLog.w(_tag,
            'Saved-searches server clear attempt $attempt/$maxAttempts failed',
            error: e);
        if (attempt < maxAttempts) {
          await Future<void>.delayed(Duration(milliseconds: 600 * attempt));
        }
      }
    }
    return false;
  }

  Future<void> _setPendingClear(bool value) async {
    _pendingFullClear = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value) {
        await prefs.setBool(_kPendingClearKey, true);
      } else {
        await prefs.remove(_kPendingClearKey);
      }
    } catch (e) {
      TLog.w(_tag, 'pending-clear flag write failed', error: e);
    }
  }

  /// After a full wipe there are no tombstones worth re-reading, so forget the
  /// watermark — the next pull starts clean.
  Future<void> _resetSyncWatermark() async {
    _tombstoneWatermark = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kTombstoneWatermarkKey);
    } catch (_) {/* non-fatal */}
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

      // Stale drafts: a draft row (pinned=false) older than [_kDraftTtl]
      // means the user did a search, never saved, and never explicitly
      // cleared it (e.g. app got killed, phone died, or they just walked
      // away). Hard-delete it together with its chat messages + summary so
      // the local DB doesn't fill up with abandoned sessions on a user
      // who runs many one-off searches.
      final cutoffDraft =
          DateTime.now().toUtc().subtract(_kDraftTtl).toIso8601String();
      // Snapshot the ids first so we can cascade-delete chats + summaries
      // before the parent rows go away. Using a single transaction would
      // be marginally faster but we don't have hard ordering requirements
      // and three small deletes are perfectly fine.
      final staleDraftRows = await (db.select(db.savedSearches)
            ..where((t) =>
                t.pinned.equals(false) &
                t.updatedAt.isSmallerThanValue(cutoffDraft)))
          .get();
      if (staleDraftRows.isNotEmpty) {
        final ids = staleDraftRows.map((r) => r.id).toList(growable: false);
        await (db.delete(db.savedSearchChatMessages)
              ..where((t) => t.searchId.isIn(ids)))
            .go();
        await (db.delete(db.savedSearchChatSummaries)
              ..where((t) => t.searchId.isIn(ids)))
            .go();
        await (db.delete(db.savedSearches)..where((t) => t.id.isIn(ids))).go();
        TLog.w(_gcTag,
            'hard-deleted ${ids.length} abandoned draft row(s) (>${_kDraftTtl.inHours}h)');
      }
    } catch (e) {
      TLog.w(_gcTag, 'gc cycle failed', error: e);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _responseTypeOf(Object result) {
    if (result is SummarizerResult) return SavedSearchResponseType.summarizer;
    // Image-grounded check MUST come before GroundedSearchResponse — the
    // wrapper exposes a [response] field of that exact type so a plain
    // `is GroundedSearchResponse` against the wrapper would mis-route it.
    if (result is ImageGroundedResult) {
      return SavedSearchResponseType.imageGrounded;
    }
    if (result is GroundedSearchResponse) {
      return SavedSearchResponseType.grounded;
    }
    if (result is TavilySearchResponse) return SavedSearchResponseType.tavily;
    throw ArgumentError(
        'Unsupported result type for saved-search: ${result.runtimeType}');
  }

  static String _serializeResult(Object result) {
    if (result is SummarizerResult) return jsonEncode(result.toJson());
    if (result is ImageGroundedResult) return jsonEncode(result.toJson());
    if (result is GroundedSearchResponse) return jsonEncode(result.toJson());
    if (result is TavilySearchResponse) return jsonEncode(result.toJson());
    throw ArgumentError(
        'Unsupported result type for saved-search: ${result.runtimeType}');
  }

  static String _modelOf(Object result) {
    if (result is SummarizerResult) return result.model;
    if (result is ImageGroundedResult) return result.model;
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
