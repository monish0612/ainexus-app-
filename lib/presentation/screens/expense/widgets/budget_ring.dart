import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../settings/settings_controller.dart';

class BudgetRing extends ConsumerWidget {
  const BudgetRing({
    super.key,
    required this.budget,
    required this.spent,
    this.onSetBudget,
  });

  final double budget;
  final double spent;
  final VoidCallback? onSetBudget;

  static const double _strokeWidth = 8;

  static const Color _green = Color(0xFF51CF66);
  static const Color _amber = Color(0xFFFCC419);
  static const Color _red = Color(0xFFFF6B6B);

  static Color _statusColor(double budget, double spent) {
    if (budget <= 0) return AppColors.accent;
    final pct = (spent / budget) * 100;
    if (pct >= 100) return _red;
    if (pct >= 70) return _amber;
    return _green;
  }

  static String _statusLabel(double budget, double spent) {
    if (budget <= 0) return '';
    final pct = (spent / budget) * 100;
    if (pct >= 100) return 'OVER BUDGET';
    if (pct >= 70) return 'AT RISK';
    return 'ON TRACK';
  }

  static double _progress(double budget, double spent) {
    if (budget <= 0) return 0;
    return (spent / budget).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(settingsProvider.select((s) => s.isDark));
    final colors = Theme.of(context).extension<AppColors>()!;
    final screenWidth = MediaQuery.of(context).size.width;
    final ringSize = (screenWidth * 0.38).clamp(130.0, 165.0);

    return _BudgetRingBody(
      budget: budget,
      spent: spent,
      colors: colors,
      onSetBudget: onSetBudget,
      size: ringSize,
      strokeWidth: _strokeWidth,
      statusColor: _statusColor(budget, spent),
      statusLabel: _statusLabel(budget, spent),
      targetProgress: _progress(budget, spent),
    );
  }
}

class _BudgetRingBody extends StatefulWidget {
  const _BudgetRingBody({
    required this.budget,
    required this.spent,
    required this.colors,
    required this.onSetBudget,
    required this.size,
    required this.strokeWidth,
    required this.statusColor,
    required this.statusLabel,
    required this.targetProgress,
  });

  final double budget;
  final double spent;
  final AppColors colors;
  final VoidCallback? onSetBudget;
  final double size;
  final double strokeWidth;
  final Color statusColor;
  final String statusLabel;
  final double targetProgress;

  @override
  State<_BudgetRingBody> createState() => _BudgetRingBodyState();
}

class _BudgetRingBodyState extends State<_BudgetRingBody>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _progressAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _progressAnim = Tween<double>(
      begin: 0,
      end: widget.targetProgress,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    )..addListener(_onTick);
    _controller.forward();
  }

  void _onTick() => setState(() {});

  @override
  void didUpdateWidget(covariant _BudgetRingBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetProgress != widget.targetProgress) {
      _progressAnim.removeListener(_onTick);
      final from = _progressAnim.value;
      _controller.reset();
      _progressAnim = Tween<double>(begin: from, end: widget.targetProgress)
          .animate(
            CurvedAnimation(parent: _controller, curve: Curves.easeOut),
          )
        ..addListener(_onTick);
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _progressAnim.removeListener(_onTick);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.budget - widget.spent;
    final isOver = remaining < 0;
    final trackColor = widget.budget <= 0
        ? widget.colors.text4.withValues(alpha: 0.12)
        : widget.statusColor.withValues(alpha: 0.1);
    final progressColor =
        widget.budget <= 0 ? widget.colors.text3 : widget.statusColor;

    if (widget.budget <= 0) {
      return _buildNoBudget();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size.square(widget.size),
                painter: _BudgetRingPainter(
                  trackColor: trackColor,
                  progressColor: progressColor,
                  progress: _progressAnim.value,
                  strokeWidth: widget.strokeWidth,
                  glowColor: progressColor,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isOver
                          ? '-${formatCurrency(remaining.abs())}'
                          : formatCurrency(remaining),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: isOver ? 20 : 22,
                        fontWeight: FontWeight.w800,
                        color: widget.statusColor,
                        height: 1.1,
                        letterSpacing: -0.5,
                      ),
                    ),
                    if (widget.statusLabel.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        widget.statusLabel,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: widget.colors.text4,
                          letterSpacing: 1.8,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StatPill(
              label: 'Spent',
              value: formatCurrency(widget.spent),
              color: widget.colors.text2,
              bg: widget.colors.bg3,
            ),
            const SizedBox(width: 8),
            _StatPill(
              label: 'Budget',
              value: formatCurrency(widget.budget),
              color: widget.colors.text3,
              bg: widget.colors.bg2,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNoBudget() {
    final ring = SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(widget.size),
            painter: _BudgetRingPainter(
              trackColor: widget.colors.text4.withValues(alpha: 0.12),
              progressColor: widget.colors.text3,
              progress: 0,
              strokeWidth: widget.strokeWidth,
              glowColor: widget.colors.text3,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Set Budget',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: widget.colors.text,
                  ),
                ),
                if (widget.onSetBudget != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Tap to set monthly limit',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      color: widget.colors.text4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (widget.onSetBudget != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onSetBudget,
          customBorder: const CircleBorder(),
          child: ring,
        ),
      );
    }
    return ring;
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.label,
    required this.value,
    required this.color,
    required this.bg,
  });

  final String label;
  final String value;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: color.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetRingPainter extends CustomPainter {
  _BudgetRingPainter({
    required this.trackColor,
    required this.progressColor,
    required this.progress,
    required this.strokeWidth,
    required this.glowColor,
  });

  final Color trackColor;
  final Color progressColor;
  final double progress;
  final double strokeWidth;
  final Color glowColor;

  static const double _startRad = 135 * math.pi / 180;
  static const double _fullSweepRad = 270 * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _startRad, _fullSweepRad, false, trackPaint);

    if (progress <= 0) return;

    final sweep = _fullSweepRad * progress;

    final glow = Paint()
      ..color = glowColor.withAlpha(0x30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 8
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawArc(rect, _startRad, sweep, false, glow);

    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _startRad, sweep, false, progressPaint);
  }

  @override
  bool shouldRepaint(covariant _BudgetRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
