import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/time_greeting.dart';
import 'user_avatar.dart';

/// Polished Expense-tab greeting: time-based hello + display name.
/// News / Tutor / Cloud keep [CompactHeader].
class ExpenseHomeHeader extends StatelessWidget {
  const ExpenseHomeHeader({
    super.key,
    this.name = 'Monish',
    this.photoPath,
    this.now,
    this.onAvatarTap,
    this.onWatchTap,
    this.watchBadge = 0,
  });

  final String name;
  final String? photoPath;
  final DateTime? now;
  final VoidCallback? onAvatarTap;
  final VoidCallback? onWatchTap;
  final int watchBadge;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final when = now ?? DateTime.now();
    final greeting = greetingForDateTime(when);
    final nameLine = headerNameLine(name);

    return Container(
      decoration: BoxDecoration(
        color: colors.headerBg,
        border: Border(
          bottom: BorderSide(color: colors.border, width: 1),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                    color: colors.text3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  nameLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    letterSpacing: -0.6,
                    color: colors.text,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (onWatchTap != null) ...[
            GestureDetector(
              key: const Key('watch-entry'),
              onTap: onWatchTap,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 40,
                height: 40,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.local_offer_outlined,
                      size: 22,
                      color: colors.text2,
                    ),
                    if (watchBadge > 0)
                      Positioned(
                        right: 4,
                        top: 6,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFFEF4444),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
          UserAvatar(
            size: 40,
            photoPath: photoPath,
            onTap: onAvatarTap,
          ),
        ],
      ),
    );
  }
}
