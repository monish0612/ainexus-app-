import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../data/services/price_watch/history_series.dart';
import '../../../../data/services/price_watch/price_models.dart';
import '../../../../data/services/price_watch/price_parse.dart';

class PriceHistoryChart extends StatefulWidget {
  const PriceHistoryChart({
    super.key,
    required this.series,
    this.targetPrice,
    this.basePrice,
    this.accent,
    this.onSelectPoint,
    this.height = 168,
  });

  final HistorySeries series;
  final double? targetPrice;
  final double? basePrice;
  final Color? accent;
  final ValueChanged<WatchPricePoint?>? onSelectPoint;
  final double height;

  @override
  State<PriceHistoryChart> createState() => _PriceHistoryChartState();
}

class _PriceHistoryChartState extends State<PriceHistoryChart> {
  String? _lastSnapId;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final accent = widget.accent ?? AppColors.accent;
    if (widget.series.isEmpty) {
      return _ShimmerChart(height: widget.height, colors: colors);
    }
    if (widget.series.isSingle) {
      return _SinglePoint(
        series: widget.series,
        colors: colors,
        accent: accent,
        height: widget.height,
      );
    }
    final spots = [
      for (final p in widget.series.points)
        FlSpot(p.checkedAt.millisecondsSinceEpoch.toDouble(), p.price),
    ];
    final bounds = widget.series.yBounds(
      target: widget.targetPrice,
      base: widget.basePrice,
    );
    return RepaintBoundary(
      child: SizedBox(
        height: widget.height,
        child: LineChart(
          LineChartData(
            minX: spots.first.x,
            maxX: spots.last.x,
            minY: bounds.$1,
            maxY: bounds.$2,
            gridData: const FlGridData(show: false),
            titlesData: const FlTitlesData(show: false),
            borderData: FlBorderData(show: false),
            extraLinesData: ExtraLinesData(
              extraLinesOnTop: false,
              horizontalLines: [
                if (widget.basePrice != null && widget.basePrice! > 0)
                  HorizontalLine(
                    y: widget.basePrice!,
                    color: colors.text5,
                    strokeWidth: 1,
                    dashArray: const [6, 5],
                  ),
                if (widget.targetPrice != null && widget.targetPrice! > 0)
                  HorizontalLine(
                    y: widget.targetPrice!,
                    color: accent.withValues(alpha: 0.55),
                    strokeWidth: 1.2,
                    dashArray: const [5, 4],
                  ),
              ],
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                preventCurveOverShooting: true,
                color: accent,
                barWidth: 2.4,
                isStrokeCapRound: true,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      accent.withValues(alpha: 0.28),
                      accent.withValues(alpha: 0.02),
                    ],
                  ),
                ),
              ),
            ],
            lineTouchData: LineTouchData(
              handleBuiltInTouches: true,
              getTouchedSpotIndicator: (bar, indexes) {
                return [
                  for (final _ in indexes)
                    TouchedSpotIndicatorData(
                      FlLine(color: accent.withValues(alpha: 0.35), strokeWidth: 1),
                      FlDotData(
                        show: true,
                        getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                          radius: 5,
                          color: accent,
                          strokeWidth: 2,
                          strokeColor: colors.bg1,
                        ),
                      ),
                    ),
                ];
              },
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => colors.bg3,
                tooltipRoundedRadius: 12,
                tooltipPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                getTooltipItems: (touched) {
                  return [
                    for (final t in touched)
                      LineTooltipItem(
                        _tooltip(widget.series.nearestRaw(t.x)),
                        GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colors.text,
                          height: 1.35,
                        ),
                      ),
                  ];
                },
              ),
              touchCallback: (event, response) {
                if (!event.isInterestedForInteractions ||
                    response?.lineBarSpots == null ||
                    response!.lineBarSpots!.isEmpty) {
                  if (_lastSnapId != null) {
                    _lastSnapId = null;
                    widget.onSelectPoint?.call(null);
                  }
                  return;
                }
                final p = widget.series.nearestRaw(response.lineBarSpots!.first.x);
                if (p == null || p.id == _lastSnapId) return;
                _lastSnapId = p.id;
                HapticFeedback.selectionClick();
                widget.onSelectPoint?.call(p);
              },
            ),
          ),
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        ),
      ),
    );
  }

  String _tooltip(WatchPricePoint? p) {
    if (p == null) return '';
    final when = formatRelativeTime(p.checkedAt.toLocal());
    return '${formatInr(p.price)}\n$when';
  }
}

class _SinglePoint extends StatelessWidget {
  const _SinglePoint({
    required this.series,
    required this.colors,
    required this.accent,
    required this.height,
  });

  final HistorySeries series;
  final AppColors colors;
  final Color accent;
  final double height;

  @override
  Widget build(BuildContext context) {
    final price = series.last ?? 0;
    return SizedBox(
      height: height,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            formatInr(price),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: colors.text,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Next check adds the line.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: colors.text3,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.35),
                  blurRadius: 10,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShimmerChart extends StatelessWidget {
  const _ShimmerChart({required this.height, required this.colors});

  final double height;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: colors.shimmerBase,
      highlightColor: colors.shimmerHighlight,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: colors.bg2,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}
