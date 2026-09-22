// NexusLoader contract.
//
// A CustomPainter is invisible to screen readers and to `find.text`, so every
// variant must publish its status copy through a live-region Semantics node.
// That node is the a11y path AND the hook QA asserts on, so it is tested for
// all six variants, in both motion modes.

import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/presentation/widgets/nexus_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ThemeData _theme(AppColors palette) => ThemeData(
      brightness: palette.isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: palette.bg,
      extensions: <ThemeExtension<dynamic>>[palette],
    );

Future<void> _pump(
  WidgetTester tester,
  Widget loader, {
  bool reduceMotion = false,
  AppColors palette = AppColors.dark,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: _theme(palette),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(body: Center(child: loader)),
      ),
    ),
  );
  await tester.pump();
}

/// Reads the single live-region label in the tree.
String _liveLabel(WidgetTester tester) {
  final node = tester.getSemantics(
    find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.liveRegion == true,
    ),
  );
  return node.label;
}

void main() {
  const allVariants = NexusLoaderVariant.values;

  group('semantics', () {
    for (final variant in allVariants) {
      for (final reduce in const <bool>[false, true]) {
        final motion = reduce ? 'reduced motion' : 'full motion';
        testWidgets('$variant publishes a live region under $motion',
            (tester) async {
          final handle = tester.ensureSemantics();
          await _pump(
            tester,
            NexusLoader(variant: variant, progress: 0.4),
            reduceMotion: reduce,
          );
          expect(_liveLabel(tester), isNotEmpty);
          expect(tester.takeException(), isNull);
          handle.dispose();
        });
      }
    }

    testWidgets('the label is the current stage copy, not invented text',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const NexusLoader(variant: NexusLoaderVariant.research),
      );
      expect(_liveLabel(tester), NexusStageCopy.research.first);
      handle.dispose();
    });

    testWidgets('sync folds the percentage into the announcement',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const NexusLoader(variant: NexusLoaderVariant.sync, progress: 0.42),
      );
      expect(_liveLabel(tester), '${NexusStageCopy.sync} 42%');
      handle.dispose();
    });
  });

  group('stage sequence', () {
    testWidgets('advances once per interval and HOLDS on the last stage',
        (tester) async {
      await _pump(
        tester,
        const NexusLoader(variant: NexusLoaderVariant.research),
      );
      const stages = NexusStageCopy.research;
      expect(find.text(stages[0]), findsOneWidget);

      for (var i = 1; i < stages.length; i++) {
        await tester.pump(const Duration(milliseconds: 2000));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text(stages[i]), findsOneWidget, reason: 'stage $i');
      }

      // Well past the end: it must not wrap back to the first stage.
      await tester.pump(const Duration(seconds: 10));
      expect(find.text(stages.last), findsOneWidget);
      expect(find.text(stages.first), findsNothing);
    });

    testWidgets('reduced motion keeps the same clock, only cross-fading',
        (tester) async {
      await _pump(
        tester,
        const NexusLoader(variant: NexusLoaderVariant.research),
        reduceMotion: true,
      );
      expect(find.text(NexusStageCopy.research[0]), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(NexusStageCopy.research[1]), findsOneWidget);
    });

    testWidgets('the status box does not resize between stages',
        (tester) async {
      await _pump(
        tester,
        const NexusLoader(variant: NexusLoaderVariant.research),
      );
      final box = find.byKey(NexusLoader.statusKey);
      final first = tester.getSize(box);
      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getSize(box), first);
    });
  });

  group('rendering', () {
    for (final palette in const <AppColors>[AppColors.dark, AppColors.white]) {
      final name = palette.isDark ? 'dark' : 'white';
      for (final variant in allVariants) {
        testWidgets('$variant paints in the $name palette', (tester) async {
          await _pump(
            tester,
            NexusLoader(variant: variant, progress: 0.6),
            palette: palette,
          );
          await tester.pump(const Duration(milliseconds: 600));
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('research completion sequence runs without exceptions',
        (tester) async {
      await _pump(
        tester,
        const NexusLoader(variant: NexusLoaderVariant.research, complete: true),
      );
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    });

    testWidgets('vision renders determinate and indeterminate',
        (tester) async {
      for (final progress in const <double?>[null, 0.25, 1.0]) {
        await _pump(
          tester,
          NexusLoader(variant: NexusLoaderVariant.vision, progress: progress),
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('vision glides to a new level and then goes idle',
        (tester) async {
      await _pump(
        tester,
        const NexusLoader(variant: NexusLoaderVariant.vision, progress: 0.2),
      );
      // The field + breath controllers are running, so drive the widget to a
      // new progress value and let the level spring settle.
      await _pump(
        tester,
        const NexusLoader(variant: NexusLoaderVariant.vision, progress: 0.9),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a determinate vision level still moves under reduced motion',
        (tester) async {
      // Progress is information: the front must rise even when the tilt,
      // ripple and tremor are switched off.
      await _pump(
        tester,
        const NexusLoader(variant: NexusLoaderVariant.vision, progress: 0.1),
        reduceMotion: true,
      );
      await _pump(
        tester,
        const NexusLoader(variant: NexusLoaderVariant.vision, progress: 0.8),
        reduceMotion: true,
      );
      // ~1.6s: comfortably past the spring's settling time so the ticker has
      // had the chance to switch itself off.
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.takeException(), isNull);
      // Only the breathing controller is left; the level ticker stops itself
      // at rest rather than idling at 60fps.
      expect(tester.binding.transientCallbackCount, lessThanOrEqualTo(1));
    });

    testWidgets('list uses ONE controller for every row', (tester) async {
      await _pump(
        tester,
        const NexusLoader(variant: NexusLoaderVariant.list, itemCount: 6),
      );
      // Six rows, six ShaderMasks, but a single State — so a single ticker.
      expect(find.byType(ShaderMask), findsNWidgets(6));
      expect(tester.binding.transientCallbackCount, lessThanOrEqualTo(1));
    });

    testWidgets('reduced-motion list drops the shimmer but keeps the shapes',
        (tester) async {
      await _pump(
        tester,
        const NexusLoader(variant: NexusLoaderVariant.list, itemCount: 4),
        reduceMotion: true,
      );
      expect(find.byType(ShaderMask), findsNothing);
      expect(find.byType(Opacity), findsWidgets);
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('list cross-fades to real content when complete',
        (tester) async {
      await _pump(
        tester,
        const NexusLoader(
          variant: NexusLoaderVariant.list,
          complete: true,
          child: Text('real content'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('real content'), findsOneWidget);
    });
  });

  group('result', () {
    testWidgets('success draws the check and announces Done', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const NexusLoader(variant: NexusLoaderVariant.result),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 900));
      expect(_liveLabel(tester), NexusStageCopy.success);
      expect(tester.takeException(), isNull);
      handle.dispose();
    });

    testWidgets('failure shakes, then auto-reverts after 3s', (tester) async {
      var reverted = false;
      await _pump(
        tester,
        NexusLoader(
          variant: NexusLoaderVariant.result,
          result: NexusResult.failure,
          onRevert: () => reverted = true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(reverted, isFalse);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(reverted, isTrue);
    });

    testWidgets('reduced-motion failure does not translate', (tester) async {
      await _pump(
        tester,
        const NexusLoader(
          variant: NexusLoaderVariant.result,
          result: NexusResult.failure,
        ),
        reduceMotion: true,
      );
      final badge = find.byKey(NexusLoader.badgeKey);
      final at0 = tester.getTopLeft(badge);
      // The shake window. The badge must not move a pixel; only the border
      // colour cross-fades.
      for (final ms in const <int>[40, 80, 150, 220, 280]) {
        await tester.pump(Duration(milliseconds: ms));
        expect(tester.getTopLeft(badge), at0, reason: 'moved at ${ms}ms');
      }
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('full-motion failure does translate', (tester) async {
      await _pump(
        tester,
        const NexusLoader(
          variant: NexusLoaderVariant.result,
          result: NexusResult.failure,
        ),
      );
      final badge = find.byKey(NexusLoader.badgeKey);
      final at0 = tester.getTopLeft(badge);
      await tester.pump(const Duration(milliseconds: 70));
      expect(tester.getTopLeft(badge), isNot(at0));
      await tester.pump(const Duration(seconds: 4));
    });
  });
}
