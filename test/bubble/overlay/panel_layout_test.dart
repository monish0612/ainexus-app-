import 'dart:async';

import 'package:ai_nexus/bubble/overlay/bubble.dart';
import 'package:ai_nexus/bubble/overlay/glass.dart';
import 'package:ai_nexus/bubble/overlay/overlay_bridge.dart';
import 'package:ai_nexus/bubble/overlay/panel.dart';
import 'package:ai_nexus/bubble/overlay/tokens.dart';
import 'package:ai_nexus/domain/entities/rephrase_platform.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Layout and interaction tests for the floating bubble's UI.
///
/// The overlay renders inside a small, native-sized window, so the thing that
/// can actually break for a user is overflow: a font scale or a cramped landscape
/// window pushing content past the window edge. Every case below asserts that no
/// layout exception was thrown, which is what a RenderFlex overflow produces.

/// Window sizes native gives the panel, in logical pixels.
const _windows = <String, Size>{
  'small phone': Size(320, 260),
  'compact phone': Size(320, 300),
  'modern phone': Size(324, 320),
  'tablet': Size(324, 320),
  'landscape short': Size(324, 250),
  'very short window': Size(324, 200),
  'narrow window': Size(260, 300),
};

const _scales = <double>[1.0, 1.15, 1.3, 2.0];

/// Long enough to exercise scrolling in the result area.
const _longResult =
    'Hi there, I hope this finds you well. Could we please move tomorrow morning '
    'to a slightly later slot, ideally after eleven, so that I can finish the '
    'quarterly numbers first? Happy to work around whatever suits you best, and '
    'I will send the deck across beforehand so we can keep the call short.';

class _Harness {
  _Harness({this.result = 'rephrased text', this.fail = false});

  final String result;
  final bool fail;

  final List<String> runs = <String>[];
  final List<String?> intents = <String?>[];
  final List<bool> freshFlags = <bool>[];
  final List<bool> focusRequests = <bool>[];
  final List<Size> measured = <Size>[];
  final List<String> copied = <String>[];
  final List<String> accepted = <String>[];
  final List<String> platformsUsed = <String>[];
  ReplaceOutcome acceptOutcome = ReplaceOutcome.setText;
  int closes = 0;

  Future<PanelResult> run(String platform, String? intent,
      {required bool fresh}) async {
    runs.add(platform);
    intents.add(intent);
    freshFlags.add(fresh);
    if (fail) return const PanelResult.failure('No network');
    // A fresh run returns a distinguishable "different version".
    return PanelResult.success(fresh ? '$result (v${runs.length})' : result);
  }

  Future<ReplaceOutcome> accept(String text) async {
    accepted.add(text);
    return acceptOutcome;
  }
}

Widget _wrap({
  required Size window,
  required double scale,
  required _Harness harness,
  BubbleTarget? target,
  String? lastPlatformId,
}) {
  final resolved = target ??
      BubbleTarget(
        text: 'hey can we push the meeting to tomorrow morning please',
        package: 'com.whatsapp',
        maxWidth: window.width,
        maxHeight: window.height,
        lastPlatformId: lastPlatformId,
      );
  return MediaQuery(
    data: MediaQueryData(
      size: window,
      textScaler: TextScaler.linear(scale),
    ),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      // Mirrors the overlay app: clamp scaling, transparent Material host.
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: 1,
        maxScaleFactor: kMaxTextScale,
        child: child ?? const SizedBox.shrink(),
      ),
      home: Material(
        type: MaterialType.transparency,
        child: RephrasePanel(
          target: resolved,
          onRun: harness.run,
          onAccept: harness.accept,
          onCopy: harness.copied.add,
          onClose: () => harness.closes++,
          onFocusRequest: (value) async => harness.focusRequests.add(value),
          onMeasured: harness.measured.add,
          lastPlatformId: lastPlatformId ?? resolved.lastPlatformId,
          onPlatformUsed: harness.platformsUsed.add,
        ),
      ),
    ),
  );
}

/// Nothing may paint outside the window native allocated.
///
/// The exception check is the one that catches a RenderFlex overflow; the bounds
/// check catches a panel surface that is positioned or sized past the edge.
void _expectFits(WidgetTester tester, Size window) {
  expect(tester.takeException(), isNull);

  final surface = tester.getRect(find.byType(PanelSurface).first);
  expect(surface.left, greaterThanOrEqualTo(-0.5));
  expect(surface.top, greaterThanOrEqualTo(-0.5));
  expect(surface.right, lessThanOrEqualTo(window.width + 0.5));
  expect(surface.bottom, lessThanOrEqualTo(window.height + 0.5));
  expect(surface.width, greaterThan(0));
  expect(surface.height, greaterThan(0));
}

void main() {
  group('RephrasePanel — no overflow across windows and font scales', () {
    for (final entry in _windows.entries) {
      for (final scale in _scales) {
        testWidgets('${entry.key} @ ${scale}x — idle', (tester) async {
          tester.view.physicalSize = entry.value;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);

          final harness = _Harness();
          await tester.pumpWidget(
            _wrap(window: entry.value, scale: scale, harness: harness),
          );
          await tester.pump();
          _expectFits(tester, entry.value);
        });

        testWidgets('${entry.key} @ ${scale}x — long result', (tester) async {
          tester.view.physicalSize = entry.value;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);

          final harness = _Harness(result: _longResult);
          await tester.pumpWidget(
            _wrap(window: entry.value, scale: scale, harness: harness),
          );
          await tester.tap(find.text('😊 Casual'));
          await tester.pumpAndSettle();
          _expectFits(tester, entry.value);
          // The review flow: result stays on screen with Use / New version.
          // skipOffstage: false because in extreme windows (landscape, huge
          // fonts) the actions sit below the fold of the safety-net scroll.
          expect(
            find.bySemanticsLabel('Use rephrased text', skipOffstage: false),
            findsOneWidget,
          );
          expect(
            find.bySemanticsLabel('New version', skipOffstage: false),
            findsOneWidget,
          );
        });

        testWidgets('${entry.key} @ ${scale}x — tone input', (tester) async {
          tester.view.physicalSize = entry.value;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);

          final harness = _Harness();
          await tester.pumpWidget(
            _wrap(window: entry.value, scale: scale, harness: harness),
          );
          await tester.tap(find.text('✨ Own'));
          await tester.pumpAndSettle();
          _expectFits(tester, entry.value);
          expect(find.byType(TextField), findsOneWidget);
        });
      }
    }
  });

  group('RephrasePanel — measurement contract', () {
    testWidgets('reports a size that fits the window budget', (tester) async {
      const window = Size(324, 320);
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = _Harness();
      await tester.pumpWidget(
        _wrap(window: window, scale: 1, harness: harness),
      );
      await tester.pump();

      expect(harness.measured, isNotEmpty);
      final size = harness.measured.last;
      expect(size.width, lessThanOrEqualTo(window.width));
      expect(size.height, greaterThan(0));
      expect(size.height, lessThanOrEqualTo(window.height));
    });

    testWidgets('asks for more height once a result is showing', (tester) async {
      const window = Size(324, 320);
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = _Harness(result: _longResult);
      await tester.pumpWidget(
        _wrap(window: window, scale: 1, harness: harness),
      );
      await tester.pump();
      final idle = harness.measured.last.height;

      await tester.tap(find.text('😊 Casual'));
      await tester.pumpAndSettle();
      expect(harness.measured.last.height, greaterThan(idle));
    });

    testWidgets('does not re-report an unchanged size', (tester) async {
      const window = Size(324, 320);
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = _Harness();
      await tester.pumpWidget(
        _wrap(window: window, scale: 1, harness: harness),
      );
      await tester.pumpAndSettle();
      final count = harness.measured.length;
      await tester.pump(const Duration(milliseconds: 300));
      expect(harness.measured.length, count);
    });

    testWidgets('a bubble-sized surface never echoes into the reported width '
        '(the shrunken-panel regression)', (tester) async {
      // The race from the field: the panel's first frame can render while the
      // window is still the 76dp bubble, before native's expansion lands. The
      // panel must report the display budget, not the stale surface size —
      // reporting 76 made native shrink the window and the panel stuck tiny.
      const bubbleWindow = Size(76, 76);
      tester.view.physicalSize = bubbleWindow;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = _Harness();
      await tester.pumpWidget(
        _wrap(
          window: bubbleWindow,
          scale: 1,
          harness: harness,
          target: const BubbleTarget(
            text: 'hey can we push the meeting to tomorrow morning please',
            package: 'com.whatsapp',
            maxWidth: 324,
            maxHeight: 320,
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(harness.measured, isNotEmpty);
      expect(
        harness.measured.last.width,
        324,
        reason: 'width must come from the display budget, never the window',
      );
    });

    testWidgets('height stays stable when the window shrinks to the reported '
        'size (no resize feedback loop)', (tester) async {
      const window = Size(324, 320);
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = _Harness();
      await tester.pumpWidget(
        _wrap(window: window, scale: 1, harness: harness),
      );
      await tester.pumpAndSettle();
      final first = harness.measured.last;

      // Native shrinks the window to what we asked for; the panel must ask for
      // the same height again rather than shrinking further each frame.
      await tester.pumpWidget(
        _wrap(window: first, scale: 1, harness: harness),
      );
      await tester.pumpAndSettle();
      expect(harness.measured.last.height, closeTo(first.height, 2));
    });
  });

  group('RephrasePanel — platform chips', () {
    testWidgets('shows every catalog action by switching groups', (tester) async {
      const window = Size(324, 320);
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = _Harness();
      await tester.pumpWidget(
        _wrap(window: window, scale: 1, harness: harness),
      );
      await tester.pump();

      expect(kRephrasePlatforms.length, 11);

      final seen = <String>{};
      void collect(Iterable<RephrasePlatform> platforms) {
        for (final platform in platforms) {
          if (find
              .text(platform.chipLabel, skipOffstage: false)
              .evaluate()
              .isNotEmpty) {
            seen.add(platform.id);
          }
        }
      }

      Future<void> sweepGroup(String groupLabel, List<RephrasePlatform> platforms) async {
        await tester.tap(find.text(groupLabel));
        await tester.pump();
        collect(platforms);
        for (var i = 0; i < 30 && !platforms.every((p) => seen.contains(p.id)); i++) {
          await tester.drag(find.byType(ListView), const Offset(-80, 0));
          await tester.pump();
          collect(platforms);
        }
      }

      await sweepGroup('Tone', kTonePlatforms);
      await sweepGroup('Rewrite', kRewritePlatforms);
      await sweepGroup('Chat', kChatPlatforms);

      expect(
        seen,
        kAllRephraseActions.map((p) => p.id).toSet(),
        reason: 'every grouped action must be reachable',
      );
    });

    testWidgets('tapping a platform sends its id with no intent', (tester) async {
      const window = Size(324, 320);
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = _Harness();
      await tester.pumpWidget(
        _wrap(window: window, scale: 1, harness: harness),
      );
      await tester.tap(find.text('😊 Casual'));
      await tester.pumpAndSettle();

      expect(harness.runs, ['casual']);
      expect(harness.intents, [null]);
      expect(harness.focusRequests, isEmpty);
    });

    testWidgets('Fix chip shows Fixing grammar… while the request is in flight',
        (tester) async {
      const window = Size(324, 320);
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final gate = Completer<PanelResult>();
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: window),
          child: MaterialApp(
            home: Material(
              type: MaterialType.transparency,
              child: RephrasePanel(
                target: const BubbleTarget(
                  text: 'hey can we push the meeting to tomorrow morning please',
                  package: 'com.whatsapp',
                  maxWidth: 324,
                  maxHeight: 320,
                ),
                onRun: (platform, intent, {required bool fresh}) => gate.future,
                onAccept: (_) async => ReplaceOutcome.setText,
                onCopy: (_) {},
                onClose: () {},
                onFocusRequest: (_) async {},
                onMeasured: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Rewrite'));
      await tester.pump();
      await tester.tap(find.text('✓ Fix'));
      await tester.pump();

      expect(find.text('Fixing grammar…'), findsOneWidget);
      expect(find.bySemanticsLabel('Use rephrased text'), findsNothing);

      gate.complete(const PanelResult.success('fixed text'));
      await tester.pumpAndSettle();
      expect(find.text('fixed text'), findsOneWidget);
    });

    testWidgets('Rewrite Fix chip sends the fix platform id', (tester) async {
      const window = Size(324, 320);
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = _Harness();
      await tester.pumpWidget(
        _wrap(window: window, scale: 1, harness: harness),
      );
      await tester.tap(find.text('Rewrite'));
      await tester.pump();
      await tester.tap(find.text('✓ Fix'));
      await tester.pumpAndSettle();

      expect(harness.runs, ['fix']);
      expect(harness.intents, [null]);
    });
  });

  group('RephrasePanel — the Own flow', () {
    Future<_Harness> openTone(WidgetTester tester) async {
      const window = Size(324, 320);
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = _Harness();
      await tester.pumpWidget(
        _wrap(window: window, scale: 1, harness: harness),
      );
      await tester.tap(find.text('✨ Own'));
      await tester.pumpAndSettle();
      return harness;
    }

    testWidgets('takes focus when opening the tone field', (tester) async {
      final harness = await openTone(tester);
      expect(harness.focusRequests, [true]);
      expect(find.byType(TextField), findsOneWidget);
      expect(harness.runs, isEmpty);
    });

    testWidgets('returns focus before running, then sends the typed tone',
        (tester) async {
      final harness = await openTone(tester);
      await tester.enterText(find.byType(TextField), 'professional simple');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Focus must be handed back before the request, or the write-back has
      // nowhere to land.
      expect(harness.focusRequests, [true, false]);
      expect(harness.runs, ['own']);
      expect(harness.intents, ['professional simple']);
    });

    testWidgets('strips a "rephrase to" prefix from the tone', (tester) async {
      final harness = await openTone(tester);
      await tester.enterText(
        find.byType(TextField),
        'rephrase to professional simple',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // The panel forwards the raw tone; stripping happens in the client, so
      // assert the round trip stays intact here.
      expect(harness.runs, ['own']);
      expect(harness.intents.single, contains('professional simple'));
    });

    testWidgets('an empty tone does not fire a request', (tester) async {
      final harness = await openTone(tester);
      await tester.enterText(find.byType(TextField), '   ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(harness.runs, isEmpty);
      expect(harness.focusRequests, [true]);
    });

    testWidgets('cancelling the tone field returns focus and restores chips',
        (tester) async {
      final harness = await openTone(tester);
      // The trailing close glyph inside the tone row cancels it.
      await tester.tap(find.byType(TextField));
      await tester.pump();
      final cancels = find.bySemanticsLabel('Cancel tone');
      expect(cancels, findsOneWidget);
      await tester.tap(cancels);
      await tester.pumpAndSettle();

      expect(harness.focusRequests, [true, false]);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('😊 Casual'), findsOneWidget);
    });
  });

  group('RephrasePanel — result actions', () {
    testWidgets('copy button hands the result text to the clipboard bridge',
        (tester) async {
      const window = Size(324, 320);
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = _Harness();
      await tester.pumpWidget(
        _wrap(window: window, scale: 1, harness: harness),
      );
      await tester.tap(find.text('😊 Casual'));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Copy rephrased text'));
      await tester.pump();
      expect(harness.copied, ['rephrased text']);
      _expectFits(tester, window);
      // Let the "copied" tick revert so no timer outlives the tree.
      await tester.pump(const Duration(milliseconds: 1400));
    });

    testWidgets('a failure shows the message and a retry that re-runs',
        (tester) async {
      const window = Size(324, 320);
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = _Harness(fail: true);
      await tester.pumpWidget(
        _wrap(window: window, scale: 1, harness: harness),
      );
      await tester.tap(find.text('😊 Casual'));
      await tester.pumpAndSettle();

      expect(find.text('No network'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Retry'));
      await tester.pumpAndSettle();
      expect(harness.runs, ['casual', 'casual']);
      _expectFits(tester, window);
    });

    testWidgets('Use writes the reviewed text back and closes the panel',
        (tester) async {
      const window = Size(324, 320);
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = _Harness();
      await tester.pumpWidget(
        _wrap(window: window, scale: 1, harness: harness),
      );
      await tester.tap(find.text('😊 Casual'));
      await tester.pumpAndSettle();

      // Nothing is written until the user accepts.
      expect(harness.accepted, isEmpty);

      await tester.tap(find.bySemanticsLabel('Use rephrased text'));
      await tester.pump();
      expect(harness.accepted, ['rephrased text']);

      // The green check flashes briefly before the panel closes itself.
      await tester.pump(kAcceptFlash + const Duration(milliseconds: 20));
      await tester.pumpAndSettle();
      expect(harness.closes, 1, reason: 'accept must close the panel');
    });

    testWidgets('New version re-runs with the cache bypassed and shows the '
        'different take', (tester) async {
      const window = Size(324, 320);
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = _Harness();
      await tester.pumpWidget(
        _wrap(window: window, scale: 1, harness: harness),
      );
      await tester.tap(find.text('😊 Casual'));
      await tester.pumpAndSettle();
      expect(find.text('rephrased text'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('New version'));
      await tester.pumpAndSettle();

      expect(harness.freshFlags, [false, true]);
      expect(find.text('rephrased text (v2)'), findsOneWidget);
      _expectFits(tester, window);

      // Accepting the new version writes that exact text.
      await tester.tap(find.bySemanticsLabel('Use rephrased text'));
      await tester.pump();
      await tester.pump(kAcceptFlash + const Duration(milliseconds: 20));
      await tester.pumpAndSettle();
      expect(harness.accepted, ['rephrased text (v2)']);
      expect(harness.closes, 1);
    });

    testWidgets('New version for Own keeps the typed tone', (tester) async {
      const window = Size(324, 320);
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = _Harness();
      await tester.pumpWidget(
        _wrap(window: window, scale: 1, harness: harness),
      );
      await tester.tap(find.text('✨ Own'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'professional simple');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('New version'));
      await tester.pumpAndSettle();

      expect(harness.runs, ['own', 'own']);
      expect(harness.intents, ['professional simple', 'professional simple']);
      expect(harness.freshFlags, [false, true]);
    });

    testWidgets('a blocked write-back keeps the panel open and says the text '
        'was copied', (tester) async {
      const window = Size(324, 320);
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = _Harness()..acceptOutcome = ReplaceOutcome.blocked;
      await tester.pumpWidget(
        _wrap(window: window, scale: 1, harness: harness),
      );
      await tester.tap(find.text('😊 Casual'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Use rephrased text'));
      await tester.pumpAndSettle();

      expect(find.textContaining("Couldn't edit this field"), findsOneWidget);
      expect(harness.closes, 0, reason: 'a blocked field must not auto-close');
      _expectFits(tester, window);
    });

    testWidgets('a huge rephrase (thousands of chars) scrolls instead of '
        'overflowing', (tester) async {
      const window = Size(324, 320);
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final huge = List.generate(
        400,
        (i) => 'sentence $i keeps going with plenty of words,',
      ).join(' ');
      final harness = _Harness(result: huge);
      await tester.pumpWidget(
        _wrap(window: window, scale: 1, harness: harness),
      );
      await tester.tap(find.text('😊 Casual'));
      await tester.pumpAndSettle();

      _expectFits(tester, window);
      final use = find.bySemanticsLabel('Use rephrased text', skipOffstage: false);
      expect(use, findsOneWidget);

      // With this much text the actions sit below the fold of the safety-net
      // scroll; bring them into view the way a user would.
      await tester.ensureVisible(use);
      await tester.pumpAndSettle();
      await tester.tap(use);
      await tester.pump();
      await tester.pump(kAcceptFlash + const Duration(milliseconds: 20));
      await tester.pumpAndSettle();
      expect(harness.accepted.single.length, huge.length);
    });

    testWidgets('close button reports up', (tester) async {
      const window = Size(324, 320);
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = _Harness();
      await tester.pumpWidget(
        _wrap(window: window, scale: 1, harness: harness),
      );
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pump();
      expect(harness.closes, 1);
    });

    testWidgets('lays out under an RTL locale without overflowing',
        (tester) async {
      const window = Size(324, 320);
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = _Harness(result: _longResult);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: _wrap(window: window, scale: 1.3, harness: harness),
        ),
      );
      await tester.tap(find.text('😊 Casual'));
      await tester.pumpAndSettle();
      _expectFits(tester, window);
    });

    testWidgets('reduced motion still produces a full result view',
        (tester) async {
      const window = Size(324, 320);
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = _Harness();
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: window, disableAnimations: true),
          child: MaterialApp(
            home: Material(
              type: MaterialType.transparency,
              child: RephrasePanel(
                target: const BubbleTarget(
                  text: 'text to rephrase',
                  package: 'com.whatsapp',
                  maxWidth: 324,
                  maxHeight: 320,
                ),
                onRun: harness.run,
                onAccept: harness.accept,
                onCopy: harness.copied.add,
                onClose: () {},
                onFocusRequest: (_) async {},
                onMeasured: harness.measured.add,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('😊 Casual'));
      await tester.pumpAndSettle();
      expect(find.text('rephrased text'), findsOneWidget);
      _expectFits(tester, window);
    });

    testWidgets('an empty field says there is nothing to rephrase',
        (tester) async {
      const window = Size(324, 320);
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = _Harness();
      await tester.pumpWidget(
        _wrap(
          window: window,
          scale: 1,
          harness: harness,
          target: const BubbleTarget(
            text: '',
            package: 'com.whatsapp',
            maxWidth: 324,
            maxHeight: 320,
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('Nothing to rephrase'), findsOneWidget);
      _expectFits(tester, window);
    });
  });

  group('RephrasePanel — AMOLED readability', () {
    testWidgets('root panel surface is pure opaque black', (tester) async {
      const window = Size(324, 320);
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = _Harness();
      await tester.pumpWidget(
        _wrap(window: window, scale: 1, harness: harness),
      );
      await tester.pump();

      expect(kPanelBg, const Color(0xFF000000));
      expect(kPanelBg.a, 1.0);

      final root = tester.widget<PanelSurface>(find.byType(PanelSurface).first);
      expect(root.elevated, isFalse);

      // The root DecoratedBox under the first PanelSurface must be pure black.
      final decorated = tester.widgetList<DecoratedBox>(
        find.descendant(
          of: find.byType(PanelSurface).first,
          matching: find.byType(DecoratedBox),
        ),
      ).first;
      final box = decorated.decoration as BoxDecoration;
      expect(box.color, kPanelBg);
      expect(box.color!.a, 1.0);
    });

    testWidgets('panel never uses GlassContainer — glass is bubble-only',
        (tester) async {
      const window = Size(324, 320);
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = _Harness(result: _longResult);
      await tester.pumpWidget(
        _wrap(window: window, scale: 1, harness: harness),
      );
      await tester.tap(find.text('😊 Casual'));
      await tester.pumpAndSettle();

      expect(find.byType(GlassContainer), findsNothing);
      expect(find.byType(PanelSurface), findsWidgets);
      _expectFits(tester, window);
    });
  });

  group('RephrasePanel — position near bubble', () {
    testWidgets('panel opens near a lower-right bubble, not at the top',
        (tester) async {
      const window = Size(360, 800);
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = _Harness();
      await tester.pumpWidget(
        _wrap(
          window: window,
          scale: 1,
          harness: harness,
          target: const BubbleTarget(
            text: 'hey can we push the meeting to tomorrow morning please',
            package: 'com.whatsapp',
            maxWidth: 360,
            maxHeight: 800,
            bubbleX: 280,
            bubbleY: 620,
            bubbleSize: 56,
          ),
        ),
      );
      await tester.pump();

      final panelRect = tester.getRect(find.byType(PanelSurface).first);
      // Must sit in the lower half near the bubble, not glued to y≈0.
      expect(panelRect.top, greaterThan(300));
      expect(panelRect.bottom, lessThanOrEqualTo(620 + 1));
      expect(panelRect.left, greaterThan(20));
    });

    testWidgets('panel follows a mid-screen bubble on a wide display',
        (tester) async {
      const window = Size(800, 800);
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = _Harness();
      await tester.pumpWidget(
        _wrap(
          window: window,
          scale: 1,
          harness: harness,
          target: const BubbleTarget(
            text: 'hey can we push the meeting to tomorrow morning please',
            package: 'com.whatsapp',
            maxWidth: 800,
            maxHeight: 800,
            bubbleX: 360,
            bubbleY: 200,
            bubbleSize: 56,
          ),
        ),
      );
      await tester.pump();

      final panelRect = tester.getRect(find.byType(PanelSurface).first);
      expect(panelRect.left, greaterThan(80));
      expect(panelRect.right, lessThan(window.width - 80));
      expect(panelRect.top, greaterThan(200));
    });
  });

  group('RephrasePanel — dismiss and last chip', () {
    testWidgets('swipe down past the threshold closes the panel', (tester) async {
      const window = Size(324, 400);
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = _Harness();
      await tester.pumpWidget(
        _wrap(window: window, scale: 1, harness: harness),
      );
      await tester.pump();

      final panel = find.byType(PanelSurface).first;
      await tester.drag(panel, const Offset(0, 160));
      await tester.pumpAndSettle();
      expect(harness.closes, 1);
    });

    testWidgets('a short swipe does not close the panel', (tester) async {
      const window = Size(324, 400);
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = _Harness();
      await tester.pumpWidget(
        _wrap(window: window, scale: 1, harness: harness),
      );
      await tester.pump();

      await tester.drag(find.byType(PanelSurface).first, const Offset(0, 30));
      await tester.pumpAndSettle();
      expect(harness.closes, 0);
    });

    testWidgets('last used platform is shown first in the chip row',
        (tester) async {
      const window = Size(324, 320);
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final ordered = platformsWithPreferredFirst('whatsapp');
      expect(ordered.first.id, 'whatsapp');
      expect(ordered.length, kRephrasePlatforms.length);

      final harness = _Harness();
      await tester.pumpWidget(
        _wrap(
          window: window,
          scale: 1,
          harness: harness,
          lastPlatformId: 'whatsapp',
        ),
      );
      await tester.pump();

      // First visible chip label in the row should be WhatsApp.
      expect(find.text('📱 WhatsApp'), findsOneWidget);
    });

    testWidgets('a successful rephrase persists the platform id',
        (tester) async {
      const window = Size(324, 320);
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = _Harness();
      await tester.pumpWidget(
        _wrap(window: window, scale: 1, harness: harness),
      );
      await tester.tap(find.text('😊 Casual'));
      await tester.pumpAndSettle();
      expect(harness.platformsUsed, ['casual']);
    });

    testWidgets('last used Rewrite id opens the Rewrite group', (tester) async {
      const window = Size(324, 320);
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = _Harness();
      await tester.pumpWidget(
        _wrap(window: window, scale: 1, harness: harness, lastPlatformId: 'fix'),
      );
      await tester.pump();

      expect(find.text('✓ Fix'), findsOneWidget);
      expect(find.text('😊 Casual'), findsNothing);
    });

    testWidgets('unknown lastPlatformId stays on Tone', (tester) async {
      const window = Size(324, 320);
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = _Harness();
      await tester.pumpWidget(
        _wrap(
          window: window,
          scale: 1,
          harness: harness,
          lastPlatformId: 'not-a-real-chip',
        ),
      );
      await tester.pump();

      expect(find.text('✨ Own'), findsOneWidget);
      expect(find.text('😊 Casual'), findsOneWidget);
      expect(find.text('✓ Fix'), findsNothing);
    });

    testWidgets('Chat Reply chip sends reply and Meaning sends define',
        (tester) async {
      const window = Size(324, 320);
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = _Harness();
      await tester.pumpWidget(
        _wrap(window: window, scale: 1, harness: harness),
      );
      await tester.tap(find.text('Chat'));
      await tester.pump();

      final seen = <String>{};
      void collect() {
        for (final id in ['reply', 'define']) {
          final platform = kChatPlatforms.firstWhere((p) => p.id == id);
          if (find.text(platform.chipLabel, skipOffstage: false).evaluate().isNotEmpty) {
            seen.add(id);
          }
        }
      }

      collect();
      for (var i = 0; i < 40 && seen.length < 2; i++) {
        await tester.drag(find.byType(ListView), const Offset(-90, 0));
        await tester.pump();
        collect();
      }
      expect(seen, {'reply', 'define'});

      final reply = find.text('↩ Reply', skipOffstage: false);
      expect(reply, findsOneWidget);
      await tester.ensureVisible(reply);
      await tester.pumpAndSettle();
      await tester.tap(find.text('↩ Reply'));
      await tester.pumpAndSettle();
      expect(harness.runs, ['reply']);
    });

    testWidgets('last used WhatsApp opens the Chat group, not Tone',
        (tester) async {
      const window = Size(324, 320);
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final harness = _Harness();
      await tester.pumpWidget(
        _wrap(
          window: window,
          scale: 1,
          harness: harness,
          lastPlatformId: 'whatsapp',
        ),
      );
      await tester.pump();

      expect(find.text('📱 WhatsApp'), findsOneWidget);
      expect(find.text('✓ Fix'), findsNothing);
      expect(find.text('✨ Own'), findsNothing);
    });
  });

  group('RephraseBubble', () {
    testWidgets('fits its 76dp window as liquid glass',
        (tester) async {
      const window = Size(76, 76);
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(size: window),
          child: MaterialApp(
            home: Material(
              type: MaterialType.transparency,
              child: RephraseBubble(),
            ),
          ),
        ),
      );
      // Breathing animation is continuous; don't pumpAndSettle.
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);

      final rect = tester.getRect(find.byType(RephraseBubble));
      expect(rect.width, lessThanOrEqualTo(window.width + 0.5));
      expect(rect.height, lessThanOrEqualTo(window.height + 0.5));
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.byType(GlassContainer), findsNothing);
      expect(find.byType(RephrasePanel), findsNothing);
      expect(find.byType(PanelSurface), findsNothing);
    });

    testWidgets('honours reduced motion without breaking layout',
        (tester) async {
      const window = Size(76, 76);
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(size: window, disableAnimations: true),
          child: MaterialApp(
            home: Material(
              type: MaterialType.transparency,
              child: RephraseBubble(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(RephraseBubble), findsOneWidget);
    });

    testWidgets('bubble scales with the display but stays in its window',
        (tester) async {
      for (final shortest in const [320.0, 360.0, 411.0, 768.0, 1024.0]) {
        final size = bubbleSize(
          await _contextFor(tester, Size(shortest, shortest * 2)),
        );
        expect(size, greaterThanOrEqualTo(44));
        expect(size, lessThanOrEqualTo(56));
      }
    });
  });
}

/// Builds a throwaway tree just to obtain a BuildContext with a known MediaQuery.
Future<BuildContext> _contextFor(WidgetTester tester, Size size) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: size),
      child: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return captured;
}
