import 'package:flutter/services.dart';

import 'tokens.dart';

/// The text the bubble is acting on, the app it came from, and how large the
/// panel is allowed to be on this display.
class BubbleTarget {
  const BubbleTarget({
    required this.text,
    required this.package,
    this.maxWidth = kPanelMaxWidth,
    this.maxHeight = 320,
    this.lastPlatformId,
    this.bubbleX,
    this.bubbleY,
    this.bubbleSize,
  });

  const BubbleTarget.empty()
      : text = '',
        package = '',
        maxWidth = kPanelMaxWidth,
        maxHeight = 320,
        lastPlatformId = null,
        bubbleX = null,
        bubbleY = null,
        bubbleSize = null;

  factory BubbleTarget.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const BubbleTarget.empty();
    final width = (map['maxWidth'] as num?)?.toDouble() ?? kPanelMaxWidth;
    final height = (map['maxHeight'] as num?)?.toDouble() ?? 320;
    final last = (map['lastPlatformId'] as String?)?.trim();
    final bx = (map['bubbleX'] as num?)?.toDouble();
    final by = (map['bubbleY'] as num?)?.toDouble();
    final bs = (map['bubbleSize'] as num?)?.toDouble();
    return BubbleTarget(
      text: (map['text'] as String?) ?? '',
      package: (map['package'] as String?) ?? '',
      // Native reports 0 before the overlay window exists.
      maxWidth: width > 0 ? width : kPanelMaxWidth,
      maxHeight: height > 0 ? height : 320,
      lastPlatformId: (last == null || last.isEmpty) ? null : last,
      // Negative / missing means native has no collapsed position yet.
      bubbleX: (bx != null && bx >= 0) ? bx : null,
      bubbleY: (by != null && by >= 0) ? by : null,
      bubbleSize: (bs != null && bs > 0) ? bs : null,
    );
  }

  final String text;
  final String package;

  /// The panel's size budget in logical pixels, clamped by native to the
  /// display. Layout uses this rather than the current window size so the panel
  /// reaches its final size in one pass instead of growing over several frames.
  final double maxWidth;
  final double maxHeight;

  /// Last successful rephrase platform id, shown first in the chip row.
  final String? lastPlatformId;

  /// Collapsed bubble window origin (logical px) captured before expand.
  /// Used so the panel opens next to the bubble instead of at the top.
  final double? bubbleX;
  final double? bubbleY;
  final double? bubbleSize;

  bool get isEmpty => text.trim().isEmpty;
}

/// How the rephrased text landed in the target field.
enum ReplaceOutcome {
  setText,
  paste,
  blocked;

  static ReplaceOutcome fromName(String? name) => switch (name) {
        'REPLACED_SET_TEXT' => ReplaceOutcome.setText,
        'REPLACED_PASTE' => ReplaceOutcome.paste,
        _ => ReplaceOutcome.blocked,
      };

  bool get replaced => this != ReplaceOutcome.blocked;
}

/// Dart side of the overlay bridge. Channel name must match `Channels.kt`.
class OverlayBridge {
  OverlayBridge() {
    _channel.setMethodCallHandler(_onCall);
  }

  static const _channel =
      MethodChannel('app.ainexus.ai_nexus/bubble_overlay');

  void Function(BubbleTarget target)? onTarget;
  void Function()? onCollapse;

  /// Native tap on the collapsed bubble (gestures live natively now).
  void Function()? onTap;

  /// Overlay window left the screen — stop breath/sheen tickers.
  void Function()? onPause;

  /// Overlay window is showing again — tickers may resume.
  void Function()? onResume;

  Future<void> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'onTarget':
        final args = (call.arguments as Map?)?.cast<String, dynamic>();
        onTarget?.call(BubbleTarget.fromMap(args));
      case 'onCollapse':
        onCollapse?.call();
      case 'onTap':
        onTap?.call();
      case 'onPause':
        onPause?.call();
      case 'onResume':
        onResume?.call();
    }
  }

  Future<BubbleTarget> target() => _target('target');

  /// Grow the window for the panel. Native takes a final live read of the field
  /// first, so the returned target is the authoritative text to rephrase.
  Future<BubbleTarget> expand() => _target('expand');

  Future<BubbleTarget> _target(String method) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(method);
      return BubbleTarget.fromMap(result);
    } on PlatformException {
      return const BubbleTarget.empty();
    } on MissingPluginException {
      return const BubbleTarget.empty();
    }
  }

  /// Write [text] into the focused field of the target app.
  Future<ReplaceOutcome> replace(String text) async {
    try {
      final name = await _channel.invokeMethod<String>('replace', {'text': text});
      return ReplaceOutcome.fromName(name);
    } on PlatformException {
      return ReplaceOutcome.blocked;
    }
  }

  Future<void> copy(String text) => _fireAndForget('copy', {'text': text});

  Future<void> collapse() => _fireAndForget('collapse');

  /// Ask native to shrink the window to the panel's measured size, so the
  /// overlay never swallows touches meant for the app underneath.
  Future<void> resize(Size size) => _fireAndForget(
        'resize',
        {'width': size.width, 'height': size.height},
      );

  /// Lend the overlay keyboard focus for the "Own" tone field. Must be handed
  /// back before writing to the target field.
  Future<void> setFocusable(bool value) =>
      _fireAndForget('setFocusable', {'value': value});

  Future<void> hideKeyboard() => _fireAndForget('hideKeyboard');

  /// Persist the last successful chip so the next open shows it first.
  Future<void> saveLastPlatform(String platform) =>
      _fireAndForget('saveLastPlatform', {'platform': platform});

  Future<void> _fireAndForget(String method, [Map<String, dynamic>? args]) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on PlatformException {
      // The service may have been torn down mid-gesture; nothing to recover.
    } on MissingPluginException {
      // Overlay running outside the accessibility service (tests).
    }
  }
}
