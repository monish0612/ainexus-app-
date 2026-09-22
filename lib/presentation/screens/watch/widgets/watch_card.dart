import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../data/services/price_watch/price_models.dart';
import '../../../../data/services/price_watch/price_parse.dart';

class WatchCard extends StatelessWidget {
  const WatchCard({
    super.key,
    required this.item,
    required this.colors,
    required this.onTap,
    this.highlighted = false,
  });

  final WatchItem item;
  final AppColors colors;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final drop = item.dropVsBase;
    final dropColor = drop > 0.5
        ? const Color(0xFF22C55E)
        : drop < -0.5
            ? const Color(0xFFEF4444)
            : colors.text3;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.bg2,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: highlighted ? AppColors.accent : colors.border,
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: item.imageUrl.isEmpty
                    ? Container(
                        width: 56,
                        height: 56,
                        color: colors.bg3,
                        child: Icon(LucideIcons.shoppingBag, color: colors.text4),
                      )
                    : CachedNetworkImage(
                        imageUrl: item.imageUrl,
                        width: 56,
                        height: 56,
                        memCacheWidth: (56 *
                                MediaQuery.devicePixelRatioOf(context))
                            .round(),
                        memCacheHeight: (56 *
                                MediaQuery.devicePixelRatioOf(context))
                            .round(),
                        fit: BoxFit.cover,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.store.label.toUpperCase(),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: colors.text3,
                        letterSpacing: 0.4,
                      ),
                    ),
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: colors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          formatInr(item.currentPrice),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: colors.text,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${drop >= 0 ? '−' : '+'}${drop.abs().toStringAsFixed(0)}%',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: dropColor,
                          ),
                        ),
                        if (item.isPaused) ...[
                          const SizedBox(width: 8),
                          Text(
                            'Paused',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: colors.text4,
                            ),
                          ),
                        ],
                        if (item.lastCheckError != null) ...[
                          const SizedBox(width: 8),
                          Icon(
                            LucideIcons.alertCircle,
                            size: 12,
                            color: const Color(0xFFEF4444).withValues(alpha: 0.8),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
