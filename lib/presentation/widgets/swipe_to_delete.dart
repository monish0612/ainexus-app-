import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_colors.dart';

/// Generic swipe-to-delete wrapper around an arbitrary card widget.
///
/// Currently consumed by every News > For You chip (All, AI News,
/// Finance, Movies, General) on both the featured card and list rows,
/// and by Watch list rows.
///
/// Behavior contract:
///   • Accepts a swipe in EITHER horizontal direction (start↔end). The
///     same red trash background is rendered on both sides for visual
///     symmetry — "swipe left" and "swipe right" both unambiguously
///     mean DELETE.
///   • A committed swipe opens [showSwipeDeleteConfirm] before
///     [onDelete] (unless [confirm] is false). Keep, barrier tap,
///     system/predictive back, swipe-back on the overlay, and a
///     keep-swipe on the popup itself snap the card back with no
///     side effects.
///   • `confirmDismiss` always returns `false` so the Dismissible NEVER
///     actually animates the child away — instead it fires [onDelete]
///     only after an explicit confirm and trusts the host's data layer
///     (Drift stream / state notifier) to drop the row on the next
///     rebuild. This eliminates the "ghost row" race where Dismissible
///     removes a widget while the underlying stream re-emits the same
///     item one tick later.
///   • Fires a selection haptic when the confirm sheet opens and a
///     medium impact when the user confirms, matching the haptic
///     pattern used elsewhere in the app.
///   • [borderRadius] keeps the red background's corners flush with the
///     child card's corners. Default `0` for flat cards; pass `24` for
///     the news featured card, `14` for a typical rounded list card.
///   • [contentHeight] forces the background to a fixed height so it
///     exactly matches a child that uses `Ink(height: X)` (otherwise
///     the Dismissible's `Stack`-style layout sizes the bg to the
///     child's intrinsic constraints — fine for flat list items but
///     visibly mismatched when the child sets an explicit height).
class SwipeToDelete extends StatelessWidget {
  const SwipeToDelete({
    super.key,
    required this.child,
    required this.onDelete,
    this.borderRadius = 0,
    this.contentHeight,
    this.dismissThreshold = 0.3,
    this.confirm = true,
    this.headline = 'Delete this?',
    this.title,
    this.message,
    this.confirmLabel = 'Delete',
    this.keepLabel = 'Keep',
  });

  final Widget child;
  final VoidCallback onDelete;
  final double borderRadius;
  final double? contentHeight;

  /// Fraction of the row width the user must drag past before the
  /// swipe commits. 0.3 (30 %) matches the platform default and is
  /// lenient enough that an accidental horizontal drag during a normal
  /// vertical scroll won't fire.
  final double dismissThreshold;

  /// When true (default), a committed swipe asks for confirmation
  /// before [onDelete]. Isolated pager tests set this to false.
  final bool confirm;

  /// Dialog heading, e.g. "Delete this article?".
  final String headline;

  /// Optional subject line shown under [headline] (article title,
  /// watch name). Truncated to two lines.
  final String? title;

  /// Optional supporting copy (category / undo warning).
  final String? message;

  final String confirmLabel;
  final String keepLabel;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      // Use the caller's `key` if provided (it should be, and the host
      // wires in an article-id-bearing ValueKey). Fall back to an
      // ObjectKey on the child so the widget tree is at least
      // well-formed in tests that forget the key.
      key: key ?? ObjectKey(child),
      dismissThresholds: {
        DismissDirection.startToEnd: dismissThreshold,
        DismissDirection.endToStart: dismissThreshold,
      },
      movementDuration: const Duration(milliseconds: 200),
      background: SwipeDeleteBackground(
        alignEnd: false,
        borderRadius: borderRadius,
        height: contentHeight,
      ),
      secondaryBackground: SwipeDeleteBackground(
        alignEnd: true,
        borderRadius: borderRadius,
        height: contentHeight,
      ),
      confirmDismiss: (direction) async {
        if (!confirm) {
          HapticFeedback.lightImpact();
          onDelete();
          return false;
        }
        HapticFeedback.selectionClick();
        final ok = await showSwipeDeleteConfirm(
          context: context,
          headline: headline,
          title: title,
          message: message,
          confirmLabel: confirmLabel,
          keepLabel: keepLabel,
        );
        if (!context.mounted || !ok) return false;
        HapticFeedback.mediumImpact();
        onDelete();
        return false;
      },
      child: child,
    );
  }
}

/// Centered, 160 ms scale+fade confirm.
///
/// Keep paths (never delete): Keep button, barrier tap, system/predictive
/// back, swipe-back on the dimmed overlay, or a keep-swipe on the card
/// itself (horizontal either way, or down). Returns `true` only when the
/// user taps Delete.
Future<bool> showSwipeDeleteConfirm({
  required BuildContext context,
  String headline = 'Delete this?',
  String? title,
  String? message,
  String confirmLabel = 'Delete',
  String keepLabel = 'Keep',
}) async {
  final colors = swipeDeleteColorsOf(context);
  final result = await showGeneralDialog<bool>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: 'Delete confirmation',
    barrierColor: Color.fromRGBO(0, 0, 0, colors.isDark ? 0.62 : 0.40),
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (ctx, _, __) {
      return SizedBox.expand(
        child: _SwipeDeleteConfirmLayer(
          colors: colors,
          headline: headline,
          title: title,
          message: message,
          confirmLabel: confirmLabel,
          keepLabel: keepLabel,
        ),
      );
    },
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      // Fade only — never scale the full layer. Scaling the overlay
      // shrinks its hit box so an edge swipe-back misses the popup
      // and lands on the article Dismissible underneath.
      return FadeTransition(opacity: curved, child: child);
    },
  );
  return result ?? false;
}

/// Resolves [AppColors] even when a test Theme omitted the extension.
AppColors swipeDeleteColorsOf(BuildContext context) {
  final ext = Theme.of(context).extension<AppColors>();
  if (ext != null) return ext;
  return Theme.of(context).brightness == Brightness.dark
      ? AppColors.dark
      : AppColors.white;
}

void _popConfirm(BuildContext context, bool value) {
  final nav = Navigator.of(context, rootNavigator: true);
  if (nav.canPop()) nav.pop(value);
}

/// Full-screen confirm host. The dimmed layer is opaque to *all* pointers
/// so a back-swipe cannot leak through to the article [Dismissible] under
/// the dialog. Any keep-swipe / tap on that layer pops with `false`.
class _SwipeDeleteConfirmLayer extends StatefulWidget {
  const _SwipeDeleteConfirmLayer({
    required this.colors,
    required this.headline,
    required this.confirmLabel,
    required this.keepLabel,
    this.title,
    this.message,
  });

  final AppColors colors;
  final String headline;
  final String? title;
  final String? message;
  final String confirmLabel;
  final String keepLabel;

  @override
  State<_SwipeDeleteConfirmLayer> createState() =>
      _SwipeDeleteConfirmLayerState();
}

class _SwipeDeleteConfirmLayerState extends State<_SwipeDeleteConfirmLayer> {
  bool _closed = false;
  bool _panningCard = false;
  Offset _cardDrag = Offset.zero;
  Offset? _barrierOrigin;
  Offset? _cardOrigin;

  void _close(bool confirmed) {
    if (_closed) return;
    _closed = true;
    if (!mounted) return;
    if (!confirmed) HapticFeedback.selectionClick();
    _popConfirm(context, confirmed);
  }

  bool _isKeepSwipe(Offset offset) {
    final dist = (MediaQuery.sizeOf(context).width * 0.16).clamp(56.0, 96.0);
    if (offset.dx.abs() >= dist) return true;
    if (offset.dy >= dist) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final fade = (1 - (_cardDrag.distance / 280)).clamp(0.55, 1.0);
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _closed = true;
      },
      child: Semantics(
        namesRoute: true,
        label: 'Delete confirmation',
        child: SizedBox.expand(
          child: Stack(
            fit: StackFit.expand,
            children: [
            Positioned.fill(
              child: Listener(
                key: const Key('swipe-delete-confirm-barrier'),
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) => _barrierOrigin = e.position,
                onPointerUp: (e) {
                  final origin = _barrierOrigin;
                  _barrierOrigin = null;
                  if (origin == null) return;
                  final delta = e.position - origin;
                  // Tap or any keep-swipe on the dimmed field = Keep.
                  if (delta.distance < 12 || _isKeepSwipe(delta)) {
                    _close(false);
                  }
                },
                onPointerCancel: (_) => _barrierOrigin = null,
                child: const ColoredBox(color: Colors.transparent),
              ),
            ),
            SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Listener(
                    onPointerDown: (e) {
                      _cardOrigin = e.position;
                      _panningCard = true;
                      _cardDrag = Offset.zero;
                    },
                    onPointerMove: (e) {
                      if (_cardOrigin == null) return;
                      final delta = e.position - _cardOrigin!;
                      setState(() {
                        _cardDrag = Offset(
                          delta.dx,
                          delta.dy < 0 ? delta.dy * 0.35 : delta.dy,
                        );
                      });
                    },
                    onPointerUp: (e) {
                      final origin = _cardOrigin;
                      _cardOrigin = null;
                      _panningCard = false;
                      if (origin == null) return;
                      final delta = e.position - origin;
                      if (_isKeepSwipe(delta)) {
                        _close(false);
                        return;
                      }
                      setState(() => _cardDrag = Offset.zero);
                    },
                    onPointerCancel: (_) {
                      _cardOrigin = null;
                      _panningCard = false;
                      setState(() => _cardDrag = Offset.zero);
                    },
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0.94, end: 1),
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                      builder: (context, scale, child) {
                        return Transform.scale(scale: scale, child: child);
                      },
                      child: AnimatedSlide(
                        offset: Offset(
                          _cardDrag.dx / 420,
                          _cardDrag.dy / 420,
                        ),
                        duration: _panningCard
                            ? Duration.zero
                            : const Duration(milliseconds: 140),
                        curve: Curves.easeOutCubic,
                        child: Opacity(
                          opacity: fade,
                          child: Material(
                            color: Colors.transparent,
                            child: SwipeDeleteConfirmCard(
                              colors: widget.colors,
                              headline: widget.headline,
                              title: widget.title,
                              message: widget.message,
                              confirmLabel: widget.confirmLabel,
                              keepLabel: widget.keepLabel,
                              onKeep: () => _close(false),
                              onConfirm: () => _close(true),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
              ],
            ),
          ),
        ),
      );
  }
}

/// Production confirm card. Public so widget tests can pump it without
/// a route, and so light/dark overflow checks stay cheap.
class SwipeDeleteConfirmCard extends StatelessWidget {
  const SwipeDeleteConfirmCard({
    super.key,
    required this.colors,
    required this.headline,
    this.title,
    this.message,
    this.confirmLabel = 'Delete',
    this.keepLabel = 'Keep',
    this.onKeep,
    this.onConfirm,
  });

  final AppColors colors;
  final String headline;
  final String? title;
  final String? message;
  final String confirmLabel;
  final String keepLabel;
  final VoidCallback? onKeep;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final trimmedTitle = title?.trim();
    final trimmedMessage = message?.trim();
    return ConstrainedBox(
      key: const Key('swipe-delete-confirm-card'),
      constraints: const BoxConstraints(maxWidth: 340),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.bg1,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: colors.border),
          boxShadow: [
            BoxShadow(
              color: colors.shadowColor,
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0x1AEF4444),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0x33EF4444)),
                ),
                child: const Icon(
                  LucideIcons.trash2,
                  size: 22,
                  color: Color(0xFFEF4444),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                headline,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: colors.text,
                  letterSpacing: -0.3,
                  height: 1.2,
                ),
              ),
              if (trimmedTitle != null && trimmedTitle.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  trimmedTitle,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.text2,
                    height: 1.35,
                  ),
                ),
              ],
              if (trimmedMessage != null && trimmedMessage.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  trimmedMessage,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    height: 1.4,
                    color: colors.text3,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _ConfirmActionButton(
                      key: const Key('swipe-delete-keep'),
                      label: keepLabel,
                      background: colors.bg2,
                      foreground: colors.text2,
                      border: colors.border,
                      onTap: () =>
                          (onKeep ?? () => _popConfirm(context, false))(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ConfirmActionButton(
                      key: const Key('swipe-delete-confirm'),
                      label: confirmLabel,
                      background: const Color(0xFFEF4444),
                      foreground: Colors.white,
                      onTap: () =>
                          (onConfirm ?? () => _popConfirm(context, true))(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfirmActionButton extends StatelessWidget {
  const _ConfirmActionButton({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
    this.border,
  });

  final String label;
  final Color background;
  final Color foreground;
  final Color? border;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          height: 48,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(14),
            border: border == null ? null : Border.all(color: border!),
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Red-tinted trash icon + "Delete" label rendered behind the card
/// while it's being dragged. Public so callers can use it as a
/// non-Dismissible placeholder for sanity tests, but most consumers
/// should just instantiate [SwipeToDelete].
///
/// [borderRadius] is shared with the wrapped card so corners line up
/// during partial drags (no jagged "background visible through card
/// corner" artifact).
class SwipeDeleteBackground extends StatelessWidget {
  const SwipeDeleteBackground({
    super.key,
    required this.alignEnd,
    this.borderRadius = 0,
    this.height,
  });

  /// `true` renders the icon flush with the trailing edge (revealed
  /// when the user swipes from end-to-start), `false` renders it flush
  /// with the leading edge (start-to-end). Both directions show the
  /// same destructive intent.
  final bool alignEnd;

  final double borderRadius;

  /// Optional fixed height — lets the red region match a child that
  /// has an explicit height (e.g. featured card is 280 px). When null,
  /// the background stretches to whatever the child renders to.
  final double? height;

  @override
  Widget build(BuildContext context) {
    final bg = Container(
      alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      padding: alignEnd
          ? const EdgeInsets.only(right: 24)
          : const EdgeInsets.only(left: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          begin: alignEnd ? Alignment.centerLeft : Alignment.centerRight,
          end: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
          colors: [
            const Color(0xFFEF4444).withValues(alpha: 0.15),
            const Color(0xFFEF4444).withValues(alpha: 0.40),
          ],
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            LucideIcons.trash2,
            size: 20,
            color: Color(0xFFEF4444),
          ),
          const SizedBox(width: 8),
          Text(
            'Delete',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: const Color(0xFFEF4444),
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
    if (height == null) return bg;
    return SizedBox(height: height, child: bg);
  }
}
