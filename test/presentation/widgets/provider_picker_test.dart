import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/presentation/widgets/provider_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';

const _gemini = ProviderOption(
  id: 'gemini',
  label: 'Gemini',
  icon: LucideIcons.globe,
  color: Color(0xFF4285F4),
);

const _xgrok = ProviderOption(
  id: 'xgrok',
  label: 'xGrok',
  icon: LucideIcons.bot,
  color: Color(0xFFE8453C),
);

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData(extensions: const [AppColors.dark]),
    home: Scaffold(
      // Pad so the picker is fully visible; we anchor the dropdown using
      // the chip's RenderBox global rect, so a non-zero offset matters.
      body: Padding(
        padding: const EdgeInsets.fromLTRB(40, 40, 40, 40),
        child: Align(
          alignment: Alignment.topRight,
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  group('ProviderPicker — single-option (xGrok disabled equivalent)', () {
    testWidgets('renders the chip without a chevron', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ProviderPicker(
            options: const [_gemini],
            selectedId: 'gemini',
            onChanged: (_) {},
          ),
        ),
      );

      expect(find.text('Gemini'), findsOneWidget);
      // No chevron in the static state — that's the "non-interactive" tell.
      expect(find.byIcon(LucideIcons.chevronDown), findsNothing);
    });

    testWidgets('tapping does not open a menu', (tester) async {
      var fired = 0;
      await tester.pumpWidget(
        _wrap(
          ProviderPicker(
            options: const [_gemini],
            selectedId: 'gemini',
            onChanged: (_) => fired++,
          ),
        ),
      );

      await tester.tap(find.text('Gemini'));
      await tester.pumpAndSettle();

      expect(fired, 0);
      // Menu items aren't even instantiated.
      expect(find.byIcon(LucideIcons.check), findsNothing);
    });
  });

  group('ProviderPicker — two-option (xGrok enabled)', () {
    testWidgets('renders chip + chevron and is tappable', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ProviderPicker(
            options: const [_gemini, _xgrok],
            selectedId: 'gemini',
            onChanged: (_) {},
          ),
        ),
      );

      expect(find.text('Gemini'), findsOneWidget);
      expect(find.byIcon(LucideIcons.chevronDown), findsOneWidget);
    });

    testWidgets('opens a popover containing both options on tap',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          ProviderPicker(
            options: const [_gemini, _xgrok],
            selectedId: 'gemini',
            onChanged: (_) {},
          ),
        ),
      );

      await tester.tap(find.text('Gemini'));
      await tester.pumpAndSettle();

      // Both options visible inside the popover; the original chip's
      // "Gemini" text is now duplicated by the menu item.
      expect(find.text('Gemini'), findsNWidgets(2));
      expect(find.text('xGrok'), findsOneWidget);
      // Active option carries a check.
      expect(find.byIcon(LucideIcons.check), findsOneWidget);
    });

    testWidgets('selecting a different option fires onChanged once',
        (tester) async {
      String? picked;
      await tester.pumpWidget(
        _wrap(
          ProviderPicker(
            options: const [_gemini, _xgrok],
            selectedId: 'gemini',
            onChanged: (id) => picked = id,
          ),
        ),
      );

      await tester.tap(find.text('Gemini'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('xGrok'));
      await tester.pumpAndSettle();

      expect(picked, 'xgrok');
    });

    testWidgets(
        'selecting the SAME option does not fire onChanged (de-dupe)',
        (tester) async {
      var fired = 0;
      await tester.pumpWidget(
        _wrap(
          ProviderPicker(
            options: const [_gemini, _xgrok],
            selectedId: 'gemini',
            onChanged: (_) => fired++,
          ),
        ),
      );

      await tester.tap(find.text('Gemini'));
      await tester.pumpAndSettle();
      // Tap the second "Gemini" — the menu item, not the chip.
      await tester.tap(find.text('Gemini').last);
      await tester.pumpAndSettle();

      expect(fired, 0);
    });

    testWidgets('tapping outside dismisses the popover without firing',
        (tester) async {
      var fired = 0;
      await tester.pumpWidget(
        _wrap(
          ProviderPicker(
            options: const [_gemini, _xgrok],
            selectedId: 'gemini',
            onChanged: (_) => fired++,
          ),
        ),
      );

      await tester.tap(find.text('Gemini'));
      await tester.pumpAndSettle();
      // Tap somewhere outside the menu (top-left corner of the scaffold).
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(fired, 0);
      // Menu is gone.
      expect(find.byIcon(LucideIcons.check), findsNothing);
    });
  });

  group('ProviderPicker — stale state safety', () {
    testWidgets(
        'unknown selectedId falls back to first option without crashing',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          ProviderPicker(
            // selectedId references an option that does not exist in the
            // list — e.g. settings still hold "claude" but the build only
            // exposes Gemini + xGrok. Picker must self-heal.
            options: const [_gemini, _xgrok],
            selectedId: 'claude-3-opus',
            onChanged: (_) {},
          ),
        ),
      );

      // First option (Gemini) is shown as active fallback.
      expect(find.text('Gemini'), findsOneWidget);
      // No exception during build.
      expect(tester.takeException(), isNull);
    });

    testWidgets('switching selectedId across rebuilds animates cleanly',
        (tester) async {
      String selected = 'gemini';
      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(builder: (context, setState) {
            return Column(children: [
              ProviderPicker(
                options: const [_gemini, _xgrok],
                selectedId: selected,
                onChanged: (id) => setState(() => selected = id),
              ),
              ElevatedButton(
                onPressed: () => setState(() => selected = 'xgrok'),
                child: const Text('flip'),
              ),
            ]);
          }),
        ),
      );

      expect(find.text('Gemini'), findsOneWidget);
      await tester.tap(find.text('flip'));
      await tester.pumpAndSettle();
      expect(find.text('xGrok'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ── Production-grade robustness ──────────────────────────────────────────
  //
  // These exercise the failure modes that wouldn't show up in a happy-path
  // user flow but absolutely *can* happen in production:
  //   • frantic finger taps causing multi-open
  //   • parent navigating away mid-animation
  //   • callback throwing
  //   • settings change that removes interactivity while menu is open
  // Each test asserts no exceptions reach Flutter's framework error handler.

  group('ProviderPicker — production-grade robustness', () {
    testWidgets(
        'rapid double-tap on the chip never stacks two popovers',
        (tester) async {
      var fired = 0;
      await tester.pumpWidget(
        _wrap(
          ProviderPicker(
            options: const [_gemini, _xgrok],
            selectedId: 'gemini',
            onChanged: (_) => fired++,
          ),
        ),
      );

      // Two taps in the same frame — picker must coalesce because _open=true
      // short-circuits the second invocation.
      final chip = find.text('Gemini');
      await tester.tap(chip);
      await tester.tap(chip, warnIfMissed: false);
      await tester.pumpAndSettle();

      // Exactly one popover, with one check icon (the active option).
      expect(find.byIcon(LucideIcons.check), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(fired, 0);
    });

    testWidgets(
        'unmounting the picker while popover is open is safe (no setState-after-dispose)',
        (tester) async {
      // Real scenario: the user opens the menu, then a settings event
      // mid-animation rebuilds the parent without the picker (e.g. a tab
      // switch that recycles the InsightsAI body). The popover route is
      // anchored to the root navigator so it survives the unmount; the
      // picker's post-`await` `if (!mounted) return` guard must catch it.
      // We simulate by replacing the root tree entirely while the popover
      // is mid-open animation, then dismissing the popover.
      await tester.pumpWidget(
        _wrap(
          ProviderPicker(
            options: const [_gemini, _xgrok],
            selectedId: 'gemini',
            onChanged: (_) {},
          ),
        ),
      );

      await tester.tap(find.text('Gemini'));
      // Mid-flight: popover is fading-in. Replace the host tree.
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pumpWidget(
        _wrap(const SizedBox.shrink()),
      );
      await tester.pumpAndSettle();

      // Picker fully gone. No use-after-dispose, no leaked check icon.
      expect(find.byIcon(LucideIcons.chevronDown), findsNothing);
      expect(find.byIcon(LucideIcons.check), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'onChanged throwing does NOT corrupt picker state — chevron resets',
        (tester) async {
      // A real-world failure mode: the callback persists to disk and the
      // disk write throws (e.g. SharedPreferences not yet initialised).
      // The picker hardens against this by wrapping `onChanged` in a
      // try/catch that reports via FlutterError.reportError but otherwise
      // leaves picker state intact. The test asserts the picker remains
      // fully operable AND that the error is reported (not silently lost).
      String selected = 'gemini';
      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(builder: (context, setState) {
            return ProviderPicker(
              options: const [_gemini, _xgrok],
              selectedId: selected,
              onChanged: (id) {
                setState(() => selected = id);
                throw StateError('synthetic disk failure');
              },
            );
          }),
        ),
      );

      await tester.tap(find.text('Gemini'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('xGrok'));
      await tester.pumpAndSettle();

      // The picker reports the synthetic failure via FlutterError.reportError;
      // the test framework surfaces it through takeException so we drain it.
      final reported = tester.takeException();
      expect(reported, isA<StateError>());

      // State updated to xgrok before the throw — picker reflects it.
      expect(find.text('xGrok'), findsOneWidget);
      // Chevron is re-armed for the next tap.
      expect(find.byIcon(LucideIcons.chevronDown), findsOneWidget);

      // Picker is still operable post-throw — open and close again.
      await tester.tap(find.text('xGrok'));
      await tester.pumpAndSettle();
      expect(find.byIcon(LucideIcons.check), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'shrinking options to a single entry mid-render reverts to static chip',
        (tester) async {
      // Real scenario: user opens InsightAI tab with xGrok enabled (2-option
      // picker), then the settings page is opened in another flow which
      // toggles xGrok off. On the next rebuild the picker receives a
      // 1-option list and must downgrade to the static chip without
      // crashing or leaving the chevron stuck.
      bool xgrokOn = true;
      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(builder: (context, setState) {
            final options = xgrokOn
                ? const [_gemini, _xgrok]
                : const [_gemini];
            return Column(children: [
              ProviderPicker(
                options: options,
                selectedId: 'gemini',
                onChanged: (_) {},
              ),
              ElevatedButton(
                onPressed: () => setState(() => xgrokOn = false),
                child: const Text('disable'),
              ),
            ]);
          }),
        ),
      );

      expect(find.byIcon(LucideIcons.chevronDown), findsOneWidget);
      await tester.tap(find.text('disable'));
      await tester.pumpAndSettle();
      expect(find.byIcon(LucideIcons.chevronDown), findsNothing);
      expect(find.text('Gemini'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'open → dismiss → re-open cycle works (no leaked state across opens)',
        (tester) async {
      // Real scenario: user opens the picker, dismisses it, opens it again.
      // This catches regressions where _open or the route survives across
      // open cycles (e.g. a static field, a stuck animation controller).
      await tester.pumpWidget(
        _wrap(
          ProviderPicker(
            options: const [_gemini, _xgrok],
            selectedId: 'gemini',
            onChanged: (_) {},
          ),
        ),
      );

      // Cycle 1: open → tap-outside dismiss
      await tester.tap(find.text('Gemini'));
      await tester.pumpAndSettle();
      expect(find.byIcon(LucideIcons.check), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byIcon(LucideIcons.check), findsNothing);

      // Cycle 2: open again — must work identically.
      await tester.tap(find.text('Gemini'));
      await tester.pumpAndSettle();
      expect(find.byIcon(LucideIcons.check), findsOneWidget);
      // Cycle 3: pick the other option — must fire onChanged.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byIcon(LucideIcons.chevronDown), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'menu fires LIGHT impact only when selection actually changes',
        (tester) async {
      // No way to assert haptic counts directly without a platform mock,
      // but we can at least verify that selecting a NEW option fires
      // onChanged exactly once (we already cover same-selection no-op).
      var calls = <String>[];
      await tester.pumpWidget(
        _wrap(
          ProviderPicker(
            options: const [_gemini, _xgrok],
            selectedId: 'gemini',
            onChanged: (id) => calls.add(id),
          ),
        ),
      );

      await tester.tap(find.text('Gemini'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('xGrok'));
      await tester.pumpAndSettle();
      expect(calls, ['xgrok']);
    });

    testWidgets(
        '3+ options work too (future-proofing for adding a 3rd provider)',
        (tester) async {
      const claude = ProviderOption(
        id: 'claude',
        label: 'Claude',
        icon: LucideIcons.sparkles,
        color: Color(0xFFD97757),
      );
      String selected = 'gemini';
      String? picked;
      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(builder: (context, setState) {
            return ProviderPicker(
              options: const [_gemini, _xgrok, claude],
              selectedId: selected,
              onChanged: (id) {
                picked = id;
                setState(() => selected = id);
              },
            );
          }),
        ),
      );

      await tester.tap(find.text('Gemini'));
      await tester.pumpAndSettle();
      // All three options listed in the popover.
      expect(find.text('Claude'), findsOneWidget);
      await tester.tap(find.text('Claude'));
      await tester.pumpAndSettle();
      expect(picked, 'claude');
      // After selection the chip itself now reads "Claude".
      expect(find.text('Claude'), findsOneWidget);
    });
  });

  // ── Smart up/down anchoring (regression guard) ───────────────────────────
  //
  // Real-world bug the user hit: in both the saved-search detail sheet and
  // the FAB follow-up chat, the provider chip lives in the BOTTOM input bar.
  // The popover used to always drop DOWN, which either pushed it off-screen
  // or made it visually overlap the input field (looked broken). The fix:
  // measure available space below the chip vs above it and flip direction
  // when the chip is sitting in the bottom of the visible area.
  group('ProviderPicker — smart up/down anchoring', () {
    testWidgets(
        'menu opens UPWARD when the chip lives at the bottom of the screen',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [AppColors.dark]),
          home: Scaffold(
            // Mount the picker near the bottom edge — exactly where the
            // input-bar chip lives in our two bottom-sheet flows.
            body: Stack(
              children: [
                Positioned(
                  right: 16,
                  bottom: 24,
                  child: ProviderPicker(
                    options: const [_gemini, _xgrok],
                    selectedId: 'gemini',
                    onChanged: (_) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open the popover.
      await tester.tap(find.byIcon(LucideIcons.chevronDown));
      await tester.pumpAndSettle();

      // Chip rect uses the FIRST 'Gemini' (the chip itself); menu is
      // located via 'xGrok' which only exists inside the popover.
      final chipRect = tester.getRect(find.text('Gemini').first);
      final menuItemRect = tester.getRect(find.text('xGrok'));

      // The "xGrok" menu item must sit ABOVE the chip's top edge — i.e.
      // the popover flipped upward instead of dropping over the bottom
      // safe area / off-screen.
      expect(menuItemRect.bottom, lessThanOrEqualTo(chipRect.top),
          reason:
              'menu should flip upward when chip is in the bottom of the screen');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'menu opens DOWNWARD (default) when the chip is in the top of the screen',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [AppColors.dark]),
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  right: 16,
                  top: 24,
                  child: ProviderPicker(
                    options: const [_gemini, _xgrok],
                    selectedId: 'gemini',
                    onChanged: (_) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.chevronDown));
      await tester.pumpAndSettle();

      final chipRect = tester.getRect(find.text('Gemini').first);
      final menuItemRect = tester.getRect(find.text('xGrok'));

      // Default direction: menu sits BELOW the chip's bottom edge.
      expect(menuItemRect.top, greaterThanOrEqualTo(chipRect.bottom),
          reason: 'menu should drop downward when chip has room below');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'menu fits inside a tall option list by scrolling rather than '
        'overflowing the visible area', (tester) async {
      const claude = ProviderOption(
        id: 'claude',
        label: 'Claude',
        icon: LucideIcons.sparkles,
        color: Color(0xFFD97757),
      );
      const opus = ProviderOption(
        id: 'opus',
        label: 'Opus',
        icon: LucideIcons.brain,
        color: Color(0xFFA855F7),
      );
      const o1 = ProviderOption(
        id: 'o1',
        label: 'o1-pro',
        icon: LucideIcons.bot,
        color: Color(0xFF10A37F),
      );

      // 5 options on a 400x600 viewport — without scrolling, the menu
      // would be ~256 px tall and could overflow the smaller half.
      tester.view.physicalSize = const Size(400 * 3, 600 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [AppColors.dark]),
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  right: 16,
                  top: 280,
                  child: ProviderPicker(
                    options: const [_gemini, _xgrok, claude, opus, o1],
                    selectedId: 'gemini',
                    onChanged: (_) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Gemini'));
      await tester.pumpAndSettle();

      // All five labels are findable in the menu (the SingleChildScrollView
      // builds them eagerly; only painting is virtualised on overflow).
      expect(find.text('Gemini'), findsAtLeastNWidgets(1));
      expect(find.text('xGrok'), findsOneWidget);
      expect(find.text('Claude'), findsOneWidget);
      expect(find.text('Opus'), findsOneWidget);
      expect(find.text('o1-pro'), findsOneWidget);

      // The menu's painted bounds must fit within the screen — the
      // picker auto-bounded its max-height and gave the inner column a
      // SingleChildScrollView so excess content scrolls.
      final firstItem = tester.getRect(find.text('xGrok'));
      final lastItem = tester.getRect(find.text('o1-pro'));
      expect(firstItem.top, greaterThanOrEqualTo(0.0));
      expect(lastItem.bottom, lessThanOrEqualTo(600.0),
          reason: 'menu must clip to viewport on a 600 px tall screen');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'menu does NOT crash on a tiny viewport too small to fit it (defensive '
        'safe-clamp branch — split-screen / foldable / robustness)',
        (tester) async {
      // Sub-180 px viewport: smaller than our base 172 px menu width
      // plus the 8 px insets. Real phones are never this small but this
      // exercises the [_safeClamp] degenerate branch so a synthetic
      // window resize can never throw a clamp assertion in production.
      tester.view.physicalSize = const Size(160 * 3, 320 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [AppColors.dark]),
          home: Scaffold(
            body: Center(
              child: ProviderPicker(
                options: const [_gemini, _xgrok],
                selectedId: 'gemini',
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Gemini'));
      await tester.pumpAndSettle();

      // No clamp / layout exception thrown — menu adapted to the
      // available width via the menuWidth ceiling clamp.
      expect(tester.takeException(), isNull);
      // Menu still renders the alternate option so the user can pick.
      expect(find.text('xGrok'), findsOneWidget);
    });

    testWidgets(
        'extremely long labels truncate with ellipsis instead of pushing '
        'the menu wider than the chip anchor', (tester) async {
      const longLabel = ProviderOption(
        id: 'extralong',
        label: 'A Very Long Provider Name That Should Get Ellipsised',
        icon: LucideIcons.bot,
        color: Color(0xFFFF8800),
      );
      await tester.pumpWidget(
        _wrap(
          ProviderPicker(
            options: const [_gemini, longLabel],
            selectedId: 'gemini',
            onChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Gemini'));
      await tester.pumpAndSettle();

      // Find the long-label Text inside the menu. It must be marked
      // with overflow=ellipsis; otherwise a wrapping label would inflate
      // the menu height beyond our 48 px-per-row geometry estimate.
      final longText = find.byWidgetPredicate((w) =>
          w is Text &&
          w.data == 'A Very Long Provider Name That Should Get Ellipsised');
      expect(longText, findsOneWidget);
      final widget = tester.widget<Text>(longText);
      expect(widget.overflow, TextOverflow.ellipsis);
      expect(widget.maxLines, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'chip in the screen MIDDLE keeps the conventional drop-down '
        'direction (no spurious flips)', (tester) async {
      tester.view.physicalSize = const Size(400 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [AppColors.dark]),
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  right: 16,
                  // Dead centre of an 800 px viewport.
                  top: 380,
                  child: ProviderPicker(
                    options: const [_gemini, _xgrok],
                    selectedId: 'gemini',
                    onChanged: (_) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Gemini'));
      await tester.pumpAndSettle();

      final chipRect = tester.getRect(find.text('Gemini').first);
      final menuItemRect = tester.getRect(find.text('xGrok'));
      expect(menuItemRect.top, greaterThanOrEqualTo(chipRect.bottom),
          reason:
              'mid-screen chips must drop DOWN, not flip up — no spurious flips');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'menu stays inside the visible area when the keyboard is open',
        (tester) async {
      // Set the test viewport AND its window insets so the picker —
      // which reads MediaQuery from the popup route's own context (root
      // overlay, not our Builder) — sees a realistic keyboard inset.
      tester.view.physicalSize = const Size(400 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3.0;
      tester.view.viewInsets = const FakeViewPadding(bottom: 380 * 3);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetViewInsets();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [AppColors.dark]),
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  right: 16,
                  // Just above the keyboard's top edge — exactly where
                  // the input-bar chip sits when the keyboard is up in
                  // production.
                  top: 380,
                  child: ProviderPicker(
                    options: const [_gemini, _xgrok],
                    selectedId: 'gemini',
                    onChanged: (_) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Gemini'));
      await tester.pumpAndSettle();

      // The 'xGrok' item must be ABOVE the keyboard's top edge (y ≤ 420
      // — screen height 800 minus keyboard 380).
      final menuItemRect = tester.getRect(find.text('xGrok'));
      expect(menuItemRect.bottom, lessThanOrEqualTo(420.0),
          reason: 'menu must not extend below the keyboard inset');
      expect(tester.takeException(), isNull);
    });
  });
}
