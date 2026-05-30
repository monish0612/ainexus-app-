import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Generic swipe-to-delete wrapper around an arbitrary card widget.
///
/// Currently consumed by the News > For You > Movies/General row + the
/// big featured card on those same chips, where the user wants to nuke
/// a single article without going through the FAB Clear-All flow. The
/// widget is intentionally generic — the only side-effect is calling
/// [onDelete], so a future caller can drop it on top of any rounded or
/// flat card and get the same UX.
///
/// Behavior contract:
///   • Accepts a swipe in EITHER horizontal direction (start↔end). The
///     same red trash background is rendered on both sides for visual
///     symmetry — "swipe left" and "swipe right" both unambiguously
///     mean DELETE. No confirmation dialog (the host can show one if
///     the destructive action warrants it).
///   • `confirmDismiss` always returns `false` so the Dismissible NEVER
///     actually animates the child away — instead it fires [onDelete]
///     inline and trusts the host's data layer (Drift stream / state
///     notifier) to drop the row on the next rebuild. This eliminates
///     the "ghost row" race where Dismissible removes a widget while the
///     underlying stream re-emits the same item one tick later — a
///     race that produces visible flickers in manual testing.
///   • Fires a light-impact haptic when the swipe commits, matching the
///     haptic pattern used elsewhere in the app.
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
        HapticFeedback.lightImpact();
        // Inline-delete pattern — see class doc.
        onDelete();
        return false;
      },
      child: child,
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
