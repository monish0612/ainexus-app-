import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

abstract final class AppConstants {
  static const appName = 'Nexus AI';
  static const appVersion = 'v2.4.1';

  /// Toggle this to switch between local dev and production.
  /// Set to `true` when running on emulator/device against local backend.
  /// Set to `false` for release builds pointing to Coolify VPS.
  ///
  /// On the web build we always treat the app as production unless the
  /// developer explicitly overrides via `--dart-define`, since `kDebugMode`
  /// is `true` even when serving the app from a deployed Caddy container in
  /// a tab the developer happens to be debugging.
  static const useLocalDev = kDebugMode && !kIsWeb;

  static const _localBaseUrl = 'http://localhost:3000';
  static const _prodBaseUrl = 'http://72.60.219.97:3000';

  static const _localLiteLlmUrl = 'http://localhost:4000';
  // Note: pre-existing constant retained as-is (Flutter never calls LiteLLM
  // directly; all LLM traffic goes through the backend API). Fixing the
  // typo here would be a logic change; leaving alone to honour the
  // "don't break anything" requirement.
  static const _prodLiteLlmUrl = 'http://72.80.219.97:4000';

  /// Optional override at build time:
  ///   flutter build web --dart-define=API_BASE_URL=https://api.example.com
  ///   flutter build apk --dart-define=API_BASE_URL=http://10.0.2.2:3000
  ///
  /// When empty, falls back to local-vs-prod toggle below.
  static const _envApiBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: '');
  static const _envLiteLlmUrl =
      String.fromEnvironment('LITELLM_URL', defaultValue: '');

  static String get baseUrl {
    if (_envApiBaseUrl.isNotEmpty) return _envApiBaseUrl;
    return useLocalDev ? _localBaseUrl : _prodBaseUrl;
  }

  static String get liteLlmUrl {
    if (_envLiteLlmUrl.isNotEmpty) return _envLiteLlmUrl;
    return useLocalDev ? _localLiteLlmUrl : _prodLiteLlmUrl;
  }

  static const animDuration = Duration(milliseconds: 220);
  static const animDurationSlow = Duration(milliseconds: 380);
  static const animationCurve = Curves.easeOutCubic;

  static const headerHeight = 52.0;
  static const navHeight = 56.0;
  static const maxAppWidth = 430.0;

  static const categories = <String>[
    'Food',
    'Grocery',
    'Transport',
    'Entertainment',
    'Shopping',
    'Bills',
    'Health',
    'Others',
  ];

  static const banks = <String>['HDFC', 'ICICI', 'FEDERAL', 'Other'];
  static const cardTypes = <String>['Debit Card', 'Credit Card', 'Cash'];

  static const budgetPresets = <int>[5000, 10000, 20000, 50000];

}
