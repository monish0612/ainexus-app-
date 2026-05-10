import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_colors.dart';

/// One entry in a [ProviderPicker]. Designed to be const-constructible so
/// the picker can be passed a `const` list with zero per-build allocation.
@immutable
class ProviderOption {
  const ProviderOption({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    this.shortLabel,
  });

  /// Stable wire id (e.g. `'gemini'`, `'xgrok'`). This is what the picker
  /// hands back through [ProviderPicker.onChanged] and what the caller
  /// should persist.
  final String id;

  /// Pretty label used in the dropdown menu (e.g. `"Gemini"`).
  final String label;

  /// Optional shorter label used in the compact chip when label is too long
  /// for the available space. Defaults to [label].
  final String? shortLabel;

  /// Icon shown next to the label in both the chip and the menu.
  final IconData icon;

  /// Brand colour used for the chip background, border and text.
  final Color color;

  String get chipLabel => shortLabel ?? label;
}

/// A compact, modern, theme-aware provider picker.
///
/// Two render modes, decided automatically from [options.length]:
///
///   • **Single option** → renders as a static read-only chip. Used when
///     the parent has decided the user has no real choice (e.g. xGrok is
///     disabled in settings) but we still want to surface which provider
///     is in play. Pixel-equivalent to the legacy static chip so this is
///     a safe drop-in replacement.
///
///   • **Two or more options** → renders as a tappable chip with a rotating
///     chevron. Tapping opens a custom-routed popover anchored to the chip,
///     showing every option with the active one highlighted. Selection
///     emits a haptic tick and calls [onChanged] with the option's id.
///
/// State ownership is intentionally external — the picker holds nothing
/// across rebuilds except the chevron rotation. Persistence and the
/// "currently active provider" both live in the caller (typically a
/// Riverpod settings notifier), so this widget composes cleanly into any
/// state model.
class ProviderPicker extends StatefulWidget {
  const ProviderPicker({
    super.key,
    required this.options,
    required this.selectedId,
    required this.onChanged,
    this.colors,
    this.heroTag,
  }) : assert(options.length > 0, 'ProviderPicker needs at least one option');

  final List<ProviderOption> options;

  /// The id of the currently active option. If [options] does not contain
  /// this id (e.g. a stale persisted value), the first option is shown
  /// instead — the picker never crashes on stale state.
  final String selectedId;

  /// Fired with the chosen option's [ProviderOption.id] when the user picks
  /// a different one. Identical-selection taps are coalesced (no fire).
  final ValueChanged<String> onChanged;

  /// Optional explicit colour palette. When omitted, the picker reads from
  /// the ambient `Theme.of(context).extension<AppColors>()`.
  final AppColors? colors;

  /// Used as the AnimatedSwitcher key so callers that mount the picker in
  /// multiple places at once (e.g. several search screens) animate
  /// independently. Optional.
  final String? heroTag;

  @override
  State<ProviderPicker> createState() => _ProviderPickerState();
}

class _ProviderPickerState extends State<ProviderPicker> {
  bool _open = false;

  // Captured at open-time so we can dismiss the popover on dispose. Without
  // this, navigating away from the host tab while the popover is open would
  // orphan the route in the root navigator — the user would see a stale
  // popover floating over the next screen.
  NavigatorState? _navigator;
  _ProviderMenuRoute? _activeRoute;

  ProviderOption get _active {
    return widget.options.firstWhere(
      (o) => o.id == widget.selectedId,
      orElse: () => widget.options.first,
    );
  }

  bool get _interactive => widget.options.length > 1;

  @override
  void didUpdateWidget(covariant ProviderPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If interactivity is taken away while the popover is open (e.g. settings
    // toggle reduces options to one), dismiss the popover so the chip and
    // its overlay stay in sync. Use a microtask so we don't pop during build.
    if (_open && !_interactive) {
      _dismissActiveRoute();
    }
  }

  void _dismissActiveRoute() {
    final nav = _navigator;
    final route = _activeRoute;
    if (nav != null && route != null && route.isActive) {
      // removeRoute is preferred over pop() because it works even if the
      // route is no longer on top of the stack (e.g. user opened a dialog
      // over our popover before we cleaned up).
      nav.removeRoute(route);
    }
    _activeRoute = null;
    _navigator = null;
  }

  @override
  void dispose() {
    _dismissActiveRoute();
    super.dispose();
  }

  Future<void> _openMenu() async {
    if (!_interactive || _open) return;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final overlay = Overlay.of(context, rootOverlay: true);
    final overlayBox = overlay.context.findRenderObject() as RenderBox;

    final anchor = renderBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final size = renderBox.size;
    final overlaySize = overlayBox.size;

    final navigator = Navigator.of(context, rootNavigator: true);
    final route = _ProviderMenuRoute(
      anchor: anchor,
      anchorSize: size,
      overlaySize: overlaySize,
      options: widget.options,
      selectedId: _active.id,
      colors: widget.colors ?? Theme.of(context).extension<AppColors>()!,
    );
    _navigator = navigator;
    _activeRoute = route;

    setState(() => _open = true);
    HapticFeedback.selectionClick();

    final picked = await navigator.push(route);

    _activeRoute = null;
    _navigator = null;

    if (!mounted) return;
    setState(() => _open = false);

    if (picked != null && picked != widget.selectedId) {
      HapticFeedback.lightImpact();
      // The callback is caller-owned (typically writes to SharedPreferences
      // or fires a network sync). It MUST NOT be allowed to corrupt the
      // picker's open/close state machine — we've already popped the route
      // and reset _open above, so a throw here can only damage the caller's
      // own state. We swallow + report so the picker stays usable. If the
      // caller cares about errors they can wrap their own logic.
      try {
        widget.onChanged(picked);
      } catch (e, st) {
        FlutterError.reportError(FlutterErrorDetails(
          exception: e,
          stack: st,
          library: 'provider_picker',
          context: ErrorDescription('while invoking onChanged($picked)'),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _active;

    final chip = AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.fromLTRB(7, 3, _interactive ? 5 : 7, 3),
      decoration: BoxDecoration(
        color: active.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: active.color.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(active.icon, size: 9, color: active.color),
          const SizedBox(width: 4),
          Text(
            active.chipLabel,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: active.color,
              letterSpacing: 0.3,
            ),
          ),
          if (_interactive) ...[
            const SizedBox(width: 3),
            AnimatedRotation(
              turns: _open ? 0.5 : 0.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: Icon(
                LucideIcons.chevronDown,
                size: 10,
                color: active.color,
              ),
            ),
          ],
        ],
      ),
    );

    final switcher = AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: anim, child: child),
      ),
      child: Container(
        // The key forces a smooth crossfade when the user switches providers
        // (e.g. Gemini ↔ xGrok), without triggering a rebuild storm.
        key: ValueKey(
            '${widget.heroTag ?? 'provider'}-${active.id}-$_interactive'),
        child: chip,
      ),
    );

    if (!_interactive) return switcher;

    return Semantics(
      button: true,
      label: 'Search provider: ${active.label}. Tap to change.',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openMenu,
        child: switcher,
      ),
    );
  }
}

// ── Custom dropdown route ───────────────────────────────────────────────────
//
// We deliberately do NOT use `showMenu` because Material's PopupMenuButton
// lays out its overlay with an opinionated padding/elevation that fights
// our compact dark-theme chip. Rolling our own [PopupRoute] gives us:
//
//   • Pixel-precise anchor positioning (right-aligned to the chip)
//   • Scale + fade entrance from the chip's anchor point
//   • Custom barrier (no scrim, just a tap-outside-to-dismiss layer)
//   • Constant-time route swap — no Navigator-tree pollution
//
// The route is internal to this file because it's tightly coupled to
// [ProviderPicker]'s visual language. Nothing else should instantiate it.

class _ProviderMenuRoute extends PopupRoute<String> {
  _ProviderMenuRoute({
    required this.anchor,
    required this.anchorSize,
    required this.overlaySize,
    required this.options,
    required this.selectedId,
    required this.colors,
  });

  final Offset anchor;
  final Size anchorSize;
  final Size overlaySize;
  final List<ProviderOption> options;
  final String selectedId;
  final AppColors colors;

  /// True when the menu was placed ABOVE the chip because there wasn't
  /// enough room below (e.g. the chip lives in a bottom-sheet input
  /// bar). Drives the scale-in transition origin so the menu always
  /// appears to grow OUT of the chip, never from the screen centre.
  bool _openedUpward = false;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss provider picker';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 180);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 120);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return Stack(children: [_positioned(context)]);
  }

  Widget _positioned(BuildContext context) {
    // ── Geometry ──────────────────────────────────────────────────────
    // Match the chip's right edge horizontally so the menu reads as a
    // direct continuation of the chip. Vertically, prefer to drop DOWN
    // (the conventional direction users expect), but flip UP whenever
    // the chip is sitting in the bottom of the visible area — exactly
    // the situation in our two bottom-sheet input bars (saved-search
    // detail + FAB chat) and in the Tutor screen's main result page
    // when the keyboard is up.
    const baseMenuWidth = 172.0;
    const gap = 6.0;
    const sideInset = 8.0;

    // Adapt menu width to extreme viewports so we never try to pin a
    // 172 px panel on a 160 px window. Real phones never hit this; it's
    // a defensive guard for split-screen / foldable / tiny-tablet edge
    // cases so the geometry math below stays valid.
    final menuWidth = baseMenuWidth.clamp(
      120.0,
      (overlaySize.width - sideInset * 2).clamp(120.0, double.infinity),
    );

    // Per-option visual height: 22 line + 18 vertical padding. With the
    // outer card's 4 px padding-top + 4 px padding-bottom that's exactly
    // 48 px per row. We bias slightly above the visual minimum so a
    // line-wrap (extra-long label) still fits inside our flip threshold.
    final estimatedHeight = options.length * 48.0 + 16.0;

    final mq = MediaQuery.of(context);
    final visibleBottom = overlaySize.height - mq.viewInsets.bottom;
    final visibleTop = mq.padding.top;

    // Space measured from the chip edge in each direction, ignoring the
    // keyboard / system insets so the menu always lands inside the
    // user-visible window.
    final chipBottomOnScreen = anchor.dy + anchorSize.height;
    final spaceBelow = (visibleBottom - chipBottomOnScreen - gap)
        .clamp(0.0, double.infinity);
    final spaceAbove = (anchor.dy - visibleTop - gap)
        .clamp(0.0, double.infinity);

    // Flip up when below is too cramped for the menu AND above has more
    // room. The strict `>` against `spaceBelow` prevents flicker when
    // both spaces are close (we keep the conventional drop-down).
    _openedUpward = spaceBelow < estimatedHeight && spaceAbove > spaceBelow;

    // Right-edge alignment, defended against degenerate widths.
    final desiredRight =
        overlaySize.width - (anchor.dx + anchorSize.width);
    final maxRight = overlaySize.width - menuWidth - sideInset;
    final right = _safeClamp(desiredRight, sideInset, maxRight);

    // Bound the menu to the larger visible half so a 5-option list
    // scrolls inside the card instead of overflowing the screen.
    final maxHeight = _safeClamp(
      _openedUpward ? spaceAbove : spaceBelow,
      80.0,
      overlaySize.height,
    );

    if (_openedUpward) {
      // Position by `bottom` so the menu's bottom edge sits gap-px
      // above the chip's top edge — this is what makes it visually
      // "grow out of" the chip even when the keyboard is up.
      final bottomFromOverlay =
          (overlaySize.height - anchor.dy + gap).clamp(0.0, double.infinity);
      return Positioned(
        right: right,
        bottom: bottomFromOverlay,
        width: menuWidth,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: _MenuCard(
            options: options,
            selectedId: selectedId,
            colors: colors,
          ),
        ),
      );
    }

    // Drop-down. Cap the top position so the menu's bottom edge always
    // lands inside the visible area; if the menu is taller than the
    // viewport we simply start it at the chip and let the inner
    // SingleChildScrollView handle the overflow.
    final maxTop = overlaySize.height - estimatedHeight - sideInset;
    final top = _safeClamp(chipBottomOnScreen + gap, 0.0, maxTop);
    return Positioned(
      right: right,
      top: top,
      width: menuWidth,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: _MenuCard(
          options: options,
          selectedId: selectedId,
          colors: colors,
        ),
      ),
    );
  }

  /// Saturating clamp — when [lower] exceeds [upper] (degenerate viewport
  /// where the screen is too small to fit the menu and the safe inset),
  /// pin to [lower] instead of throwing. Real production devices never
  /// trigger this branch; it's a defensive guard for split-screen /
  /// foldable / unit-test edge cases.
  static double _safeClamp(double value, double lower, double upper) {
    if (lower > upper) return lower;
    return value.clamp(lower, upper);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        // Origin flips with the open direction: drop-down scales from
        // top-right (under the chip), drop-up scales from bottom-right
        // (above the chip). Either way it grows out of the chip itself.
        alignment:
            _openedUpward ? Alignment.bottomRight : Alignment.topRight,
        scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
        child: child,
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.options,
    required this.selectedId,
    required this.colors,
  });

  final List<ProviderOption> options;
  final String selectedId;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: colors.bg1,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        padding: const EdgeInsets.all(4),
        // SingleChildScrollView with shrinkWrap'd Column lets the card
        // gracefully scroll when the parent ConstrainedBox limits its
        // max-height below the natural content height (rare, only with
        // 4+ providers + keyboard up). For the common 1-2 option case
        // it's a free no-op.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in options)
                _MenuItem(
                  option: option,
                  selected: option.id == selectedId,
                  colors: colors,
                  onTap: () => Navigator.of(context).pop(option.id),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuItem extends StatefulWidget {
  const _MenuItem({
    required this.option,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  final ProviderOption option;
  final bool selected;
  final AppColors colors;
  final VoidCallback onTap;

  @override
  State<_MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<_MenuItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final option = widget.option;
    final colors = widget.colors;
    final highlighted = widget.selected || _hover;

    return Semantics(
      button: true,
      selected: widget.selected,
      label:
          '${option.label}${widget.selected ? ', currently selected' : ''}',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: highlighted
                  ? option.color.withValues(alpha: 0.10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: option.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(option.icon, size: 12, color: option.color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5,
                      fontWeight:
                          widget.selected ? FontWeight.w800 : FontWeight.w600,
                      color: widget.selected ? option.color : colors.text,
                    ),
                  ),
                ),
                if (widget.selected)
                  Icon(LucideIcons.check, size: 14, color: option.color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
