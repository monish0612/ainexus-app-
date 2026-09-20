import 'package:flutter/material.dart';

/// White-on-transparent status-bar glyph (`drawable/ic_notification`).
///
/// Android tints this drawable with the notification accent. The full
/// phone+card launcher must never be used here — at 24dp it collapses
/// into a white square.
abstract final class AndroidStatusBarIcon {
  static const drawableName = 'ic_notification';
  static const audioServiceRes = 'drawable/ic_notification';
  static const manifestMeta = 'app.ainexus.NOTIFICATION_ICON';
  static const accent = Color(0xFF0D59F2);
}
