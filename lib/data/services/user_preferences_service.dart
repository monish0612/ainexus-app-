import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/services/telegram_logger.dart';

/// Remote key-value store for cross-device settings sync.
///
/// Every method is fail-safe: network errors are logged via [TLog] and never
/// propagated, so callers can fire-and-forget without wrapping in try-catch.
/// The [ApiClient] already has retry + exponential backoff interceptors, so
/// this layer doesn't add its own retry — it just measures, logs, and returns
/// a success/failure signal.
class UserPreferencesService {
  UserPreferencesService(this._api);

  final ApiClient _api;

  static const _tag = 'UserPrefs';

  /// Fetch all preferences from the server.
  ///
  /// Returns `null` on network/parse error (caller should keep local state).
  /// Returns an empty map if the server has no preferences yet.
  Future<Map<String, String>?> fetchAll() async {
    TLog.d(_tag, 'fetchAll');
    final sw = Stopwatch()..start();
    try {
      final response = await _api.get<Object?>(ApiEndpoints.userPreferences);
      sw.stop();
      final data = response.data;
      if (data is Map) {
        final result =
            data.map((k, v) => MapEntry(k.toString(), v.toString()));
        TLog.i(
          _tag,
          'fetchAll ✓ ${result.length} keys (${sw.elapsedMilliseconds}ms)',
        );
        return result;
      }
      TLog.w(_tag, 'fetchAll non-map body (${sw.elapsedMilliseconds}ms)');
      return {};
    } catch (e) {
      sw.stop();
      TLog.e(
        _tag,
        'fetchAll FAILED (${sw.elapsedMilliseconds}ms)',
        error: e,
      );
      return null;
    }
  }

  /// Push a batch of key-value pairs to the server (single round-trip).
  ///
  /// Returns `true` on success, `false` on failure.
  Future<bool> pushBatch(Map<String, String> entries) async {
    if (entries.isEmpty) return true;
    final keys = entries.keys.join(', ');
    TLog.d(_tag, 'pushBatch → ${entries.length} keys [$keys]');
    final sw = Stopwatch()..start();
    try {
      final entryList = entries.entries
          .map((e) => <String, String>{'key': e.key, 'value': e.value})
          .toList();
      await _api.put<Object?>(
        ApiEndpoints.userPreferencesBatch,
        data: <String, dynamic>{'entries': entryList},
      );
      sw.stop();
      TLog.i(
        _tag,
        'pushBatch ✓ ${entries.length} keys (${sw.elapsedMilliseconds}ms)',
      );
      return true;
    } catch (e) {
      sw.stop();
      TLog.e(
        _tag,
        'pushBatch FAILED ${entries.length} keys (${sw.elapsedMilliseconds}ms)',
        error: e,
      );
      return false;
    }
  }
}
