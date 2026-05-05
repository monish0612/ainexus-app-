import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';

class CompactHeader extends StatelessWidget {
  const CompactHeader({
    super.key,
    required this.title,
    this.actionIcon,
    this.onActionTap,
    this.onAvatarTap,
    this.actionBadgeCount,
  });

  final String title;
  final IconData? actionIcon;
  final VoidCallback? onActionTap;
  final VoidCallback? onAvatarTap;
  /// When non-null and > 0, shows a small red badge on the action icon.
  final int? actionBadgeCount;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;

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
          GestureDetector(
            onTap: onAvatarTap,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [AppColors.accent, AppColors.accentCyan],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: const Center(
                child: Text(
                  '😎',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),
          ),
          const Spacer(),
          Text(
            title,
            style: TextStyle(
              color: colors.text,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (actionIcon != null)
            GestureDetector(
              onTap: onActionTap,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(actionIcon, color: colors.text2, size: 22),
                  if (actionBadgeCount != null && actionBadgeCount! > 0)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
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
            )
          else
            const SizedBox(width: 32),
        ],
      ),
    );
  }
}
