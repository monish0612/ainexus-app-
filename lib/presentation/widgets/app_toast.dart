import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/services/telegram_logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  AppToast — Overlay-based toast with HARD-TIMER auto-dismiss
// ─────────────────────────────────────────────────────────────────────────────
//
// Why this exists (and why we don't use SnackBar for save/remove popovers):
//
//   ScaffoldMessenger's SnackBar has well-known fragility when shown from
//   inside a [showModalBottomSheet]:
//     • The snackbar renders in the underlying Scaffold's body — i.e. behind
//       the modal route in z-order. Visually it can be invisible until the
//       sheet closes.
//     • Some Flutter versions pause SnackBar's auto-dismiss timer when a new
//       opaque route covers the underlying messenger. Result: the user
//       perceives the toast as "stuck".
//     • Floating snackbars with a margin from the bottom can appear pinned
//       above bottom-sheet input bars instead of dismissing cleanly.
//
//   The fix is the same one every production app eventually lands on:
//   render the toast directly on the *root navigator's overlay* with a
//   hard [Timer] that calls dismiss after the configured duration —
//   independent of any Scaffold, route stack, or animation pipeline.
//
// Guarantees:
//   • The toast WILL dismiss after [duration] regardless of route state,
//     widget tree changes, or whether the user interacts with the screen.
//   • Showing a new toast immediately replaces any toast currently on
//     screen — no stacking, no orphans.
//   • The overlay is mounted on the [rootOverlay], so the toast renders
//     ABOVE all bottom sheets, dialogs, and pushed routes.
//   • Tap on the toast's body dismisses it instantly.
//   • If the user taps the optional action button (e.g. "Undo"), the
//     callback fires and the toast dismisses immediately.
//
// Telegram observability:
//   Every show/dismiss path emits a debug-level [TLog] entry tagged
//   "AppToast" so the toast lifecycle is visible in production logs.

class AppToast {
  AppToast._();

  static OverlayEntry? _activeEntry;
  static Timer? _activeTimer;
  static _AppToastEntryState? _activeState;

  /// Default visible duration for a toast. Long enough for the user to
  /// read + reach the action button; short enough that it never feels
  /// like the app is "stuck".
  static const Duration _kDefaultDuration = Duration(seconds: 3);

  /// Hard upper-bound timer leeway — we add 200 ms over the configured
  /// duration so the slide-out animation can complete before the entry
  /// is removed from the overlay tree.
  static const Duration _kAnimationOut = Duration(milliseconds: 220);

  /// Show a toast attached to the nearest [Overlay] of [context].
  ///
  /// Pass [action] to render an inline button (e.g. "Undo"). Tapping it
  /// fires [onAction] and immediately dismisses the toast.
  ///
  /// [duration] is the visible time before auto-dismiss kicks in. Pass
  /// [Duration.zero] for an indefinite toast (will only dismiss on tap or
  /// when [hide] is called explicitly).
  static void show(
    BuildContext context, {
    required String message,
    Duration duration = _kDefaultDuration,
    String? action,
    VoidCallback? onAction,
    AppToastVariant variant = AppToastVariant.info,
  }) {
    // Resolve a root overlay so the toast sits above modal sheets and
    // dialogs that the user opened from inside the same task.
    final overlay =
        Overlay.maybeOf(context, rootOverlay: true) ?? Overlay.maybeOf(context);
    if (overlay == null) {
      // No overlay yet (extremely unusual — only happens when a toast is
      // requested before the first frame). Defer one frame and retry.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        show(context,
            message: message,
            duration: duration,
            action: action,
            onAction: onAction,
            variant: variant);
      });
      return;
    }

    // Replace any existing toast — no stacking. We slide-out the prior
    // entry first so the transition reads naturally.
    _hideInternal(animate: false);

    final entry = OverlayEntry(
      builder: (_) => _AppToastEntry(
        key: UniqueKey(),
        message: message,
        action: action,
        onAction: onAction,
        variant: variant,
        onDismiss: () => hide(),
        onMounted: (state) => _activeState = state,
      ),
    );
    _activeEntry = entry;
    overlay.insert(entry);

    TLog.d('AppToast', 'show "$message" '
        '(${duration.inMilliseconds}ms${action != null ? ', action=$action' : ''})');

    if (duration > Duration.zero) {
      _activeTimer = Timer(duration, () {
        TLog.d('AppToast', 'auto-dismiss after ${duration.inMilliseconds}ms');
        hide();
      });
    }
  }

  /// Dismiss the active toast immediately. No-op if nothing is showing.
  /// The slide-out animation runs first so the dismiss is visually smooth.
  static void hide() {
    _hideInternal(animate: true);
  }

  static void _hideInternal({required bool animate}) {
    _activeTimer?.cancel();
    _activeTimer = null;
    final entry = _activeEntry;
    final state = _activeState;
    _activeEntry = null;
    _activeState = null;
    if (entry == null) return;

    if (animate && state != null && state.mounted) {
      // Trigger the slide-out, then remove the entry once it's offscreen.
      state.startDismissAnimation();
      Future<void>.delayed(_kAnimationOut, () {
        try {
          entry.remove();
        } catch (_) {/* already removed */}
      });
    } else {
      try {
        entry.remove();
      } catch (_) {/* already removed */}
    }
  }

  /// Test-only synchronous reset — wipes the active overlay/timer without
  /// touching the widget tree. Production code never calls this.
  @visibleForTesting
  static void debugResetForTests() {
    _activeTimer?.cancel();
    _activeTimer = null;
    final entry = _activeEntry;
    _activeEntry = null;
    _activeState = null;
    if (entry != null) {
      try {
        entry.remove();
      } catch (_) {/* already removed */}
    }
  }

  /// Test-only inspector — true if a toast is currently on the overlay.
  @visibleForTesting
  static bool debugIsShowing() => _activeEntry != null;
}

enum AppToastVariant {
  info,
  success,
  error,
}

/// Single-toast widget rendered inside the overlay. Owns its own slide
/// + fade animation so the parent only worries about lifecycle.
class _AppToastEntry extends StatefulWidget {
  const _AppToastEntry({
    super.key,
    required this.message,
    required this.action,
    required this.onAction,
    required this.variant,
    required this.onDismiss,
    required this.onMounted,
  });

  final String message;
  final String? action;
  final VoidCallback? onAction;
  final AppToastVariant variant;
  final VoidCallback onDismiss;
  final ValueChanged<_AppToastEntryState> onMounted;

  @override
  State<_AppToastEntry> createState() => _AppToastEntryState();
}

class _AppToastEntryState extends State<_AppToastEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _slide; // 0 → offscreen, 1 → on
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _slide = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
    // Hand the parent a reference so it can trigger the slide-out
    // animation deterministically when AppToast.hide() is called.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onMounted(this);
    });
  }

  void startDismissAnimation() {
    if (!mounted) return;
    _ctrl.reverse();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final colors = _variantColors(widget.variant);

    return Positioned(
      left: 0,
      right: 0,
      // Anchored to the bottom edge with a comfortable inset above the
      // gesture-nav area. The 16-pt extra clearance keeps the toast
      // visually distinct from any bottom-sheet input bars.
      bottom: media.padding.bottom + 16,
      child: SafeArea(
        top: false,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) {
            // Slide up from below by 32 px and fade in.
            final dy = (1 - _slide.value) * 32;
            return Opacity(
              opacity: _fade.value,
              child: Transform.translate(offset: Offset(0, dy), child: child),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Material(
              color: Colors.transparent,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      TLog.d('AppToast', 'tap-to-dismiss');
                      widget.onDismiss();
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: colors.bg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: colors.border, width: 0.6),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 18,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                      child: Row(
                        children: [
                          if (colors.icon != null) ...[
                            Icon(colors.icon, size: 18, color: colors.iconColor),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: Text(
                              widget.message,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                height: 1.3,
                              ),
                            ),
                          ),
                          if (widget.action != null) ...[
                            const SizedBox(width: 10),
                            // Dedicated action chip — separate hit-target so
                            // the body's tap-to-dismiss doesn't swallow it.
                            Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () {
                                  TLog.d('AppToast',
                                      'action="${widget.action}" pressed');
                                  // Fire callback first so any state mutation
                                  // happens BEFORE the overlay tears down.
                                  // Wrap in try/finally so a throwing action
                                  // never leaks the toast on-screen forever
                                  // (production safety: a buggy Undo handler
                                  // shouldn't permanently freeze the toast).
                                  Object? caught;
                                  StackTrace? caughtStack;
                                  try {
                                    widget.onAction?.call();
                                  } catch (e, st) {
                                    caught = e;
                                    caughtStack = st;
                                    TLog.e('AppToast',
                                        'action="${widget.action}" threw',
                                        error: e);
                                  } finally {
                                    widget.onDismiss();
                                  }
                                  // Re-raise after dismiss so the framework /
                                  // test harness still observes the error
                                  // through normal channels.
                                  if (caught != null) {
                                    Error.throwWithStackTrace(
                                        caught, caughtStack ?? StackTrace.current);
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  child: Text(
                                    widget.action!,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFFC084FC),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  _ToastColors _variantColors(AppToastVariant v) {
    switch (v) {
      case AppToastVariant.success:
        return const _ToastColors(
          bg: Color(0xE61F2937),
          border: Color(0xFF22C55E),
          icon: Icons.check_circle_outline,
          iconColor: Color(0xFF22C55E),
        );
      case AppToastVariant.error:
        return const _ToastColors(
          bg: Color(0xE6991B1B),
          border: Color(0xFFFCA5A5),
          icon: Icons.error_outline,
          iconColor: Color(0xFFFCA5A5),
        );
      case AppToastVariant.info:
        return const _ToastColors(
          bg: Color(0xE61F2937),
          border: Color(0x331F2937),
          icon: null,
          iconColor: Colors.white,
        );
    }
  }
}

class _ToastColors {
  const _ToastColors({
    required this.bg,
    required this.border,
    required this.icon,
    required this.iconColor,
  });

  final Color bg;
  final Color border;
  final IconData? icon;
  final Color iconColor;
}
