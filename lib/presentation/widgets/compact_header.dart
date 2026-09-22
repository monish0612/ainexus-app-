import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';
import 'user_avatar.dart';

class CompactHeader extends StatelessWidget {
  const CompactHeader({
    super.key,
    required this.title,
    this.actionIcon,
    this.onActionTap,
    this.onAvatarTap,
    this.actionBadgeCount,
    this.actionTooltip,
    this.photoPath,
  });

  final String title;
  final IconData? actionIcon;
  final VoidCallback? onActionTap;
  final VoidCallback? onAvatarTap;

  /// When non-null and > 0, shows a small red badge on the action icon.
  final int? actionBadgeCount;

  /// Accessibility / long-press label for the trailing action.
  final String? actionTooltip;

  /// Local JPEG path from Settings → profile photo. Null keeps the 😎 fallback.
  final String? photoPath;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;

    Widget? action;
    if (actionIcon != null) {
      final tip = actionTooltip;
      final spoken = (tip != null && tip.isNotEmpty) ? tip : 'Action';
      action = Semantics(
        button: true,
        label: spoken,
        child: GestureDetector(
          onTap: onActionTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Icon(actionIcon, color: colors.text2, size: 22),
                  if (actionBadgeCount != null && actionBadgeCount! > 0)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        constraints:
                            const BoxConstraints(minWidth: 14, minHeight: 14),
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(color: colors.bg, width: 1.5),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          actionBadgeCount! > 9 ? '9+' : '${actionBadgeCount!}',
                          style: const TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFFFFFFF),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      if (tip != null && tip.isNotEmpty) {
        action = Tooltip(message: tip, child: action);
      }
    }

    return Container(
      height: AppConstants.headerHeight,
      decoration: BoxDecoration(
        color: colors.headerBg,
        border: Border(
          bottom: BorderSide(color: colors.border, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          UserAvatar(
            size: 32,
            hitSize: 48,
            photoPath: photoPath,
            onTap: onAvatarTap,
          ),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          action ?? const SizedBox(width: 48, height: 48),
        ],
      ),
    );
  }
}
