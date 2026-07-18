import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Holds the server-issued JWT used to authorize calls to the shared data API.
///
/// The token is kept in memory for synchronous access from the Dio request
/// interceptor and mirrored into encrypted secure storage so it survives an app
/// restart. A [refresher] callback (wired at startup to
/// `AuthService.refreshAppToken`) lets the network layer transparently re-mint
/// the token on a 401 without the network layer depending on the auth layer.
class AppTokenStore {
  AppTokenStore._();
  static final AppTokenStore instance = AppTokenStore._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _key = 'app_jwt';

  String? _token;

  /// Current token (null when not logged in / not yet fetched).
  String? get token => _token;

  bool get hasToken => _token != null && _token!.isNotEmpty;

  /// Re-mint the token using the stored credentials. Returns true on success.
  /// Wired at startup; null until then (treated as "cannot refresh").
  Future<bool> Function()? refresher;

  /// Load any persisted token into memory (call once at startup).
  Future<void> load() async {
    try {
      _token = await _storage.read(key: _key);
    } catch (e) {
      debugPrint('AppTokenStore load failed: $e');
      _token = null;
    }
  }

  Future<void> setToken(String token) async {
    _token = token;
    try {
      await _storage.write(key: _key, value: token);
    } catch (e) {
      debugPrint('AppTokenStore write failed: $e');
    }
  }

  Future<void> clear() async {
    _token = null;
    try {
      await _storage.delete(key: _key);
    } catch (e) {
      debugPrint('AppTokenStore clear failed: $e');
    }
  }
}
