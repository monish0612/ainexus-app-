import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import 'news_chrome.dart';
import 'news_feed_filters.dart';

/// Thumb-zone category dock. Tap a destination to switch; cards above keep
/// swipe-to-delete. There is no horizontal pager, so a left/right card swipe
/// cannot jump categories.
///
/// All five destinations stay on-screen (no chip scroller), matching the ET
/// "Top News / Markets" pattern — docked under the feed so the thumb can
/// reach them without covering article rows.
class NewsCategoryRail extends StatelessWidget {
  const NewsCategoryRail({
    super.key,
    required this.colors,
    required this.selected,
    required this.counts,
    required this.onSelected,
  });

  final AppColors colors;
  final String selected;
  final Map<String, int> counts;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.navBg.withValues(alpha: colors.isDark ? 0.94 : 0.98),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.border)),
          boxShadow: [
            BoxShadow(
              color: colors.shadowColor
                  .withValues(alpha: colors.isDark ? 0.35 : 0.08),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SizedBox(
          key: const ValueKey<String>('news-category-rail'),
          height: kNewsCategoryRailHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
            child: Row(
              children: [
                for (final label in kNewsCategoryRailLabels)
                  Expanded(
                    child: _RailTab(
                      label: label,
                      count: counts[label] ?? 0,
                      selected: label == selected,
                      colors: colors,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        onSelected(label);
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RailTab extends StatelessWidget {
  const _RailTab({
    required this.label,
    required this.count,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final AppColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = label == 'All' ? AppColors.accent : newsCategoryColor(label);
    final fg = selected ? accent : colors.text4;
    final icon =
        label == 'All' ? LucideIcons.layers : newsCategoryIcon(label);

    return Semantics(
      button: true,
      selected: selected,
      label: count > 0 ? '$label, $count' : label,
      child: Material(
        key: ValueKey<String>('news-rail-$label'),
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: fg),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      letterSpacing: -0.2,
                      color: fg,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  height: 2,
                  width: selected ? 18 : 0,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
