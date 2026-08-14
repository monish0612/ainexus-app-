import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/app_constants.dart';
import '../services/telegram_logger.dart';
import 'app_credentials.dart';
import 'app_token_store.dart';
import 'session_policy.dart';

/// Singleton authentication service with HMAC-SHA256 credential verification
/// and AES-256 encrypted session persistence via Android EncryptedSharedPreferences.
class AuthService {
  AuthService._();
  static final instance = AuthService._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _sessionKey = 'nxs_session_v2';
  static const _sessionTsKey = 'nxs_session_ts';
  static const _usernameKey = 'nxs_username';
  static const _expiredKey = 'nxs_session_expired';
  static const _hmacKey = 'nxAi\$7kR2_mP9xL4q8W';

  /// Notifies GoRouter when auth state changes.
  final authState = ValueNotifier<bool>(false);

  bool get isAuthenticated => authState.value;

  String _username = '';

  /// True when the last sign-out was a 45-day session expiry (not a manual
  /// logout). The login screen uses this to ask for a re-entry of the same
  /// password and to pre-fill the username.
  bool _didSessionExpire = false;
  bool get didSessionExpire => _didSessionExpire;

  /// The display name of the logged-in user (title-cased). After a session
  /// expiry this is still the last username so the login field can be prefilled.
  String get username => _username;

  /// Just the first token of the display name — the canonical handle to use for
  /// a personal touch across the app (greetings, AI insights). Empty when not
  /// logged in.
  String get firstName {
    final parts = _username.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? '' : parts.first;
  }

  /// Read stored session on cold start; auto-expire after [SessionPolicy.maxDays].
  Future<void> init() async {
    final token = await _storage.read(key: _sessionKey);
    if (token == null || token.isEmpty) {
      _didSessionExpire = await _storage.read(key: _expiredKey) == '1';
      _username = await _storage.read(key: _usernameKey) ?? '';
      authState.value = false;
      return;
    }

    if (await _isSessionExpired()) {
      await logout(expired: true);
      return;
    }

    _didSessionExpire = false;
    await _storage.delete(key: _expiredKey);
    _username = await _storage.read(key: _usernameKey) ?? '';
    if (_username.isEmpty) {
      _username = _titleCase(AppCredentials.username);
      await _storage.write(key: _usernameKey, value: _username);
    }
    authState.value = true;
  }

  /// Re-validate on app resume so a stale session is caught even while running.
  Future<void> checkSessionValidity() async {
    if (!isAuthenticated) return;
    if (await _isSessionExpired()) await logout(expired: true);
  }

  Future<bool> _isSessionExpired() async {
    final tsStr = await _storage.read(key: _sessionTsKey);
    if (tsStr == null) return true;
    final loginTime = DateTime.tryParse(tsStr);
    if (loginTime == null) return true;
    return SessionPolicy.isExpired(loginTime, DateTime.now());
  }

  /// Verify [username] / [password] against stored HMAC digests.
  /// Returns `true` on match and creates an encrypted session token.
  ///
  /// A successful login always mints a **fresh** 45-day window — this is how
  /// the 45-day expiry "resets" without ever changing the password.
  Future<bool> authenticate(String username, String password) async {
    final expectedU = _hmac(AppCredentials.username);
    final expectedP = _hmac(AppCredentials.password);

    final inputU = _hmac(username.trim().toLowerCase());
    final inputP = _hmac(password);

    // Both comparisons execute before branching (timing-safe).
    final validUser = _constantTimeEquals(inputU, expectedU);
    final validPass = _constantTimeEquals(inputP, expectedP);
    if (!validUser || !validPass) return false;

    final now = DateTime.now();
    final session = _hmac('session:${now.toIso8601String()}');
    final displayName = _titleCase(username.trim());
    await _storage.write(key: _sessionKey, value: session);
    await _storage.write(key: _sessionTsKey, value: now.toIso8601String());
    await _storage.write(key: _usernameKey, value: displayName);
    await _storage.delete(key: _expiredKey);
    _username = displayName;
    _didSessionExpire = false;
    authState.value = true;

    // Best-effort: exchange the validated creds for a server JWT used to
    // authorize data calls. Never blocks login if the backend is unreachable.
    await _fetchAppToken(username.trim(), password);
    return true;
  }

  /// Sign out. When [expired] is true the username is kept and the login
  /// screen shows the 45-day re-entry copy; a manual logout wipes everything.
  Future<void> logout({bool expired = false}) async {
    await _storage.delete(key: _sessionKey);
    await _storage.delete(key: _sessionTsKey);
    await AppTokenStore.instance.clear();
    if (expired) {
      _didSessionExpire = true;
      await _storage.write(key: _expiredKey, value: '1');
      if (_username.isEmpty) {
        _username = await _storage.read(key: _usernameKey) ?? '';
      }
    } else {
      _didSessionExpire = false;
      _username = '';
      await _storage.delete(key: _usernameKey);
      await _storage.delete(key: _expiredKey);
    }
    authState.value = false;
  }

  /// Re-mint the server token from the built-in credentials. Wired into
  /// [AppTokenStore.refresher] so the Dio layer can recover from a 401
  /// transparently (token expiry / auth enforcement turned on mid-session).
  Future<bool> refreshAppToken() async {
    return _fetchAppToken(AppCredentials.username, AppCredentials.password);
  }

  /// Ensure a token exists when a valid session is already present (e.g. an app
  /// that upgraded into token support without re-logging-in). Safe no-op when
  /// not authenticated or a token is already cached.
  Future<void> ensureAppToken() async {
    if (!isAuthenticated) return;
    if (AppTokenStore.instance.hasToken) return;
    await refreshAppToken();
  }

  /// Test hook so unit tests never hit the network from [authenticate].
  @visibleForTesting
  static Future<bool> Function(String username, String password)? debugTokenExchange;

  Future<bool> _fetchAppToken(String username, String password) async {
    final hook = debugTokenExchange;
    if (hook != null) return hook(username, password);
    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: AppConstants.baseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          headers: {'Content-Type': 'application/json'},
        ),
      );
      final resp = await dio.post<Map<String, dynamic>>(
        '/api/v1/auth/app-login',
        data: {'username': username, 'password': password},
      );
      final token = resp.data?['token'];
      if (token is String && token.isNotEmpty) {
        await AppTokenStore.instance.setToken(token);
        return true;
      }
      return false;
    } catch (e) {
      // Auth enforcement may be off (older backend) → not fatal.
      TLog.w('Auth', 'app-login token fetch failed (non-fatal)', error: e);
      return false;
    }
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  /// Double-pass HMAC-SHA256.
  String _hmac(String input) {
    final key = utf8.encode(_hmacKey);
    final hmac = Hmac(sha256, key);
    final first = hmac.convert(utf8.encode(input));
    return hmac.convert(first.bytes).toString();
  }

  /// Constant-time comparison to prevent timing side-channel leaks.
  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  String _titleCase(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }
}
