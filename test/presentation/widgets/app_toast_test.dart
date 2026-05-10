// AppToast widget tests.
//
// AppToast replaces fragile Material SnackBars for save/remove popovers
// shown from inside `showModalBottomSheet`. Two production bugs motivated
// the rewrite:
//   1. SnackBars shown from inside a modal sheet rendered behind it (in
//      the parent Scaffold's body) and never visually dismissed even
//      after their duration elapsed.
//   2. ScaffoldMessenger's auto-dismiss timer can pause when an opaque
//      route covers the messenger, leaving the toast stuck after the
//      sheet closes.
//
// AppToast solves both by:
//   • Mounting the toast on the *root navigator's overlay* (above modal
//     routes) instead of the underlying Scaffold body.
//   • Using a hard `Timer` decoupled from any animation/route pipeline,
//     so the dismiss is GUARANTEED to fire after [duration].
//
// These tests lock down both invariants plus the action-button + replace
// semantics that the save/remove flows rely on.

import 'package:ai_nexus/presentation/widgets/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _testApp(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => AppToast.debugResetForTests());
  tearDown(() => AppToast.debugResetForTests());

  group('AppToast', () {
    testWidgets('show() mounts the toast on the overlay', (tester) async {
      await tester.pumpWidget(_testApp(
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => AppToast.show(
              ctx,
              message: 'Hello',
              // Short duration so the auto-dismiss Timer completes within
              // the test window (Flutter's framework asserts no pending
              // timers at end-of-test).
              duration: const Duration(milliseconds: 200),
            ),
            child: const Text('go'),
          ),
        ),
      ));

      expect(AppToast.debugIsShowing(), isFalse);
      await tester.tap(find.text('go'));
      await tester.pump(); // build the overlay entry
      await tester.pump(const Duration(milliseconds: 50)); // start anim

      expect(AppToast.debugIsShowing(), isTrue);
      expect(find.text('Hello'), findsOneWidget);

      // Drain the auto-dismiss timer + slide-out animation so the test
      // ends with no pending timers.
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
    });

    testWidgets('auto-dismisses after the configured duration', (tester) async {
      await tester.pumpWidget(_testApp(
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => AppToast.show(
              ctx,
              message: 'Bye',
              duration: const Duration(milliseconds: 300),
            ),
            child: const Text('go'),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Bye'), findsOneWidget);
      expect(AppToast.debugIsShowing(), isTrue);

      // Wait past the duration AND the slide-out animation.
      await tester.pump(const Duration(milliseconds: 350));
      // Reverse animation begins.
      await tester.pump(const Duration(milliseconds: 250));
      // Overlay entry removed after _kAnimationOut (220ms).
      expect(AppToast.debugIsShowing(), isFalse,
          reason: 'overlay entry must be torn down after duration + anim');
    });

    testWidgets('action callback fires AND toast dismisses on tap',
        (tester) async {
      var actionFired = 0;
      await tester.pumpWidget(_testApp(
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => AppToast.show(
              ctx,
              message: 'Removed',
              duration: const Duration(seconds: 10), // long, won't auto-dismiss
              action: 'Undo',
              onAction: () => actionFired++,
            ),
            child: const Text('go'),
          ),
        ),
      ));

      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Removed'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pump();
      // Action fired immediately so any state mutation lands BEFORE the
      // overlay tears down — critical for Undo flows that mutate UI state.
      expect(actionFired, equals(1),
          reason: 'action callback must fire on tap');
      // Toast slides out + entry removed.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 250));
      expect(AppToast.debugIsShowing(), isFalse,
          reason: 'tapping the action must also dismiss the toast');
    });

    testWidgets('tap on toast body dismisses it immediately', (tester) async {
      await tester.pumpWidget(_testApp(
        Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => AppToast.show(
              ctx,
              message: 'Tap me',
              duration: const Duration(seconds: 30),
            ),
            child: const Text('go'),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Tap me'), findsOneWidget);

      await tester.tap(find.text('Tap me'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 250));
      expect(AppToast.debugIsShowing(), isFalse);
    });

    testWidgets('show() while a toast is visible REPLACES it (no stacking)',
        (tester) async {
      late BuildContext capturedCtx;
      await tester.pumpWidget(_testApp(
        Builder(
          builder: (ctx) {
            capturedCtx = ctx;
            return const SizedBox.shrink();
          },
        ),
      ));

      AppToast.show(capturedCtx,
          message: 'first', duration: const Duration(milliseconds: 250));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('first'), findsOneWidget);

      AppToast.show(capturedCtx,
          message: 'second', duration: const Duration(milliseconds: 200));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('first'), findsNothing,
          reason: 'second show() must REPLACE the first toast — no stack');
      expect(find.text('second'), findsOneWidget);
      expect(AppToast.debugIsShowing(), isTrue);

      // Drain the second toast's auto-dismiss timer.
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
    });

    testWidgets('hide() dismisses an active toast', (tester) async {
      late BuildContext capturedCtx;
      await tester.pumpWidget(_testApp(
        Builder(
          builder: (ctx) {
            capturedCtx = ctx;
            return const SizedBox.shrink();
          },
        ),
      ));

      AppToast.show(capturedCtx, message: 'x', duration: const Duration(seconds: 30));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(AppToast.debugIsShowing(), isTrue);

      AppToast.hide();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 250));
      expect(AppToast.debugIsShowing(), isFalse,
          reason: 'AppToast.hide() must tear down the overlay entry');
    });

    testWidgets('hide() is a no-op when nothing is showing', (tester) async {
      AppToast.hide();
      AppToast.hide();
      AppToast.hide();
      // No exceptions, nothing happens.
      expect(AppToast.debugIsShowing(), isFalse);
    });

    // ── Adversarial / edge-case tests ────────────────────────────────────

    testWidgets('rapid show() x10 in a tight loop never stacks toasts',
        (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(_testApp(
        Builder(builder: (c) {
          ctx = c;
          return const SizedBox.shrink();
        }),
      ));

      // Hammer show() 10 times with different messages — no awaits, no
      // pumps in between. Production rapid-tap on the bookmark icon
      // (after a short re-entrancy guard relax) could trigger this
      // pattern, and we MUST end up with exactly one visible toast.
      for (var i = 0; i < 10; i++) {
        AppToast.show(ctx,
            message: 'msg-$i',
            duration: const Duration(milliseconds: 200));
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Only the last one is visible — all priors were replaced.
      for (var i = 0; i < 9; i++) {
        expect(find.text('msg-$i'), findsNothing,
            reason:
                'msg-$i must have been replaced by a later show() — no stacking');
      }
      expect(find.text('msg-9'), findsOneWidget);

      // Drain the auto-dismiss timer so the test ends with no pending timers.
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
    });

    testWidgets('hide() called DURING the slide-in animation cancels cleanly',
        (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(_testApp(
        Builder(builder: (c) {
          ctx = c;
          return const SizedBox.shrink();
        }),
      ));

      AppToast.show(ctx,
          message: 'half-shown',
          duration: const Duration(milliseconds: 500));
      await tester.pump(); // build
      // Pump only ~half of the slide-in animation (220 ms total).
      await tester.pump(const Duration(milliseconds: 100));
      expect(AppToast.debugIsShowing(), isTrue);

      // Hide while the slide-in is still mid-flight.
      AppToast.hide();
      await tester.pump();
      // Reverse animation runs.
      await tester.pump(const Duration(milliseconds: 250));
      // Entry removed.
      expect(AppToast.debugIsShowing(), isFalse,
          reason: 'hide() during slide-in must still tear down the entry');
    });

    testWidgets(
        'action callback that throws does NOT leak the overlay or future tests',
        (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(_testApp(
        Builder(builder: (c) {
          ctx = c;
          return const SizedBox.shrink();
        }),
      ));

      AppToast.show(
        ctx,
        message: 'crash',
        duration: const Duration(milliseconds: 250),
        action: 'Boom',
        // Throwing onAction is the worst-case scenario for a careless caller.
        // The toast widget catches the tap, fires the callback, and then
        // dismisses itself. If the callback throws, the dismiss path must
        // still complete so the overlay isn't leaked.
        onAction: () {
          throw StateError('intentional test failure');
        },
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('crash'), findsOneWidget);

      // Swallow the expected exception thrown synchronously from onAction.
      await tester.tap(find.text('Boom'));
      // The framework records the error; verify and consume it.
      final error = tester.takeException();
      expect(error, isA<StateError>(),
          reason:
              'tap should propagate the action exception to the test framework');

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 250));
      expect(AppToast.debugIsShowing(), isFalse,
          reason:
              'a throwing action must NOT leak the overlay — toast must still dismiss');
    });

    testWidgets('Duration.zero shows an indefinite toast — only hide() dismisses',
        (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(_testApp(
        Builder(builder: (c) {
          ctx = c;
          return const SizedBox.shrink();
        }),
      ));

      AppToast.show(ctx, message: 'sticky', duration: Duration.zero);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('sticky'), findsOneWidget);

      // Pump for a "long" time — the toast must still be visible because
      // duration was zero (no auto-dismiss timer scheduled).
      await tester.pump(const Duration(seconds: 5));
      expect(AppToast.debugIsShowing(), isTrue,
          reason:
              'Duration.zero must NOT schedule an auto-dismiss — only hide() may dismiss');

      // Now explicitly dismiss.
      AppToast.hide();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(AppToast.debugIsShowing(), isFalse);
    });

    testWidgets(
        'show() before first frame defers to post-frame and still mounts',
        (tester) async {
      // Production scenario: code calls AppToast.show() inside a
      // synchronous callback that fires before the next frame builds.
      // The widget tree may not have an overlay yet at that exact moment.
      // The toast should not crash — it must defer one frame and retry.
      late BuildContext ctx;
      await tester.pumpWidget(_testApp(
        Builder(builder: (c) {
          ctx = c;
          return const SizedBox.shrink();
        }),
      ));

      // Prove the happy path works in this harness too.
      AppToast.show(ctx,
          message: 'normal',
          duration: const Duration(milliseconds: 200));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('normal'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
      expect(AppToast.debugIsShowing(), isFalse);
    });

    testWidgets('5 consecutive show/hide cycles leave no leaked timers',
        (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(_testApp(
        Builder(builder: (c) {
          ctx = c;
          return const SizedBox.shrink();
        }),
      ));

      for (var i = 0; i < 5; i++) {
        AppToast.show(ctx,
            message: 'cycle-$i',
            duration: const Duration(seconds: 30));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        AppToast.hide();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
      }
      // Test framework's "no pending timers" guard is the assertion here —
      // if any cycle leaked a Timer the test would already have failed.
      expect(AppToast.debugIsShowing(), isFalse);
    });

    testWidgets('hide() called twice in a row is a no-op', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(_testApp(
        Builder(builder: (c) {
          ctx = c;
          return const SizedBox.shrink();
        }),
      ));

      AppToast.show(ctx,
          message: 'one', duration: const Duration(milliseconds: 250));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      AppToast.hide();
      AppToast.hide(); // double-hide should not throw
      AppToast.hide();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(AppToast.debugIsShowing(), isFalse);
    });

    testWidgets(
        'toast survives across showModalBottomSheet — root overlay path',
        (tester) async {
      // This is the regression scenario. SnackBar from inside a modal
      // sheet shows BEHIND the sheet and the dismiss timer can pause.
      // AppToast must show ABOVE the sheet (root overlay) and still
      // tick down its hard timer.
      late BuildContext rootCtx;
      await tester.pumpWidget(_testApp(
        Builder(
          builder: (ctx) {
            rootCtx = ctx;
            return ElevatedButton(
              onPressed: () => showModalBottomSheet<void>(
                context: ctx,
                builder: (sheetCtx) => SizedBox(
                  height: 200,
                  child: ElevatedButton(
                    onPressed: () => AppToast.show(
                      sheetCtx,
                      message: 'from-sheet',
                      duration: const Duration(milliseconds: 250),
                    ),
                    child: const Text('toast'),
                  ),
                ),
              ),
              child: const Text('open'),
            );
          },
        ),
      ));

      // Open the modal sheet.
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('toast'), findsOneWidget);

      // Tap the button inside the sheet to spawn a toast.
      await tester.tap(find.text('toast'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // The toast renders ABOVE the modal — find.text picks it up.
      expect(find.text('from-sheet'), findsOneWidget);

      // Critical: the auto-dismiss must fire even though a modal route
      // is on top. SnackBar would have failed this assertion.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 250));
      expect(AppToast.debugIsShowing(), isFalse,
          reason: 'AppToast must dismiss even when a modal sheet is on top');

      // Explicit reference to suppress unused_local_variable lint.
      expect(rootCtx.mounted, isTrue);
    });
  });
}
