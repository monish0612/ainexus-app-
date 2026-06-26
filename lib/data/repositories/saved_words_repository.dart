import 'dart:math' as math;

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
