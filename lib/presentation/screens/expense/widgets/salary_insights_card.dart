import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../domain/entities/salary_entities.dart';
import '../../../providers/salary_providers.dart';
import '../modals/salary_entry_modal.dart';
import '../salary_screen.dart';

/// Compact, tappable salary summary shown at the top of the Insights tab.
/// Tapping anywhere opens the full [SalaryScreen]; the CTA enters/updates the
/// current month's in-hand salary.
class SalaryInsightsCard extends ConsumerWidget {
  const SalaryInsightsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final stats = ref.watch(salaryStatsProvider);
    final hike = stats.hikePct;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => showSalaryScreen(context),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.accent.withValues(alpha: 0.18),
                  colors.bg2,
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colors.border),
            ),
            child: stats.hasSalary
                ? _filled(context, stats, hike, colors)
                : _empty(context, colors),
          ),
        ),
      ),
    );
  }

  Widget _filled(
    BuildContext context,
    SalaryStats stats,
    double? hike,
    AppColors colors,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('💰', style: TextStyle(fontSize: 15)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Salary · ${monthKeyShort(stats.month)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.text3,
                ),
              ),
            ),
            if (hike != null) _miniHike(hike, colors),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, size: 18, color: colors.text4),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: Text(
                formatCurrency(stats.salary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: colors.text,
                ),
              ),
            ),
            const SizedBox(width: 10),
            _pill(
              'Saved ${stats.savedPct.clamp(-999, 999).toStringAsFixed(0)}%',
              stats.saved >= 0 ? const Color(0xFF51CF66) : const Color(0xFFFF6B6B),
              colors,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _bar(stats, colors),
      ],
    );
  }

  Widget _bar(SalaryStats stats, AppColors colors) {
    final spentFrac =
        stats.salary > 0 ? (stats.spent / stats.salary).clamp(0.0, 1.0) : 0.0;
    final over = stats.isOverspent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 8,
            child: Row(
              children: [
                if (spentFrac > 0)
                  Expanded(
                    flex: (spentFrac * 1000).round(),
                    child: Container(
                      color: over
                          ? const Color(0xFFFF6B6B)
                          : const Color(0xFFFCC419),
                    ),
                  ),
                if (1 - spentFrac > 0)
                  Expanded(
                    flex: ((1 - spentFrac) * 1000).round(),
                    child: Container(color: const Color(0xFF51CF66)),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${formatCurrency(stats.spent)} spent · ${formatCurrency(stats.saved)} left',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: colors.text3,
          ),
        ),
      ],
    );
  }

  Widget _empty(BuildContext context, AppColors colors) {
    return Row(
      children: [
        const Text('💰', style: TextStyle(fontSize: 18)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add this month\'s salary',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: colors.text,
                ),
              ),
              Text(
                'Unlock savings rate, budget & income stats',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: colors.text3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        FilledButton(
          onPressed: () => showSalaryEntryModal(context),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            'Enter',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  Widget _pill(String text, Color color, AppColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        text,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _miniHike(double pct, AppColors colors) {
    final flat = pct.abs() < 0.05;
    final up = pct > 0;
    final color = flat
        ? colors.text4
        : (up ? const Color(0xFF51CF66) : const Color(0xFFFF6B6B));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          flat ? Icons.remove : (up ? Icons.trending_up : Icons.trending_down),
          size: 13,
          color: color,
        ),
        const SizedBox(width: 2),
        Text(
          flat ? '0%' : '${up ? '+' : ''}${pct.toStringAsFixed(1)}%',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}
