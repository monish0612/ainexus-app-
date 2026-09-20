import 'package:ai_nexus/bubble/overlay/panel_anchor.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const screen = Size(360, 800);
  const panel = Size(308, 120);

  group('panelOriginNearBubble', () {
    test('falls back to top-centre without bubble coords', () {
      final o = panelOriginNearBubble(
        screen: screen,
        panel: panel,
        safeTop: 24,
      );
      expect(o.dy, 24);
      expect(o.dx, closeTo((360 - 308) / 2, 0.1));
    });

    test('pins to top when Own tone needs the IME', () {
      final o = panelOriginNearBubble(
        screen: screen,
        panel: panel,
        bubbleX: 280,
        bubbleY: 600,
        bubbleSize: 56,
        pinTop: true,
        safeTop: 24,
      );
      expect(o.dy, 24);
    });

    test('sits above a bubble in the lower half (thumb zone)', () {
      final o = panelOriginNearBubble(
        screen: screen,
        panel: panel,
        bubbleX: 280,
        bubbleY: 620,
        bubbleSize: 56,
        safeTop: 24,
        safeBottom: 24,
      );
      // Panel bottom should be near the bubble top.
      expect(o.dy + panel.height, lessThanOrEqualTo(620));
      expect(o.dy, greaterThan(200)); // not stuck at the top
      // 308dp panel on a 360dp screen clamps toward the right; still on-screen.
      expect(o.dx, greaterThan(20));
    });

    test('sits below a bubble in the upper half', () {
      final o = panelOriginNearBubble(
        screen: screen,
        panel: panel,
        bubbleX: 8,
        bubbleY: 80,
        bubbleSize: 56,
        safeTop: 24,
        safeBottom: 24,
      );
      expect(o.dy, greaterThanOrEqualTo(80 + 56));
      expect(o.dx, lessThan(20)); // left side, clamped
    });

    test('centres on a mid-screen bubble on a wide display', () {
      const wide = Size(800, 800);
      final o = panelOriginNearBubble(
        screen: wide,
        panel: panel,
        bubbleX: 360,
        bubbleY: 200,
        bubbleSize: 56,
        safeTop: 24,
        safeBottom: 24,
      );
      const bubbleCenterX = 360 + 56 / 2;
      expect(o.dx, closeTo(bubbleCenterX - panel.width / 2, 1));
      expect(o.dx, greaterThan(80));
      expect(o.dx + panel.width, lessThan(wide.width - 80));
    });

    test('a left-edge bubble on a wide display does not hug the right', () {
      final o = panelOriginNearBubble(
        screen: const Size(800, 800),
        panel: panel,
        bubbleX: 8,
        bubbleY: 400,
        bubbleSize: 56,
        safeTop: 24,
        safeBottom: 24,
      );
      expect(o.dx, lessThan(40));
    });

    test('never places the panel off-screen', () {
      final o = panelOriginNearBubble(
        screen: screen,
        panel: const Size(308, 400),
        bubbleX: 300,
        bubbleY: 750,
        bubbleSize: 56,
        safeTop: 24,
        safeBottom: 24,
      );
      expect(o.dx, greaterThanOrEqualTo(0));
      expect(o.dy, greaterThanOrEqualTo(24));
      expect(o.dx + 308, lessThanOrEqualTo(360 + 0.1));
      expect(o.dy + 400, lessThanOrEqualTo(800 - 24 + 0.1));
    });
  });
}
