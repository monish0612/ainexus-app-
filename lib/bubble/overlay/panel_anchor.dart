import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Places the expanded rephrase panel near the collapsed bubble so it stays
/// reachable — not stuck at the top of the screen.
///
/// Pure geometry (no Flutter widgets) so unit tests can pin the math without
/// pumping a tree. [pinTop] is used while the "Own" tone field has the IME.
Offset panelOriginNearBubble({
  required Size screen,
  required Size panel,
  double? bubbleX,
  double? bubbleY,
  double bubbleSize = 56,
  double safeTop = 8,
  double safeBottom = 8,
  double gap = 10,
  bool pinTop = false,
}) {
  final maxX = (screen.width - panel.width).clamp(0.0, double.infinity);
  final maxY =
      (screen.height - panel.height - safeBottom).clamp(safeTop, double.infinity);

  if (pinTop || bubbleY == null || bubbleX == null) {
    return Offset(maxX / 2, safeTop);
  }

  final size = bubbleSize.clamp(24.0, 96.0);
  final bubbleCenterX = bubbleX + size / 2;
  final bubbleCenterY = bubbleY + size / 2;

  // Prefer sitting just above the bubble when it rests in the lower half
  // (keyboard / thumb zone); otherwise just below so it never covers the field.
  final preferAbove = bubbleCenterY > screen.height * 0.45;
  double y = preferAbove
      ? bubbleY - panel.height - gap
      : bubbleY + size + gap;

  // If that side doesn't fit, try the other, then centre on the bubble.
  if (y < safeTop || y > maxY) {
    y = preferAbove ? bubbleY + size + gap : bubbleY - panel.height - gap;
  }
  if (y < safeTop || y > maxY) {
    y = bubbleCenterY - panel.height / 2;
  }
  y = y.clamp(safeTop, maxY);

  // Sit over the bubble horizontally so a mid-screen park stays reachable.
  final x = (bubbleCenterX - panel.width / 2).clamp(0.0, maxX);

  return Offset(x, y);
}

/// [CustomSingleChildLayout] delegate that applies [panelOriginNearBubble].
class PanelNearBubbleDelegate extends SingleChildLayoutDelegate {
  PanelNearBubbleDelegate({
    required this.bubbleX,
    required this.bubbleY,
    required this.bubbleSize,
    required this.safeTop,
    required this.safeBottom,
    required this.pinTop,
    required this.maxPanelWidth,
    required this.maxPanelHeight,
  });

  final double? bubbleX;
  final double? bubbleY;
  final double bubbleSize;
  final double safeTop;
  final double safeBottom;
  final bool pinTop;

  /// Design budget — must not come from the current window size, or the
  /// bubble→panel expand race (surface still 76dp) shrinks the panel forever.
  final double maxPanelWidth;
  final double maxPanelHeight;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(
      maxWidth: maxPanelWidth,
      maxHeight: maxPanelHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    // During the expand race the parent size can still be the 76dp bubble
    // window — place as if we already own the full display budget so the
    // first painted frame isn't stuck at (0,0) of a tiny surface.
    final screen = Size(
      math.max(size.width, maxPanelWidth),
      math.max(size.height, maxPanelHeight),
    );
    return panelOriginNearBubble(
      screen: screen,
      panel: childSize,
      bubbleX: bubbleX,
      bubbleY: bubbleY,
      bubbleSize: bubbleSize,
      safeTop: safeTop,
      safeBottom: math.max(safeBottom, 8),
      pinTop: pinTop,
    );
  }

  @override
  bool shouldRelayout(covariant PanelNearBubbleDelegate oldDelegate) {
    return oldDelegate.bubbleX != bubbleX ||
        oldDelegate.bubbleY != bubbleY ||
        oldDelegate.bubbleSize != bubbleSize ||
        oldDelegate.safeTop != safeTop ||
        oldDelegate.safeBottom != safeBottom ||
        oldDelegate.pinTop != pinTop ||
        oldDelegate.maxPanelWidth != maxPanelWidth ||
        oldDelegate.maxPanelHeight != maxPanelHeight;
  }
}
