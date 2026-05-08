import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Compact, collapsed-by-default disclosure for the SOURCES list shown after
/// a grounded / Tavily search response.
///
/// The default state is a single chip (e.g. "🔗 4 sources ▾") so the answer
/// card stays the focal point of the screen and we no longer occupy a large
/// chunk of vertical space with always-visible source cards. Tapping the
/// chip animates the [body] open inline; tapping again collapses it.
///
/// The chip and animation are intentionally lightweight so the widget can
/// be used both inside scrollable result panes (Tutor InsightAI tab) and as
/// the trailing element of the standalone search lookup screen.
class SourcesDisclosure extends StatefulWidget {
  const SourcesDisclosure({
    super.key,
    required this.count,
    required this.accentColor,
    required this.body,
    this.label = 'sources',
    this.singularLabel,
    this.initiallyExpanded = false,
    this.padding = EdgeInsets.zero,
  });

  /// Total number of sources, displayed in the chip. Renders nothing when 0.
  final int count;

  /// Brand colour for the chip — usually matches the surrounding result card.
  final Color accentColor;

  /// The expanded content. Built lazily — never mounted while collapsed —
  /// so we don't pay layout cost for hidden widgets.
  final Widget body;

  /// Plural label, used when [count] != 1.
  final String label;

  /// Singular form. Defaults to [label] with a trailing 's' stripped.
  final String? singularLabel;

  /// Whether the disclosure starts open. Defaults to false (the whole point
  /// of the widget — keep the screen calm by default).
  final bool initiallyExpanded;

  /// Outer padding around the disclosure block.
  final EdgeInsets padding;

  @override
  State<SourcesDisclosure> createState() => _SourcesDisclosureState();
}

class _SourcesDisclosureState extends State<SourcesDisclosure>
    with SingleTickerProviderStateMixin {
  late bool _expanded = widget.initiallyExpanded;
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: _expanded ? 1.0 : 0.0,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    HapticFeedback.selectionClick();
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _ctrl.forward();
      } else {
        _ctrl.reverse();
      }
    });
  }

  String _resolvedLabel() {
    if (widget.count == 1) {
      if (widget.singularLabel != null && widget.singularLabel!.isNotEmpty) {
        return widget.singularLabel!;
      }
      // Strip a trailing 's' (e.g. "sources" → "source"). Fallback to plural
      // when the label doesn't follow that convention.
      if (widget.label.endsWith('s')) {
        return widget.label.substring(0, widget.label.length - 1);
      }
    }
    return widget.label;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.count <= 0) return const SizedBox.shrink();
    final c = widget.accentColor;

    return Padding(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPill(c),
          // ClipRect ensures the body doesn't overflow during the size
          // animation, and keeps the layout clean when the body has its own
          // shadows / borders. AnimatedSize collapses to height-0 when not
          // expanded so the hidden body adds zero layout cost.
          ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _expanded
                  ? Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: widget.body,
                    )
                  : const SizedBox(width: double.infinity, height: 0),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPill(Color c) {
    final label = _resolvedLabel();
    return Semantics(
      button: true,
      toggled: _expanded,
      label: '${widget.count} $label, '
          '${_expanded ? 'tap to collapse' : 'tap to expand'}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _toggle,
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: c.withValues(alpha: _expanded ? 0.14 : 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: c.withValues(alpha: _expanded ? 0.32 : 0.18),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.link, size: 12, color: c),
                const SizedBox(width: 6),
                Text(
                  '${widget.count} $label',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: c,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(width: 6),
                RotationTransition(
                  turns: Tween<double>(begin: 0, end: 0.5).animate(
                    CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
                  ),
                  child: Icon(LucideIcons.chevronDown, size: 12, color: c),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
