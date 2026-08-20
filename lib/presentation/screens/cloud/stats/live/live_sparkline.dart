import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../core/theme/app_colors.dart';
import '../widgets/fluid_gauge.dart';
import 'stat_metric.dart';

/// A scrolling percentage line. Same widget on the compact dashboard (short)
/// and on [StatDetailScreen] (tall) — only [height] changes.
class LiveSparkline extends StatelessWidget {
  const LiveSparkline({
    super.key,
    required this.spots,
    this.height = 88,
    this.color,
    this.interactive = true,
    this.emptyLabel = 'Collecting live readings\u2026',
  });

  /// x is seconds from the oldest point, y is 0–100.
  final List<FlSpot> spots;
  final double height;
  final Color? color;
  final bool interactive;
  final String emptyLabel;

  static List<FlSpot> spotsFrom(Iterable<({DateTime at, double? value})> samples) {
    final dated = [
      for (final s in samples)
        if (s.value != null) (at: s.at, value: s.value!),
    ];
    if (dated.isEmpty) return const [];
    final origin = dated.first.at;
    return [
      for (final s in dated)
        FlSpot(
          s.at.difference(origin).inMilliseconds / 1000.0,
          s.value.clamp(0, 100),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final active = color ??
        (spots.isEmpty ? colors.text4 : FluidGauge.rampFor(spots.last.y));

    if (spots.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            emptyLabel,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: colors.text3,
            ),
          ),
        ),
      );
    }

    final lastX = spots.last.x;
    final minX = spots.first.x;

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: 100,
          minX: minX,
          maxX: lastX <= minX ? minX + 1 : lastX,
          clipData: const FlClipData.all(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 25,
            getDrawingHorizontalLine: (v) => FlLine(
              color: colors.border.withValues(alpha: 0.7),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: height >= 140,
                reservedSize: 28,
                interval: 50,
                getTitlesWidget: (v, _) => Text(
                  '${v.round()}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: colors.text4,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineTouchData: LineTouchData(
            enabled: interactive,
            handleBuiltInTouches: interactive,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => colors.bg2,
              tooltipBorder: BorderSide(color: colors.border),
              getTooltipItems: (hits) => [
                for (final h in hits)
                  LineTooltipItem(
                    '${h.y.toStringAsFixed(h.y < 10 ? 1 : 0)}%',
                    GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: colors.text,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              preventCurveOverShooting: true,
              color: active,
              barWidth: height >= 140 ? 3 : 2,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    active.withValues(alpha: 0.28),
                    active.withValues(alpha: 0.02),
                  ],
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      ),
    );
  }
}

List<FlSpot> spotsForMetric(List<LiveStatSample> live, StatMetric metric) {
  return LiveSparkline.spotsFrom([
    for (final s in live) (at: s.at, value: s.valueOf(metric)),
  ]);
}
