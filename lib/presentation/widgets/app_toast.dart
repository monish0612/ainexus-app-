import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/services/telegram_logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  AppToast — Overlay-based toast with TWO independent dismiss timers
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
//     • In dark-mode, the default SnackBar inverts to a LIGHT background
//       with dark text — clashes hard with our app's dark theme.
//
// Belt-and-braces dismissal contract:
//   1. **Primary timer** schedules the normal dismiss after [duration].
//   2. **Watchdog timer** fires at [duration] + [_kWatchdogGrace] and force-
//      tears down the overlay entry no matter what — even if the primary
//      animation was somehow paused, even if the parent route is gone, even
//      if the widget tree was rebuilt mid-animation.
//   This is the production answer to "the toast didn't disappear" — the
//   watchdog is independent of any animation pipeline, route stack, or
//   widget lifecycle. Worst case it removes a torn-down entry which is a
//   no-op.
//
// Implementation notes:
//   • Uses the *root navigator's overlay* so the toast renders ABOVE every
//     bottom sheet, dialog, and pushed route.
//   • NO BackdropFilter — that's a hardware-accelerated path that has
//     occasional rendering issues on certain Android device/OS combos and
//     is not necessary for a solid, opaque toast.
//   • Fully opaque background — no alpha mixing means the toast renders
//     identically on every theme + device.
//   • Throwing onAction is wrapped in try/finally so a buggy caller can't
//     leave the toast stranded on screen.

class AppToast {
  AppToast._();

  static OverlayEntry? _activeEntry;
  static Timer? _activeTimer;
  static Timer? _watchdogTimer;
  static _AppToastEntryState? _activeState;

  /// Default visible duration for a toast.
  static const Duration _kDefaultDuration = Duration(seconds: 3);

  /// Slide-out animation length — kept in sync with [_AppToastEntryState].
  static const Duration _kAnimationOut = Duration(milliseconds: 220);

  /// How long after the configured [duration] the watchdog timer fires
  /// to force-remove a still-mounted entry. Generous enough that the
  /// normal animation path always completes first under healthy conditions
  /// but short enough that the user never sees a stuck toast for >1 s
  /// past its expected lifetime.
  static const Duration _kWatchdogGrace = Duration(milliseconds: 800);

  /// Show a toast attached to the root [Overlay] of [context].
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

    // Replace any existing toast — no stacking. We tear down hard (no
    // animation) so the next show() reads as a clean swap.
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
      // Primary dismiss path — schedules the smooth slide-out.
      _activeTimer = Timer(duration, () {
        TLog.d('AppToast', 'auto-dismiss after ${duration.inMilliseconds}ms');
        hide();
      });
      // Watchdog dismiss path — independent timer that force-removes the
      // overlay entry no matter what. This is the safety net for the
      // "toast stuck on screen" production bug. Fires at:
      //   duration + _kAnimationOut + _kWatchdogGrace
      // so under healthy conditions the primary path completes first and
      // this becomes a no-op (entry is already null).
      final hardLimit = duration + _kAnimationOut + _kWatchdogGrace;
      _watchdogTimer = Timer(hardLimit, () {
        if (_activeEntry == entry) {
          TLog.w('AppToast',
              'watchdog fired after ${hardLimit.inMilliseconds}ms — '
              'forcing entry removal (primary dismiss path stalled)');
          _hideInternal(animate: false);
        }
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
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
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
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
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
              // Fully opaque so the toast renders the same way on every
              // device + theme. No BackdropFilter (that's a GPU path with
              // occasional rendering glitches on certain Android combos).
              color: colors.bg,
              elevation: 8,
              shadowColor: const Color(0x55000000),
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  TLog.d('AppToast', 'tap-to-dismiss');
                  widget.onDismiss();
                },
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: colors.border, width: 0.6),
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
                              if (caught != null) {
                                Error.throwWithStackTrace(caught,
                                    caughtStack ?? StackTrace.current);
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
    );
  }

  _ToastColors _variantColors(AppToastVariant v) {
    switch (v) {
      case AppToastVariant.success:
        return const _ToastColors(
          // Fully opaque dark gray-green. Sits great on dark backgrounds
          // and is clearly distinct from "info".
          bg: Color(0xFF14532D),
          border: Color(0xFF22C55E),
          icon: Icons.check_circle_outline,
          iconColor: Color(0xFF22C55E),
        );
      case AppToastVariant.error:
        return const _ToastColors(
          bg: Color(0xFF7F1D1D),
          border: Color(0xFFFCA5A5),
          icon: Icons.error_outline,
          iconColor: Color(0xFFFCA5A5),
        );
      case AppToastVariant.info:
        return const _ToastColors(
          // Fully opaque dark slate — matches our dark theme exactly so
          // it's never mistaken for a Material SnackBar in dark mode.
          bg: Color(0xFF111827),
          border: Color(0xFF374151),
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
