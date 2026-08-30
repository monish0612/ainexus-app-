import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../core/theme/app_colors.dart';
import '../widgets/fluid_gauge.dart';
import 'chart_time.dart';
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
    this.range,
    this.axisOrigin,
  });

  /// x is seconds from the oldest point, y is 0–100.
  final List<FlSpot> spots;
  final double height;
  final Color? color;
  final bool interactive;
  final String emptyLabel;

  /// When set (enlarged Now / 7D / 30D), draw a time axis and put the stamp
  /// in the tooltip. Compact dashboard charts leave this null so their
  /// layout does not change.
  final StatsHistoryRange? range;
  final DateTime? axisOrigin;

  static List<FlSpot> spotsFrom(Iterable<({DateTime at, double? value})> samples) {
    final dated = [
      for (final s in samples)
        if (s.value != null && s.value!.isFinite) (at: s.at, value: s.value!),
    ];
    if (dated.isEmpty) return const [];
    dated.sort((a, b) => a.at.compareTo(b.at));
    final origin = dated.first.at;
    return [
      for (final s in dated)
        FlSpot(
          s.at.difference(origin).inMilliseconds / 1000.0,
          s.value.clamp(0, 100),
        ),
    ];
  }

  static List<FlSpot> downsample(List<FlSpot> spots, {int max = 64}) {
    if (spots.length <= max) return spots;
    final last = spots.length - 1;
    final step = last / (max - 1);
    final out = <FlSpot>[];
    var prev = -1;
    for (var i = 0; i < max; i++) {
      final idx = i == max - 1 ? last : (i * step).round();
      if (idx == prev) continue;
      out.add(spots[idx]);
      prev = idx;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    // Compact dashboards stay at 64 points with no axis. Enlarged Now keeps
    // every 1-second sample (~180). Enlarged 7D/30D downsample so ~43k
    // history points do not bury the four date ticks.
    final plotted = height < 140
        ? downsample(spots)
        : (range == StatsHistoryRange.d7 || range == StatsHistoryRange.d30)
            ? downsample(spots, max: 360)
            : spots;
    final active = color ??
        (plotted.isEmpty ? colors.text4 : FluidGauge.rampFor(plotted.last.y));

    if (plotted.length < 2) {
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

    final lastX = plotted.last.x;
    final minX = plotted.first.x;
    final showTimeAxis = height >= 140 && range != null && axisOrigin != null;
    final ticks = showTimeAxis ? chartAxisTicks(minX, lastX) : const <double>[];
    final tickInterval = ticks.length >= 2 ? ticks[1] - ticks[0] : null;

    DateTime? atX(double x) {
      final origin = axisOrigin;
      if (origin == null) return null;
      return origin.add(Duration(milliseconds: (x * 1000).round()));
    }

    return RepaintBoundary(
      child: SizedBox(
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
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: showTimeAxis,
                reservedSize: showTimeAxis ? 28 : 0,
                interval: tickInterval,
                getTitlesWidget: (v, _) {
                  if (!showTimeAxis) return const SizedBox.shrink();
                  final when = atX(v);
                  final r = range;
                  if (when == null || r == null) return const SizedBox.shrink();
                  final slack = math.max(0.75, (lastX - minX).abs() * 1e-4);
                  final onTick = ticks.any((t) => (t - v).abs() <= slack);
                  if (!onTick) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      formatChartAxisLabel(when, r),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: colors.text4,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            enabled: interactive,
            handleBuiltInTouches: interactive,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => colors.bg2,
              tooltipBorder: BorderSide(color: colors.border),
              getTooltipItems: (hits) {
                String textFor(LineBarSpot h) {
                  final pct = '${h.y.toStringAsFixed(h.y < 10 ? 1 : 0)}%';
                  final r = range;
                  final when = atX(h.x);
                  if (!showTimeAxis || r == null || when == null) return pct;
                  return '$pct\n${formatChartAxisLabel(when, r)}';
                }

                return [
                  for (final h in hits)
                    LineTooltipItem(
                      textFor(h),
                      GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: colors.text,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                ];
              },
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: plotted,
              isCurved: plotted.length <= 200,
              preventCurveOverShooting: plotted.length <= 200,
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
        // Live samples arrive every second on Now *and* while 7D/30D is open
        // (the gauge still watches the poll). A 220ms bezier tween on that
        // cadence is smear, not fluid — snap to the new polyline.
        duration: Duration.zero,
        curve: Curves.linear,
        ),
      ),
    );
  }
}

List<FlSpot> spotsForMetric(List<LiveStatSample> live, StatMetric metric) {
  return LiveSparkline.spotsFrom([
    for (final s in live) (at: s.at, value: s.valueOf(metric)),
  ]);
}
