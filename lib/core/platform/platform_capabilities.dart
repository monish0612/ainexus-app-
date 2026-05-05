import 'package:flutter/foundation.dart';

/// Centralized feature-availability flags for cross-platform rendering.
///
/// Use these instead of sprinkling `kIsWeb` or `Platform.isAndroid` checks
/// throughout the codebase. Every flag here represents a capability that
/// either depends on a platform-only API (MethodChannel, dart:io, native
/// plugin, etc.) or is intentionally disabled on a particular platform for
/// product reasons.
///
/// Android remains the source of truth for the full feature set; web is
/// strictly a *subset* — anything that requires Android-only native code is
/// hidden gracefully without breaking the existing flow.
abstract final class PlatformCapabilities {
  /// `true` when running in a browser (Flutter Web).
  static const bool isWeb = kIsWeb;

  /// `true` for any non-web target (Android in production today; iOS/desktop
  /// possible in the future).
  static const bool isMobile = !kIsWeb;

  // ── Native plugins / OS integrations ───────────────────────────────────────

  /// `flutter_local_notifications` + `workmanager` + `flutter_foreground_task`.
  /// Web has only a partial Notification API — we deliberately disable scheduled
  /// reminders on the web build and rely on the API/realtime stream instead.
  static const bool canUseNotifications = !kIsWeb;

  /// Background work scheduler (Android `WorkManager`). Web has no equivalent.
  static const bool canUseWorkmanager = !kIsWeb;

  /// Long-running foreground service (Android only).
  static const bool canUseForegroundTask = !kIsWeb;

  /// Biometric / device unlock (`local_auth`). Browsers have WebAuthn but
  /// it's a different surface; for now we hide it on web.
  static const bool canUseBiometric = !kIsWeb;

  /// On-device receipt OCR via `google_mlkit_text_recognition` (Android only).
  /// The web build hides the receipt-scan button per product decision.
  static const bool canUseMlKitOcr = !kIsWeb;

  /// Home-screen widget (`AppWidgetProvider`) bridge (Android only).
  static const bool canUseExpenseWidget = !kIsWeb;

  /// Quick-tile / launcher shortcut bridge (Android only).
  static const bool canUseShortcuts = !kIsWeb;

  /// Selection-toolbar `PROCESS_TEXT` intent + `ACTION_SEND` share intent
  /// (Android only).
  static const bool canUseProcessText = !kIsWeb;

  /// Native Android TextToSpeech engine bridge. `flutter_tts` itself works
  /// on web via the browser's SpeechSynthesis API; this flag specifically
  /// gates our **native** Android engine wrapper.
  static const bool canUseNativeTts = !kIsWeb;

  /// `flutter_tts` (browser SpeechSynthesis works, but quality varies). Kept
  /// enabled on web — individual screens can fall back to text-only display
  /// if speech fails.
  static const bool canUseFlutterTts = true;

  /// Microphone recording via `record` / `speech_to_text`. Web requires
  /// HTTPS + user gesture; we keep it on but expect occasional failures.
  static const bool canUseVoiceInput = true;

  /// Google Drive integration (`googleapis_auth` flow). On web we'd need a
  /// different OAuth flow (popup / redirect); for now hide it on web until
  /// we wire that up.
  static const bool canUseGoogleDrive = !kIsWeb;

  /// `dart:io` File operations (download to device, read from disk). Web
  /// uses `dart:html` Blob downloads via `package:web` instead.
  static const bool canUseDartIoFiles = !kIsWeb;

  /// PDF rendering via `pdfx` — works on web but requires CanvasKit; gate
  /// any heavy use on this if needed in the future.
  static const bool canUsePdfRendering = true;

  // ── Path utilities ─────────────────────────────────────────────────────────

  /// Path separator that works on the current platform. `Platform.pathSeparator`
  /// throws on web (no `dart:io`); use this everywhere instead.
  static const String pathSeparator = kIsWeb ? '/' : _pathSeparatorMobile;

  // The `Platform.pathSeparator` value is a const at the OS level; it's
  // platform-conditional but const-evaluable, so we encode the mobile case
  // here (always `/` on Android/iOS/macOS/Linux, `\` on Windows). Android
  // is `/`, which covers our shipping target.
  static const String _pathSeparatorMobile = '/';
}
