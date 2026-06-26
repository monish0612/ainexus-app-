import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../domain/entities/expense_insight.dart';

/// Generative, personalized AI recommendation shown above the results.
///
/// While [loading] (or [recommendation] is null) it renders an animated shimmer
/// skeleton so the table can paint instantly and the insight "streams in".
/// Once ready it shows a greeting (by name), a bold headline insight, an
/// actionable tip, and tappable follow-up chips — all bound to verified figures.
class AiRecommendationCard extends StatefulWidget {
  const AiRecommendationCard({
    super.key,
    required this.colors,
    required this.loading,
    required this.recommendation,
    this.onChip,
  });

  final AppColors colors;
  final bool loading;
  final GroundedRecommendation? recommendation;
  final void Function(String chip)? onChip;

  @override
  State<AiRecommendationCard> createState() => _AiRecommendationCardState();
}

class _AiRecommendationCardState extends State<AiRecommendationCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  Color _toneColor(InsightTone tone) {
    switch (tone) {
      case InsightTone.warning:
        return AppColors.categoryBills; // amber
      case InsightTone.positive:
        return AppColors.categoryGrocery; // green
      case InsightTone.info:
        return AppColors.accent; // blue
    }
  }

  IconData _toneIcon(InsightTone tone) {
    switch (tone) {
      case InsightTone.warning:
        return LucideIcons.trendingUp;
      case InsightTone.positive:
        return LucideIcons.trendingDown;
      case InsightTone.info:
        return LucideIcons.sparkles;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final rec = widget.recommendation;
    final showLoading = widget.loading || rec == null || !rec.hasContent;
    final accent = showLoading ? AppColors.accent : _toneColor(rec.tone);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.16),
            accent.withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.30)),
      ),
      child: showLoading
          ? _buildLoading(colors, accent)
          : _buildContent(colors, accent, rec),
    );
  }

  Widget _buildContent(
    AppColors colors,
    Color accent,
    GroundedRecommendation rec,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(_toneIcon(rec.tone), size: 16, color: accent),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (rec.greeting.isNotEmpty)
                    Text(
                      rec.greeting,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.text2,
                      ),
                    ),
                  if (rec.headline.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      rec.headline,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14.5,
                        height: 1.32,
                        fontWeight: FontWeight.w700,
                        color: colors.text,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (rec.tip.isNotEmpty) ...[
          const SizedBox(height: 9),
          Text(
            rec.tip,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              height: 1.45,
              fontWeight: FontWeight.w500,
              color: colors.text2,
            ),
          ),
        ],
        if (rec.chips.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final chip in rec.chips)
                _Chip(
                  colors: colors,
                  accent: accent,
                  label: chip,
                  onTap: widget.onChip == null
                      ? null
                      : () => widget.onChip!(chip),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildLoading(AppColors colors, Color accent) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PulsingOrb(controller: _shimmer, accent: accent),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              _ShimmerBar(controller: _shimmer, colors: colors, widthFactor: 0.45),
              const SizedBox(height: 9),
              _ShimmerBar(controller: _shimmer, colors: colors, widthFactor: 0.95),
              const SizedBox(height: 7),
              _ShimmerBar(controller: _shimmer, colors: colors, widthFactor: 0.7),
            ],
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.colors,
    required this.accent,
    required this.label,
    this.onTap,
  });

  final AppColors colors;
  final Color accent;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withValues(alpha: 0.28)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.arrowUpRight, size: 12, color: accent),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PulsingOrb extends StatelessWidget {
  const _PulsingOrb({required this.controller, required this.accent});

  final AnimationController controller;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = (controller.value * 2 - 1).abs(); // 1->0->1 triangle
        final glow = 0.35 + 0.45 * (1 - t);
        return Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(9),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: glow * 0.5),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Icon(LucideIcons.sparkles, size: 16, color: accent),
        );
      },
    );
  }
}

class _ShimmerBar extends StatelessWidget {
  const _ShimmerBar({
    required this.controller,
    required this.colors,
    required this.widthFactor,
  });

  final AnimationController controller;
  final AppColors colors;
  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final base = colors.bg3;
          final highlight = colors.bg4;
          final pos = controller.value;
          return Container(
            height: 11,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              gradient: LinearGradient(
                begin: Alignment(-1 - 2 * (1 - pos), 0),
                end: Alignment(1 - 2 * (1 - pos) + 1, 0),
                colors: [base, highlight, base],
                stops: const [0.35, 0.5, 0.65],
              ),
            ),
          );
        },
      ),
    );
  }
}
