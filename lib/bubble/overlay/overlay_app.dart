import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/auth/app_token_store.dart';
import '../../core/auth/auth_service.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/services/telegram_logger.dart';
import '../rephrase/bubble_rephrase_client.dart';
import '../rephrase/resilience.dart';
import 'bubble.dart';
import 'overlay_bridge.dart';
import 'panel.dart';
import 'tokens.dart';

/// Entry point for the second Flutter engine that renders the floating bubble.
///
/// Called from the `overlayMain` entry point in main.dart. This isolate has its
/// own singletons, so it re-does the slice of app bootstrap the rephrase call
/// needs: the Telegram logger and the JWT (plus its refresher, for a 401).
Future<void> runBubbleOverlay() async {
  WidgetsFlutterBinding.ensureInitialized();
  TLog.init();
  try {
    await AuthService.instance.init();
    await AppTokenStore.instance.load();
    AppTokenStore.instance.refresher = AuthService.instance.refreshAppToken;
  } catch (e, st) {
    // The overlay still renders; the first rephrase will surface an auth error.
    TLog.w('Bubble', 'Overlay auth bootstrap failed', error: e, st: st);
  }
  unawaited(_warmApiTls());
  runApp(const BubbleOverlayApp());
}

/// Fire-and-forget TLS + connection warmup so the first chip tap doesn't
/// pay a cold handshake to the VPS.
Future<void> _warmApiTls() async {
  try {
    await ApiClient()
        .get(ApiEndpoints.health)
        .timeout(const Duration(seconds: 4));
  } catch (_) {
    // Warmup must never surface. A dead gateway still fails the real call.
  }
}

class BubbleOverlayApp extends StatefulWidget {
  const BubbleOverlayApp({super.key});

  @override
  State<BubbleOverlayApp> createState() => _BubbleOverlayAppState();
}

class _BubbleOverlayAppState extends State<BubbleOverlayApp> {
  final _bridge = OverlayBridge();
  final _client = BubbleRephraseClient();

  BubbleTarget _target = const BubbleTarget.empty();
  bool _expanded = false;

  /// True while the collapsed bubble is on screen. Used so a typing pause does
  /// not remount it and replay the liquid entrance over a parked bubble.
  bool _collapsedOnScreen = false;

  /// Bumped only when the bubble first appears, so the entrance plays once.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    // A fresh field means a fresh panel.
    _bridge.onTarget = (target) {
      if (!mounted) return;
      setState(() {
        _target = target;
        _expanded = false;
        if (!_collapsedOnScreen) {
          _generation++;
          _collapsedOnScreen = true;
        }
      });
    };
    _bridge.onCollapse = () {
      if (!mounted) return;
      setState(() {
        _expanded = false;
        _collapsedOnScreen = false;
      });
    };
    // Bubble gestures are native; a tap arrives here as a notification.
    _bridge.onTap = () {
      if (!mounted || _expanded) return;
      _expand();
    };
  }

  Future<void> _expand() async {
    // Native re-reads the field before growing the window, so this is the
    // authoritative text for the whole interaction.
    final target = await _bridge.expand();
    if (!mounted) return;
    setState(() {
      if (target.text.isNotEmpty) _target = target;
      _expanded = true;
    });
  }

  Future<void> _collapse() async {
    await _bridge.collapse();
    if (!mounted) return;
    setState(() => _expanded = false);
  }

  /// Fetch the rephrase for review. Nothing is written to the field until the
  /// user accepts it; [fresh] bypasses the cache for a different version.
  Future<PanelResult> _run(
    String platform,
    String? intent, {
    required bool fresh,
  }) async {
    try {
      final rephrased = await _client.rephrase(
        text: _target.text,
        platform: platform,
        intent: intent,
        fresh: fresh,
      );
      return PanelResult.success(rephrased);
    } on BubbleError catch (e) {
      return PanelResult.failure(e.display);
    } catch (e, st) {
      TLog.e('Bubble', 'Unexpected rephrase failure', error: e, st: st);
      return const PanelResult.failure('Rephrase failed — tap to retry');
    }
  }

  /// The user accepted the reviewed text: write it into the field.
  Future<ReplaceOutcome> _accept(String text) async {
    final outcome = await _bridge.replace(text);
    if (!outcome.replaced) {
      // Field is off limits (secure or unsupported editor) — the panel says so
      // and the text is already on the clipboard, courtesy of native.
      TLog.w('Bubble', 'Write-back blocked in ${_target.package}');
    }
    return outcome;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      color: const Color(0x00000000),
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0x00000000),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: kAccent,
          selectionColor: Color(0x556EA8FF),
          selectionHandleColor: kAccent,
        ),
      ),
      // A floating overlay has a hard size budget, so system font scaling is
      // capped here instead of being allowed to overflow the window.
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: 1,
        maxScaleFactor: kMaxTextScale,
        child: child ?? const SizedBox.shrink(),
      ),
      home: Material(
        type: MaterialType.transparency,
        child: _Morph(
          child: _expanded
              ? _ExpandedScrim(
                  onOutsideTap: _collapse,
                  child: RephrasePanel(
                    key: const ValueKey('panel'),
                    target: _target,
                    onRun: _run,
                    onAccept: _accept,
                    onCopy: _bridge.copy,
                    onClose: _collapse,
                    onFocusRequest: _bridge.setFocusable,
                    onMeasured: _bridge.resize,
                    lastPlatformId: _target.lastPlatformId,
                    onPlatformUsed: _bridge.saveLastPlatform,
                  ),
                )
              : RephraseBubble(key: ValueKey('bubble$_generation')),
        ),
      ),
    );
  }
}

/// Full-window transparent hit target. Native grows the overlay to the screen
/// while expanded; a tap anywhere outside the panel collapses it.
class _ExpandedScrim extends StatelessWidget {
  const _ExpandedScrim({required this.onOutsideTap, required this.child});

  final VoidCallback onOutsideTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onOutsideTap,
            child: const ColoredBox(color: Color(0x00000000)),
          ),
        ),
        // Panel absorbs its own taps so they never reach the scrim.
        child,
      ],
    );
  }
}

/// Scale-and-fade between the bubble and the panel. Frozen under reduced motion.
class _Morph extends StatelessWidget {
  const _Morph({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (reducedMotion(context)) return child;
    return AnimatedSwitcher(
      duration: kMorphIn,
      reverseDuration: kMorphOut,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (widget, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(animation),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.015),
              end: Offset.zero,
            ).animate(animation),
            child: widget,
          ),
        ),
      ),
      child: child,
    );
  }
}
