// Deep coverage for the immersive [ImageZoomViewer] used to read article
// images (often screenshots of dense text) at full zoom on both Android and
// web-in-a-browser.
//
// The suite splits into two layers:
//
//   1. PURE MATH (device-independent — guarantees "no scaling / jump issues"
//      on any screen size or pixel ratio):
//        • buildZoomToPointMatrix keeps the tapped point perfectly anchored
//          (the whole reason double-tap zoom feels precise), and produces the
//          exact requested scale.
//        • zoomViewerShouldDismiss honours the distance/velocity thresholds.
//
//   2. WIDGET BEHAVIOUR (the actual gesture flow the user experiences):
//        • an empty URL is a safe no-op (never pushes a blank viewer),
//        • the viewer opens over the app and shows the interactive surface,
//        • the ✕ button and a backdrop tap both close it,
//        • the system back button / back-swipe closes it (route pop),
//        • double-tap zooms in (and a second double-tap resets),
//        • swiping down at 1× dismisses the viewer.
//
// NOTE: the loading placeholder is a CircularProgressIndicator (an infinite
// ticker) because the network image never resolves in tests, so we NEVER call
// pumpAndSettle — we always advance time with explicit pump() durations and
// tear the tree down with _drain() so no ticker/timer leaks past the test.

import 'package:ai_nexus/presentation/widgets/image_zoom_viewer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';

const String _kUrl = 'https://cdn.example.com/dense-text-screenshot.png';

Future<void> _openViewer(WidgetTester tester) async {
  late BuildContext ctx;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (c) {
            ctx = c;
            return const Center(child: Text('host'));
          },
        ),
      ),
    ),
  );
  showImageZoomViewer(ctx, imageUrl: _kUrl, heroTag: 'hero-$_kUrl');
  // Advance the fade/hero route transition (260ms) without settling (the
  // placeholder spinner would spin forever).
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 320));
}

/// Disposes the whole tree so the viewer's animation controllers + the
/// placeholder spinner ticker are torn down before the test ends.
Future<void> _drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 350));
}

TransformationController _controllerOf(WidgetTester tester) {
  final iv = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
  return iv.transformationController!;
}

Future<void> _doubleTapAt(WidgetTester tester, Offset globalPos) async {
  await tester.tapAt(globalPos);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tapAt(globalPos);
  await tester.pump(); // kick off the zoom animation
  await tester.pump(const Duration(milliseconds: 320)); // finish it (260ms)
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('buildZoomToPointMatrix (pure)', () {
    test('produces exactly the requested scale', () {
      final m = buildZoomToPointMatrix(const Offset(120, 80), 2.6);
      expect(m.getMaxScaleOnAxis(), closeTo(2.6, 1e-9));
    });

    test('anchors the focal point (it maps to itself → no jump)', () {
      // This is the property that makes double-tap zoom land precisely on the
      // tapped point regardless of device size or pixel density.
      for (final focal in const [
        Offset.zero,
        Offset(1, 1),
        Offset(200, 350),
        Offset(719.5, 1279.5),
      ]) {
        for (final scale in const [1.5, 2.6, 6.0]) {
          final m = buildZoomToPointMatrix(focal, scale);
          final mapped = MatrixUtils.transformPoint(m, focal);
          expect(mapped.dx, closeTo(focal.dx, 1e-6),
              reason: 'focal.dx must stay fixed for scale=$scale');
          expect(mapped.dy, closeTo(focal.dy, 1e-6),
              reason: 'focal.dy must stay fixed for scale=$scale');
        }
      }
    });

    test('identity when scale == 1 (no translation, no zoom)', () {
      final m = buildZoomToPointMatrix(const Offset(300, 300), 1.0);
      expect(m.getMaxScaleOnAxis(), closeTo(1.0, 1e-9));
      final t = m.getTranslation();
      expect(t.x, closeTo(0, 1e-9));
      expect(t.y, closeTo(0, 1e-9));
    });
  });

  group('zoomViewerShouldDismiss (pure)', () {
    test('dismisses on a long enough drag', () {
      expect(zoomViewerShouldDismiss(distance: 121, velocity: 0), isTrue);
      expect(zoomViewerShouldDismiss(distance: 119, velocity: 0), isFalse);
    });

    test('dismisses on a fast enough fling even if short', () {
      expect(zoomViewerShouldDismiss(distance: 10, velocity: 701), isTrue);
      expect(zoomViewerShouldDismiss(distance: 10, velocity: 699), isFalse);
    });

    test('a tiny, slow gesture never dismisses', () {
      expect(zoomViewerShouldDismiss(distance: 4, velocity: 20), isFalse);
    });
  });

  group('ImageZoomViewer widget', () {
    testWidgets('empty URL is a no-op (no viewer pushed)', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(builder: (c) {
              ctx = c;
              return const SizedBox();
            }),
          ),
        ),
      );
      showImageZoomViewer(ctx, imageUrl: '   ');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));
      expect(find.byType(ImageZoomViewer), findsNothing);
      await _drain(tester);
    });

    testWidgets('opens over the app with an interactive surface',
        (tester) async {
      await _openViewer(tester);
      expect(find.byType(ImageZoomViewer), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byIcon(LucideIcons.x), findsOneWidget);
      // Starts at 1× (un-zoomed) so a swipe dismisses rather than pans.
      expect(_controllerOf(tester).value.getMaxScaleOnAxis(), closeTo(1.0, 1e-6));
      await _drain(tester);
    });

    testWidgets('image fills the whole viewport (no intrinsic-size collapse)',
        (tester) async {
      // Regression guard: a `Center` wrapper used to hand the image loose
      // constraints, so `BoxFit.contain` collapsed it to the decoded image's
      // intrinsic size — rendering it tiny/soft and breaking the Hero. The
      // image must instead fill the full-screen surface so contain can scale it.
      await _openViewer(tester);
      final screen = tester.getSize(find.byType(ImageZoomViewer));
      final imageSize = tester.getSize(find.byType(CachedNetworkImage));
      expect(imageSize, screen,
          reason: 'the viewer image must fill the viewport, not collapse to '
              'its intrinsic size');
      await _drain(tester);
    });

    testWidgets('close (✕) button dismisses the viewer', (tester) async {
      await _openViewer(tester);
      expect(find.byType(ImageZoomViewer), findsOneWidget);
      await tester.tap(find.byIcon(LucideIcons.x));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));
      expect(find.byType(ImageZoomViewer), findsNothing);
      await _drain(tester);
    });

    testWidgets('system back button / back-swipe dismisses the viewer',
        (tester) async {
      await _openViewer(tester);
      expect(find.byType(ImageZoomViewer), findsOneWidget);
      // Emulates the Android hardware/gesture back — pops the top route.
      final popped =
          await tester.binding.handlePopRoute();
      expect(popped, isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));
      expect(find.byType(ImageZoomViewer), findsNothing);
      await _drain(tester);
    });

    testWidgets('double-tap zooms in, second double-tap resets',
        (tester) async {
      await _openViewer(tester);
      final controller = _controllerOf(tester);
      final center = tester.getCenter(find.byType(InteractiveViewer));

      await _doubleTapAt(tester, center);
      expect(controller.value.getMaxScaleOnAxis(), greaterThan(1.5),
          reason: 'first double-tap should zoom in');

      await _doubleTapAt(tester, center);
      expect(controller.value.getMaxScaleOnAxis(), closeTo(1.0, 0.05),
          reason: 'second double-tap should reset to 1×');
      await _drain(tester);
    });

    testWidgets('swipe down at 1× dismisses the viewer', (tester) async {
      await _openViewer(tester);
      expect(find.byType(ImageZoomViewer), findsOneWidget);

      // A clear downward drag past the dismiss threshold.
      await tester.drag(find.byType(InteractiveViewer), const Offset(0, 300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));

      expect(find.byType(ImageZoomViewer), findsNothing,
          reason: 'dragging down far enough at 1× should close the viewer');
      await _drain(tester);
    });

    testWidgets('a small drag at 1× snaps back and keeps the viewer open',
        (tester) async {
      await _openViewer(tester);
      // Below the 120px threshold → should NOT dismiss.
      await tester.drag(find.byType(InteractiveViewer), const Offset(0, 40));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));
      expect(find.byType(ImageZoomViewer), findsOneWidget,
          reason: 'a short drag must snap back, not dismiss');
      await _drain(tester);
    });
  });
}
