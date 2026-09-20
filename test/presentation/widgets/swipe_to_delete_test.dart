// Widget tests for [SwipeToDelete] — the generic swipe wrapper used by
// the News > For You feed (All, AI News, Finance, Movies, General).
//
// CONTRACT
//
//   • Swiping the child in EITHER direction (LTR or RTL) past the
//     dismiss threshold opens the confirm card. [onDelete] fires only
//     after tapping Delete.
//   • Keep / barrier dismiss / back / swipe-back leave the row and
//     do not call [onDelete].
//   • The child widget is NEVER actually dismissed — `confirmDismiss`
//     returns false. This is the inline-delete pattern; the host data
//     layer is the single source of truth for "is the row gone now?".
//   • Cancelled / under-threshold swipes do NOT fire `onDelete` and
//     do NOT open the confirm card.
//   • The red background renders a trash icon + "Delete" label so the
//     user sees what the gesture does mid-drag.
//
// EDGE CASES COVERED
//
//   • borderRadius: 0 (flat list card) and 24 (rounded featured card)
//     both render without overflow.
//   • contentHeight forces the background to a fixed height (used by
//     the 280 px featured card so the red bg matches the card exactly).
//   • Rapid double-swipe is idempotent — onDelete fires per confirmed
//     swipe, never more.
//   • Default key fallback (ObjectKey) doesn't blow up if a caller
//     forgets to pass `key`.
//   • Missing AppColors extension still paints the confirm card.
//   • Empty / very long titles do not overflow.
//   • Light + dark themes on a 320 px phone.
//   • confirm: false keeps the instant-delete path used by pager tests.

import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/presentation/widgets/swipe_to_delete.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

class _Probe {
  int count = 0;
  void Function() get cb => () => count++;
}

Future<void> _pumpWith(
  WidgetTester tester, {
  required Widget child,
  required VoidCallback onDelete,
  double borderRadius = 0,
  double? contentHeight,
  Key? key,
  bool confirm = true,
  String? title,
  String? message,
  String headline = 'Delete this?',
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 600,
          child: ListView(
            children: [
              SwipeToDelete(
                key: key,
                onDelete: onDelete,
                confirm: confirm,
                headline: headline,
                title: title,
                message: message,
                borderRadius: borderRadius,
                contentHeight: contentHeight,
                child: child,
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _commitSwipe(
  WidgetTester tester,
  Finder target, {
  Offset delta = const Offset(380, 0),
}) async {
  await tester.drag(target, delta);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 180));
}

Future<void> _tapConfirm(WidgetTester tester) async {
  expect(find.byKey(const Key('swipe-delete-confirm')), findsOneWidget);
  await tester.tap(find.byKey(const Key('swipe-delete-confirm')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _tapKeep(WidgetTester tester) async {
  expect(find.byKey(const Key('swipe-delete-keep')), findsOneWidget);
  await tester.tap(find.byKey(const Key('swipe-delete-keep')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  Widget card(String id) => Container(
        key: ValueKey<String>('card-$id'),
        height: 90,
        color: Colors.blue,
        alignment: Alignment.center,
        child: Text('Card $id'),
      );

  group('SwipeToDelete — basic rendering', () {
    testWidgets('renders the child without swipe affordance idle',
        (tester) async {
      final probe = _Probe();
      await _pumpWith(
        tester,
        key: const ValueKey<String>('row-a'),
        child: card('A'),
        onDelete: probe.cb,
      );

      expect(find.text('Card A'), findsOneWidget);
      // Trash icon is only visible during a drag; idle the bg is not
      // painted on screen (Dismissible doesn't render the background
      // unless the child is being dragged).
      expect(find.text('Delete'), findsNothing);
      expect(find.byKey(const Key('swipe-delete-confirm')), findsNothing);
      expect(probe.count, 0);
    });

    testWidgets('exposes a Dismissible in the tree', (tester) async {
      await _pumpWith(
        tester,
        key: const ValueKey<String>('row-a'),
        child: card('A'),
        onDelete: () {},
      );
      expect(find.byType(Dismissible), findsOneWidget);
    });
  });

  group('SwipeToDelete — swipe requires confirmation', () {
    testWidgets('LEFT-to-RIGHT swipe past threshold asks, then Delete fires',
        (tester) async {
      final probe = _Probe();
      await _pumpWith(
        tester,
        key: const ValueKey<String>('row-a'),
        title: 'Finance headline',
        child: card('A'),
        onDelete: probe.cb,
      );

      await _commitSwipe(tester, find.text('Card A'));
      expect(probe.count, 0, reason: 'must not delete before confirm');
      expect(find.text('Delete this?'), findsOneWidget);
      expect(find.text('Finance headline'), findsOneWidget);
      expect(find.text('Card A'), findsOneWidget);

      await _tapConfirm(tester);
      expect(probe.count, 1);
      expect(find.byKey(const Key('swipe-delete-confirm')), findsNothing);
      expect(find.text('Card A'), findsOneWidget);
    });

    testWidgets('RIGHT-to-LEFT swipe past threshold asks, then Delete fires',
        (tester) async {
      final probe = _Probe();
      await _pumpWith(
        tester,
        key: const ValueKey<String>('row-b'),
        child: card('B'),
        onDelete: probe.cb,
      );

      await _commitSwipe(
        tester,
        find.text('Card B'),
        delta: const Offset(-380, 0),
      );
      expect(probe.count, 0);
      await _tapConfirm(tester);
      expect(probe.count, 1);
      expect(find.text('Card B'), findsOneWidget);
    });

    testWidgets('Keep snaps back and does not fire onDelete', (tester) async {
      final probe = _Probe();
      await _pumpWith(
        tester,
        key: const ValueKey<String>('row-keep'),
        child: card('K'),
        onDelete: probe.cb,
      );

      await _commitSwipe(tester, find.text('Card K'));
      await _tapKeep(tester);

      expect(probe.count, 0);
      expect(find.text('Card K'), findsOneWidget);
      expect(find.byType(Dismissible), findsOneWidget);
    });

    testWidgets('barrier tap is a keep — no delete', (tester) async {
      final probe = _Probe();
      await _pumpWith(
        tester,
        key: const ValueKey<String>('row-barrier'),
        child: card('Z'),
        onDelete: probe.cb,
      );

      await _commitSwipe(tester, find.text('Card Z'));
      expect(find.byKey(const Key('swipe-delete-confirm')), findsOneWidget);

      await tester.tapAt(const Offset(8, 8));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(probe.count, 0);
      expect(find.byKey(const Key('swipe-delete-confirm')), findsNothing);
      expect(find.text('Card Z'), findsOneWidget);
    });

    testWidgets('system back is a keep — no delete', (tester) async {
      final probe = _Probe();
      await _pumpWith(
        tester,
        key: const ValueKey<String>('row-back'),
        child: card('Y'),
        onDelete: probe.cb,
      );

      await _commitSwipe(tester, find.text('Card Y'));
      expect(find.byKey(const Key('swipe-delete-confirm')), findsOneWidget);

      final popped = await tester.binding.handlePopRoute();
      expect(popped, isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(probe.count, 0);
      expect(find.byKey(const Key('swipe-delete-confirm')), findsNothing);
      expect(find.text('Card Y'), findsOneWidget);
    });

    testWidgets('left-edge swipe-back on the overlay is a keep', (tester) async {
      final probe = _Probe();
      await _pumpWith(
        tester,
        key: const ValueKey<String>('row-edge'),
        child: card('E'),
        onDelete: probe.cb,
      );

      await _commitSwipe(tester, find.text('Card E'));
      expect(find.byKey(const Key('swipe-delete-confirm-barrier')), findsOneWidget);
      expect(find.text('Card E').hitTestable(), findsNothing,
          reason: 'overlay must swallow pointers so the article cannot be swiped');

      final gesture = await tester.startGesture(const Offset(16, 48));
      await tester.pump();
      await gesture.moveBy(const Offset(180, 0));
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(probe.count, 0, reason: 'swipe-back must not delete');
      expect(find.byKey(const Key('swipe-delete-confirm')), findsNothing);
      expect(find.text('Card E'), findsOneWidget);
    });

    testWidgets('right-edge swipe-back on the overlay is a keep', (tester) async {
      final probe = _Probe();
      await _pumpWith(
        tester,
        key: const ValueKey<String>('row-edge-r'),
        child: card('Q'),
        onDelete: probe.cb,
      );

      await _commitSwipe(tester, find.text('Card Q'));
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      final gesture =
          await tester.startGesture(Offset(size.width - 16, 48));
      await tester.pump();
      await gesture.moveBy(const Offset(-180, 0));
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(probe.count, 0);
      expect(find.byKey(const Key('swipe-delete-confirm')), findsNothing);
      expect(find.text('Card Q'), findsOneWidget);
    });

    testWidgets('swipe the popup card away (LTR) is a keep', (tester) async {
      final probe = _Probe();
      await _pumpWith(
        tester,
        key: const ValueKey<String>('row-card-swipe'),
        child: card('S'),
        onDelete: probe.cb,
      );

      await _commitSwipe(tester, find.text('Card S'));
      await tester.drag(find.text('Delete this?'), const Offset(180, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(probe.count, 0);
      expect(find.byKey(const Key('swipe-delete-confirm')), findsNothing);
      expect(find.text('Card S'), findsOneWidget);
    });

    testWidgets('swipe the popup card away (RTL) is a keep', (tester) async {
      final probe = _Probe();
      await _pumpWith(
        tester,
        key: const ValueKey<String>('row-card-rtl'),
        child: card('T'),
        onDelete: probe.cb,
      );

      await _commitSwipe(tester, find.text('Card T'));
      await tester.drag(find.text('Delete this?'), const Offset(-180, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(probe.count, 0);
      expect(find.byKey(const Key('swipe-delete-confirm')), findsNothing);
    });

    testWidgets('swipe the popup down is a keep', (tester) async {
      final probe = _Probe();
      await _pumpWith(
        tester,
        key: const ValueKey<String>('row-card-down'),
        child: card('U'),
        onDelete: probe.cb,
      );

      await _commitSwipe(tester, find.text('Card U'));
      await tester.drag(find.text('Delete this?'), const Offset(0, 180));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(probe.count, 0);
      expect(find.byKey(const Key('swipe-delete-confirm')), findsNothing);
    });

    testWidgets('tiny pan on the popup snaps back and stays open',
        (tester) async {
      final probe = _Probe();
      await _pumpWith(
        tester,
        key: const ValueKey<String>('row-tiny'),
        child: card('V'),
        onDelete: probe.cb,
      );

      await _commitSwipe(tester, find.text('Card V'));
      await tester.drag(find.text('Delete this?'), const Offset(18, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(probe.count, 0);
      expect(find.byKey(const Key('swipe-delete-confirm')), findsOneWidget);
      await _tapKeep(tester);
    });

    testWidgets('swipe-back keep then a later Delete still works',
        (tester) async {
      final probe = _Probe();
      await _pumpWith(
        tester,
        key: const ValueKey<String>('row-after-back'),
        child: card('W'),
        onDelete: probe.cb,
      );

      await _commitSwipe(tester, find.text('Card W'));
      final gesture = await tester.startGesture(const Offset(16, 48));
      await tester.pump();
      await gesture.moveBy(const Offset(180, 0));
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(probe.count, 0);

      await _commitSwipe(tester, find.text('Card W'));
      await _tapConfirm(tester);
      expect(probe.count, 1);
    });

    testWidgets('small drag UNDER threshold does NOT fire onDelete',
        (tester) async {
      final probe = _Probe();
      await _pumpWith(
        tester,
        key: const ValueKey<String>('row-c'),
        child: card('C'),
        onDelete: probe.cb,
      );

      // Only 50 px of 400 (~12 %) — well under the 30 % threshold.
      await tester.drag(find.text('Card C'), const Offset(50, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(probe.count, 0);
      expect(find.byKey(const Key('swipe-delete-confirm')), findsNothing);
      expect(find.text('Card C'), findsOneWidget);
    });

    testWidgets(
        'swipe past threshold followed by a snap-back still leaves the '
        'row in the tree (inline-delete invariant)', (tester) async {
      final probe = _Probe();
      await _pumpWith(
        tester,
        key: const ValueKey<String>('row-d'),
        child: card('D'),
        onDelete: probe.cb,
      );

      await _commitSwipe(tester, find.text('Card D'));
      await _tapConfirm(tester);
      await tester.pump(const Duration(milliseconds: 250));

      expect(probe.count, 1, reason: 'onDelete fired exactly once');
      expect(find.byType(Dismissible), findsOneWidget,
          reason: 'Dismissible widget stays mounted after a swipe');
    });

    testWidgets('Keep then a second swipe+Delete fires onDelete once',
        (tester) async {
      final probe = _Probe();
      await _pumpWith(
        tester,
        key: const ValueKey<String>('row-retry'),
        child: card('R'),
        onDelete: probe.cb,
      );

      await _commitSwipe(tester, find.text('Card R'));
      await _tapKeep(tester);
      expect(probe.count, 0);

      await _commitSwipe(tester, find.text('Card R'));
      await _tapConfirm(tester);
      expect(probe.count, 1);
    });

    testWidgets('confirm:false still deletes instantly (pager-test path)',
        (tester) async {
      final probe = _Probe();
      await _pumpWith(
        tester,
        key: const ValueKey<String>('row-instant'),
        confirm: false,
        child: card('I'),
        onDelete: probe.cb,
      );

      await tester.drag(find.text('Card I'), const Offset(380, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('swipe-delete-confirm')), findsNothing);
      expect(probe.count, 1);
    });
  });

  group('SwipeToDelete — background visuals', () {
    testWidgets(
        'background widgets are wired into the Dismissible '
        '(both directions exposed)', (tester) async {
      final probe = _Probe();
      await _pumpWith(
        tester,
        key: const ValueKey<String>('row-e'),
        child: card('E'),
        onDelete: probe.cb,
      );

      final dismissible =
          tester.widget<Dismissible>(find.byType(Dismissible));

      expect(dismissible.background, isA<SwipeDeleteBackground>());
      expect(dismissible.secondaryBackground, isA<SwipeDeleteBackground>());

      final leading = dismissible.background! as SwipeDeleteBackground;
      final trailing = dismissible.secondaryBackground! as SwipeDeleteBackground;
      expect(leading.alignEnd, isFalse,
          reason: 'leading-edge (start-to-end) bg must align to left');
      expect(trailing.alignEnd, isTrue,
          reason: 'trailing-edge (end-to-start) bg must align to right');
    });

    testWidgets('borderRadius=24 renders without overflow (featured card)',
        (tester) async {
      await _pumpWith(
        tester,
        key: const ValueKey<String>('row-feat'),
        borderRadius: 24,
        contentHeight: 280,
        child: Container(
          height: 280,
          color: Colors.blue,
          alignment: Alignment.center,
          child: const Text('Featured'),
        ),
        onDelete: () {},
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Featured'), findsOneWidget);
    });
  });

  group('SwipeDeleteConfirmCard — copy and themes', () {
    Future<void> pumpCard(
      WidgetTester tester, {
      required AppColors colors,
      String headline = 'Delete this article?',
      String? title,
      String? message,
      Size size = const Size(360, 640),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: colors.isDark ? Brightness.dark : Brightness.light,
            extensions: <ThemeExtension<dynamic>>[colors],
          ),
          home: Scaffold(
            backgroundColor: colors.bg,
            body: Center(
              child: SwipeDeleteConfirmCard(
                colors: colors,
                headline: headline,
                title: title,
                message: message,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    for (final colors in [AppColors.white, AppColors.dark]) {
      final label = colors.isDark ? 'dark' : 'light';
      testWidgets('$label confirm card fits a 320px phone', (tester) async {
        await pumpCard(
          tester,
          colors: colors,
          title: 'A reasonably long finance headline about markets',
          message: 'Remove from Finance. It will not come back on refresh.',
          size: const Size(320, 568),
        );

        expect(find.text('Delete this article?'), findsOneWidget);
        expect(find.byKey(const Key('swipe-delete-keep')), findsOneWidget);
        expect(find.byKey(const Key('swipe-delete-confirm')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('empty title and message omit those lines', (tester) async {
      await pumpCard(
        tester,
        colors: AppColors.white,
        title: '   ',
        message: '',
      );
      expect(find.text('Delete this article?'), findsOneWidget);
      expect(find.text('   '), findsNothing);
    });

    testWidgets('very long title does not overflow', (tester) async {
      await pumpCard(
        tester,
        colors: AppColors.dark,
        title: 'X' * 240,
        message: 'Remove from AI News. It will not come back on refresh.',
        size: const Size(320, 568),
      );
      expect(tester.takeException(), isNull);
      final titleFinder = find.text('X' * 240);
      expect(titleFinder, findsOneWidget);
      final size = tester.getSize(titleFinder);
      expect(size.height, lessThan(48));
    });
  });

  group('SwipeDeleteBackground — direct rendering', () {
    testWidgets('leading-edge variant aligns trash to the left',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 100,
              child: SwipeDeleteBackground(alignEnd: false),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(LucideIcons.trash2), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      final iconPos = tester.getCenter(find.byIcon(LucideIcons.trash2));
      expect(iconPos.dx, lessThan(150));
    });

    testWidgets('trailing-edge variant aligns trash to the right',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 100,
              child: SwipeDeleteBackground(alignEnd: true),
            ),
          ),
        ),
      );
      await tester.pump();

      final iconPos = tester.getCenter(find.byIcon(LucideIcons.trash2));
      expect(iconPos.dx, greaterThan(150));
    });

    testWidgets('explicit height is respected', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: SwipeDeleteBackground(
                  alignEnd: false,
                  height: 200,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final bgFinder = find.byType(SwipeDeleteBackground);
      final size = tester.getSize(bgFinder);
      expect(size.height, 200);
    });
  });

  group('SwipeToDelete — defensive fallbacks', () {
    testWidgets('omitting `key` falls back to ObjectKey (no crash)',
        (tester) async {
      await _pumpWith(
        tester,
        child: card('X'),
        onDelete: () {},
      );

      expect(find.byType(Dismissible), findsOneWidget);
      expect(find.text('Card X'), findsOneWidget);
    });

    testWidgets('missing AppColors still opens confirm', (tester) async {
      final probe = _Probe();
      await _pumpWith(
        tester,
        key: const ValueKey<String>('row-nocolor'),
        theme: ThemeData(brightness: Brightness.light),
        child: card('N'),
        onDelete: probe.cb,
      );

      await _commitSwipe(tester, find.text('Card N'));
      expect(find.byKey(const Key('swipe-delete-confirm')), findsOneWidget);
      await _tapKeep(tester);
      expect(probe.count, 0);
    });
  });
}
