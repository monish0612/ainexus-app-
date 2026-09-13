import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Current state of the floating bubble, as reported by the native side.
@immutable
class BubbleStatus {
  const BubbleStatus({
    required this.serviceEnabled,
    required this.enabled,
    required this.minChars,
    required this.batteryUnrestricted,
  });

  const BubbleStatus.unknown()
      : serviceEnabled = false,
        enabled = true,
        minChars = 8,
        batteryUnrestricted = false;

  /// The accessibility service is switched on in system settings.
  final bool serviceEnabled;

  /// Our own master switch.
  final bool enabled;

  final int minChars;
  final bool batteryUnrestricted;

  /// The bubble only actually appears when both switches are on.
  bool get active => serviceEnabled && enabled;
}

/// Flutter side of `Channels.SETTINGS_METHOD`, handled by MainActivity.
class BubbleSettingsChannel {
  const BubbleSettingsChannel();

  static const _channel = MethodChannel('app.ainexus.ai_nexus/bubble');

  /// Android-only; other platforms report the service as unavailable.
  bool get supported => defaultTargetPlatform == TargetPlatform.android && !kIsWeb;

  Future<BubbleStatus> status() async {
    if (!supported) return const BubbleStatus.unknown();
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>('status');
      if (map == null) return const BubbleStatus.unknown();
      return BubbleStatus(
        serviceEnabled: map['serviceEnabled'] as bool? ?? false,
        enabled: map['enabled'] as bool? ?? true,
        minChars: map['minChars'] as int? ?? 8,
        batteryUnrestricted: map['batteryUnrestricted'] as bool? ?? false,
      );
    } on PlatformException {
      return const BubbleStatus.unknown();
    } on MissingPluginException {
      return const BubbleStatus.unknown();
    }
  }

  Future<void> setEnabled(bool enabled) =>
      _invoke('setEnabled', {'enabled': enabled});

  Future<void> setMinChars(int value) => _invoke('setMinChars', {'value': value});

  Future<void> openAccessibilitySettings() =>
      _invoke('openAccessibilitySettings');

  /// App info screen — where sideloaded builds must first allow restricted
  /// settings before the accessibility toggle can be flipped.
  Future<void> openAppInfo() => _invoke('openAppInfo');

  Future<void> requestIgnoreBatteryOptimizations() =>
      _invoke('requestIgnoreBatteryOptimizations');

  Future<void> _invoke(String method, [Map<String, dynamic>? args]) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>(method, args);
    } on PlatformException {
      // Nothing actionable — the settings UI re-reads status on resume.
    } on MissingPluginException {
      // Ignore.
    }
  }
}
