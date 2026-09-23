import 'package:ai_nexus/bubble/overlay/bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpOn(WidgetTester tester, Color backdrop, {bool animate = false, bool still = false}) async {
    const window = Size(76, 76);
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: window, disableAnimations: still),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: ColoredBox(
            color: backdrop,
            child: Center(child: RephraseBubble(animate: animate)),
          ),
        ),
      ),
    );
  }

  testWidgets('glass bead lays out on light, dark, and chat green', (tester) async {
    for (final backdrop in const [
      Color(0xFFFFFFFF),
      Color(0xFF0B0B0D),
      Color(0xFFE7FFDB),
    ]) {
      await pumpOn(tester, backdrop);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final rect = tester.getRect(find.byType(RephraseBubble));
      expect(rect.width, lessThanOrEqualTo(76.5));
      expect(rect.height, lessThanOrEqualTo(76.5));
      expect(find.byType(CustomPaint), findsWidgets);
    }
  });

  testWidgets('a live bead keeps breathing without throwing', (tester) async {
    await pumpOn(tester, const Color(0xFFFFFFFF), animate: true);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 900));
    expect(tester.takeException(), isNull);
    expect(find.byType(RephraseBubble), findsOneWidget);
  });

  testWidgets('reduced motion settles immediately', (tester) async {
    await pumpOn(tester, const Color(0xFF111111), animate: true, still: true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
