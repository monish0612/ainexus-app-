import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/services/telegram_logger.dart';
import '../local/database/app_database.dart';

/// Cloud-sync + bulk-clear concerns for dictionary "saved words".
///
/// The day-to-day save / fetch / per-id delete still live in [TutorAiService]
/// and the dictionary UI; this repo exists specifically so the full-app "nuke"
/// can clear saved words on the **server** too. Without a server clear the
/// words simply re-hydrate from the cloud the next time the Dictionary tab
/// pulls (`_syncSavedWordsFromServer`), which is exactly the "saved words came
/// back after a reset" bug.
///
/// Mirrors the financial repos' robustness: server DELETE → GET verify →
/// exponential-backoff retry → a SharedPreferences pending flag that self-heals
/// on the next launch/resume via [retryPendingClear].
class SavedWordsRepository {
  SavedWordsRepository(this._db, this._api, this._prefs);

  final AppDatabase _db;
  final ApiClient _api;
  final SharedPreferences _prefs;

  static const _tag = 'SavedWordsRepo';
  static const _pendingClearKey = 'pending_clear_saved_words';

  /// Cross-device delete-sync watermark: ISO-8601 timestamp of the most recent
  /// saved-word tombstone applied locally. The next /tombstones GET only
  /// returns deletions newer than this, so the server ships just the delta.
  static const _tombstoneWatermarkKey = 'saved_words_tombstone_watermark';

  /// Cheap `COUNT(*)` of saved words — used by the nuke "what was cleared"
  /// window so it can report a real number.
  Future<int> count() async {
    final countExp = _db.savedWords.id.count();
    final q = _db.selectOnly(_db.savedWords)..addColumns([countExp]);
    final row = await q.getSingle();
    return row.read(countExp) ?? 0;
  }

  /// Clear all saved words (local + server). Returns `true` when the server
  /// confirmed empty. On failure the local rows are still gone and a pending
  /// flag is set so [retryPendingClear] finishes the cloud wipe later.
  Future<bool> clearAll() async {
    try {
      await _db.delete(_db.savedWords).go();
      TLog.i(_tag, 'Saved words cleared (local)');
    } catch (e) {
      TLog.e(_tag, 'Failed to clear saved words locally', error: e);
      rethrow;
    }

    final serverOk = await _serverDeleteWithRetry();
    if (!serverOk) {
      await _prefs.setBool(_pendingClearKey, true);
      TLog.w(_tag, 'Flagged pending clear for saved words');
    }
    return serverOk;
  }

  /// Retry a previously-failed cloud clear. Call on app start/resume.
  Future<void> retryPendingClear() async {
    if (!(_prefs.getBool(_pendingClearKey) ?? false)) return;
    TLog.i(_tag, 'Retrying pending saved-words clear');
    final ok = await _serverDeleteWithRetry();
    if (ok) {
      await _prefs.remove(_pendingClearKey);
      TLog.i(_tag, 'Pending saved-words clear resolved');
    }
  }

  Future<bool> _serverDeleteWithRetry({int maxAttempts = 3}) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await _api.delete<Object?>(ApiEndpoints.savedWords);
        if (await _verifyEmpty()) {
          TLog.i(_tag, 'Saved words cleared on server (attempt $attempt)');
          return true;
        }
        TLog.w(_tag, 'Saved-words verify failed — server still has data');
      } catch (e) {
        TLog.w(_tag, 'Saved-words server clear attempt $attempt/$maxAttempts '
            'failed', error: e);
      }
      if (attempt < maxAttempts) {
        await Future<void>.delayed(Duration(
          milliseconds: math.min(1000 * math.pow(2, attempt - 1).toInt(), 8000),
        ));
      }
    }
    return false;
  }

  /// Pull the server-side tombstone log of deleted saved words (since the last
  /// watermark) and hard-delete those rows locally, so a deletion performed on
  /// the website or another device propagates to this phone. Returns the number
  /// of local rows actually removed. Idempotent and safe to call repeatedly.
  ///
  /// Before this existed the Dictionary's pull was insert-only (it skipped ids
  /// it already had), so a word deleted elsewhere never disappeared here.
  Future<int> syncTombstones() async {
    try {
      final since = _prefs.getString(_tombstoneWatermarkKey);
      final url = (since == null || since.isEmpty)
          ? ApiEndpoints.savedWordTombstones
          : '${ApiEndpoints.savedWordTombstones}'
              '?since=${Uri.encodeQueryComponent(since)}';
      final response = await _api.get<Object?>(url);
      final data = response.data;
      if (data is! List || data.isEmpty) return 0;

      var maxDeletedAt = since ?? '';
      var applied = 0;
      for (final item in data) {
        if (item is! Map) continue;
        final id = item['id']?.toString() ?? '';
        final deletedAt = item['deletedAt']?.toString() ??
            item['deleted_at']?.toString() ??
            '';
        // A real tombstone always carries both an id and a deletedAt. Skip any
        // malformed/foreign payload so we never delete on a non-tombstone row.
        if (id.isEmpty || deletedAt.isEmpty) continue;

        // Guard: if this word was (re-)saved locally strictly AFTER the remote
        // delete, keep it — its own push will re-create the server row and clear
        // the tombstone. Saved words are immutable, so savedAt is the only clock.
        final local = await (_db.select(_db.savedWords)
              ..where((t) => t.id.equals(id))
              ..limit(1))
            .getSingleOrNull();
        if (local != null &&
            local.savedAt.isNotEmpty &&
            local.savedAt.compareTo(deletedAt) > 0) {
          if (deletedAt.compareTo(maxDeletedAt) > 0) maxDeletedAt = deletedAt;
          continue;
        }

        final removed = await (_db.delete(_db.savedWords)
              ..where((t) => t.id.equals(id)))
            .go();
        if (removed > 0) applied++;
        if (deletedAt.compareTo(maxDeletedAt) > 0) maxDeletedAt = deletedAt;
      }

      if (maxDeletedAt.isNotEmpty && maxDeletedAt != since) {
        await _prefs.setString(_tombstoneWatermarkKey, maxDeletedAt);
      }
      if (applied > 0) {
        TLog.i(_tag, '☁️ Applied $applied remote saved-word deletion(s)');
      }
      return applied;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        TLog.w(_tag, 'saved-word tombstones 404 — backend not deployed yet');
        return 0;
      }
      TLog.w(_tag, 'saved-word tombstones pull failed', error: e);
      return 0;
    } catch (e) {
      TLog.w(_tag, 'saved-word tombstones parse error', error: e);
      return 0;
    }
  }

  Future<bool> _verifyEmpty() async {
    try {
      final resp = await _api.get<Object?>(ApiEndpoints.savedWords);
      final data = resp.data;
      return data is List ? data.isEmpty : true;
    } catch (e) {
      TLog.w(_tag, 'Saved-words verify GET failed', error: e);
      return false;
    }
  }
}
