import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import 'block_selectable.dart';

const Key kSearchResultShareKey = ValueKey('search_result_share');
const Key kSearchResultShareSaveClusterKey =
    ValueKey('search_result_share_save');

/// Same violet as the History pill and a filled bookmark.
const Color kSearchActionAccent = Color(0xFFC084FC);

/// Icon color that stays readable on AMOLED black and on white.
Color searchActionIconColor(AppColors colors, {required bool enabled}) {
  if (!enabled) {
    return colors.isDark
        ? const Color(0xFF6D5A7A)
        : const Color(0xFFC4B5FD);
  }
  return colors.isDark
      ? const Color(0xFFE9D5FF)
      : const Color(0xFF6D28D9);
}

/// Compact share affordance matching the news-tab share2 icon.
class SearchShareIconButton extends StatelessWidget {
  const SearchShareIconButton({
    super.key,
    required this.onPressed,
    required this.colors,
    this.enclosed = false,
  });

  final VoidCallback? onPressed;
  final AppColors colors;

  /// True when this button already sits inside [SearchShareSaveCluster].
  final bool enclosed;

  @override
  Widget build(BuildContext context) {
    final button = Tooltip(
      message: 'Share',
      child: IconButton(
        key: kSearchResultShareKey,
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        icon: Icon(
          LucideIcons.share2,
          size: 18,
          color: searchActionIconColor(colors, enabled: onPressed != null),
        ),
      ),
    );
    if (enclosed) return button;
    return _SearchActionGlass(colors: colors, child: button);
  }
}

/// Share + Save sitting in one pill so the header stays fluid next to
/// the service badge. Save stays a caller-owned widget so bookmark
/// draft/promote logic is untouched.
class SearchShareSaveCluster extends StatelessWidget {
  const SearchShareSaveCluster({
    super.key,
    required this.colors,
    required this.onShare,
    required this.saveButton,
  });

  final AppColors colors;
  final VoidCallback? onShare;
  final Widget saveButton;

  @override
  Widget build(BuildContext context) {
    return NonSelectableChrome(
      child: _SearchActionGlass(
        key: kSearchResultShareSaveClusterKey,
        colors: colors,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SearchShareIconButton(
              onPressed: onShare,
              colors: colors,
              enclosed: true,
            ),
            Container(
              width: 1,
              height: 16,
              color: kSearchActionAccent.withValues(
                alpha: colors.isDark ? 0.32 : 0.22,
              ),
            ),
            saveButton,
          ],
        ),
      ),
    );
  }
}

/// History-matching violet glass. Never reuse [AppColors.bg2] with a
/// replaced alpha — that turns the 5% white overlay into a solid blob.
class _SearchActionGlass extends StatelessWidget {
  const _SearchActionGlass({
    super.key,
    required this.colors,
    required this.child,
  });

  final AppColors colors;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final fill = kSearchActionAccent.withValues(
      alpha: colors.isDark ? 0.14 : 0.10,
    );
    final border = kSearchActionAccent.withValues(
      alpha: colors.isDark ? 0.42 : 0.30,
    );
    final glow = colors.isDark
        ? kSearchActionAccent.withValues(alpha: 0.22)
        : const Color(0xFF7C3AED).withValues(alpha: 0.14);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: glow,
            blurRadius: colors.isDark ? 12 : 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}
