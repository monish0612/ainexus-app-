import 'dart:async';

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
  Completer<void>? _startup;
  bool _startupSignaled = false;

  /// Current token (null when not logged in / not yet fetched).
  String? get token => _token;

  bool get hasToken => _token != null && _token!.isNotEmpty;

  /// Completes after post-first-frame auth wiring (token load + 401 refresher).
  /// News and other authenticated screens wait on this so the first GET is not
  /// a 401 that cannot be retried because [refresher] is still null.
  Future<void> get startupReady {
    if (_startupSignaled) return Future<void>.value();
    return (_startup ??= Completer<void>()).future;
  }

  bool get isStartupReady => _startupSignaled;

  /// Re-mint the token using the stored credentials. Returns true on success.
  /// Wired at startup; null until then (treated as "cannot refresh").
  Future<bool> Function()? refresher;

  /// Call once from `_afterFirstFrame` after [load] and [refresher] assignment.
  void markStartupReady() {
    _startupSignaled = true;
    final gate = _startup;
    if (gate != null && !gate.isCompleted) {
      gate.complete();
    }
  }

  /// Test-only: put the singleton back to a pre-boot state.
  @visibleForTesting
  void resetStartupGate() {
    final gate = _startup;
    if (gate != null && !gate.isCompleted) {
      gate.complete();
    }
    _startup = null;
    _startupSignaled = false;
  }

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
