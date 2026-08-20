import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../core/theme/app_colors.dart';
import 'stat_metric.dart';

/// Now / 7D / 30D. Shared by the enlarged detail view; the compact dashboard
/// does not fetch history, so it does not need this control.
class HistoryRangeSwitch extends StatelessWidget {
  const HistoryRangeSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final StatsHistoryRange value;
  final ValueChanged<StatsHistoryRange> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          for (final r in StatsHistoryRange.values)
            Expanded(
              child: _Chip(
                label: r.label,
                selected: r == value,
                onTap: () => onChanged(r),
              ),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Material(
      color: selected ? AppColors.accent.withValues(alpha: 0.16) : Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? AppColors.accent : colors.text3,
            ),
          ),
        ),
      ),
    );
  }
}
