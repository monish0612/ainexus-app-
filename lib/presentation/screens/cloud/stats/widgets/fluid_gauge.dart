import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../core/theme/app_colors.dart';

/// An arc gauge that always travels to a new reading instead of jumping to it.
///
/// Generalised from `_BudgetRingPainter`, with two differences that matter at a
/// two-second poll:
///
/// **It tweens from wherever it currently is.** A CPU gauge fed a fresh sample
/// every two seconds would flicker if each one snapped into place. Every new
/// value animates over ~700 ms from the arc's *current* position, so a sample
/// arriving mid-animation bends the motion rather than restarting it — which is
/// what makes a screen full of live numbers feel fluid instead of twitchy.
///
/// **The centre number is tweened in tabular figures.** Proportional digits are
/// different widths, so a counter running through 9 → 10 → 11 jitters
/// horizontally on every frame. `FontFeature.tabularFigures` fixes the advance
/// width and the number counts up in place.
class FluidGauge extends StatefulWidget {
  const FluidGauge({
    super.key,
    required this.value,
    required this.label,
    this.max = 100,
    this.unit = '%',
    this.size = 132,
    this.strokeWidth = 10,
    this.color,
    this.subtitle,
    this.decimals = 0,
    this.duration = const Duration(milliseconds: 700),
    this.showValue = true,
  });

  /// The reading. Null renders an em dash rather than a zero, because "we could
  /// not measure this" and "this is zero" are different facts.
  final double? value;

  final double max;
  final String label;
  final String unit;
  final double size;
  final double strokeWidth;

  /// Defaults to a green/amber/red ramp off [value]. Pass a colour to override
  /// when the caller knows better — memory pressure, for instance, comes from
  /// the NAS and is not a simple function of the percentage.
  final Color? color;

  final String? subtitle;
  final int decimals;
  final Duration duration;

  /// False for the compact variants that carry their reading in a caption.
  final bool showValue;

  static const Color green = Color(0xFF51CF66);
  static const Color amber = Color(0xFFFCC419);
  static const Color red = Color(0xFFFF6B6B);

  /// The same 70/80 thresholds ZFS and `reporter.py` use, so a gauge going amber
  /// on the phone means the same thing as an amber line in the daily report.
  static Color rampFor(double pct) {
    if (pct >= 80) return red;
    if (pct >= 70) return amber;
    return green;
  }

  @override
  State<FluidGauge> createState() => _FluidGaugeState();
}

class _FluidGaugeState extends State<FluidGauge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  /// Where the arc is drawn from and to. Held explicitly rather than read off a
  /// Tween so that a mid-flight update can start from the current position.
  late double _from = _target;
  late double _to = _target;

  double get _target {
    final v = widget.value;
    if (v == null || widget.max <= 0) return 0;
    return (v / widget.max).clamp(0.0, 1.0);
  }

  @override
  void initState() {
    super.initState();
    // First paint sweeps up from empty, which reads as the gauge filling rather
    // than as a value that was always there.
    _from = 0;
    _to = _target;
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant FluidGauge old) {
    super.didUpdateWidget(old);
    final next = _target;
    if ((next - _to).abs() < 0.0005) return;
    // Start from where the arc actually is, not from the last target. Without
    // this, a sample landing mid-animation would jump back and re-run.
    _from = _fraction;
    _to = next;
    _controller
      ..reset()
      ..forward();
  }

  double get _fraction {
    final t = Curves.easeOutCubic.transform(_controller.value);
    return _from + (_to - _from) * t;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final value = widget.value;
    final pct = value == null || widget.max <= 0
        ? 0.0
        : ((value / widget.max) * 100).clamp(0.0, 100.0);
    final active = widget.color ?? FluidGauge.rampFor(pct);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final fraction = _fraction;
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size.square(widget.size),
                painter: _FluidGaugePainter(
                  fraction: fraction,
                  strokeWidth: widget.strokeWidth,
                  trackColor: colors.text4.withValues(alpha: 0.14),
                  activeColor: active,
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: widget.size * 0.16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.showValue)
                      FittedBox(
                        child: Text(
                          value == null
                              ? '—'
                              // Read off the animation, not the prop, so the
                              // number and the arc arrive together.
                              : '${(fraction * widget.max).toStringAsFixed(widget.decimals)}${widget.unit}',
                          maxLines: 1,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: widget.size * 0.2,
                            fontWeight: FontWeight.w800,
                            color: value == null ? colors.text3 : active,
                            height: 1.05,
                            letterSpacing: -0.5,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      widget.label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: widget.size * 0.082,
                        fontWeight: FontWeight.w700,
                        color: colors.text3,
                        letterSpacing: 0.6,
                      ),
                    ),
                    if (widget.subtitle case final s?) ...[
                      const SizedBox(height: 1),
                      Text(
                        s,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: widget.size * 0.075,
                          fontWeight: FontWeight.w600,
                          color: colors.text4,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FluidGaugePainter extends CustomPainter {
  _FluidGaugePainter({
    required this.fraction,
    required this.strokeWidth,
    required this.trackColor,
    required this.activeColor,
  });

  final double fraction;
  final double strokeWidth;
  final Color trackColor;
  final Color activeColor;

  // A 270° arc opening at the bottom. The gap gives the eye an unambiguous
  // start and end, which a full circle does not — on a closed ring, 2% and 98%
  // are drawn a few pixels apart.
  static const double _startRad = 135 * math.pi / 180;
  static const double _fullSweepRad = 270 * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final r = (size.shortestSide - strokeWidth) / 2;
    if (r <= 0) return;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: r,
    );

    canvas.drawArc(
      rect,
      _startRad,
      _fullSweepRad,
      false,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );

    if (fraction <= 0) return;
    final sweep = _fullSweepRad * fraction.clamp(0.0, 1.0);

    // A soft bloom under the arc. Cheap, and it is what stops a flat stroke
    // reading as a static progress bar.
    canvas.drawArc(
      rect,
      _startRad,
      sweep,
      false,
      Paint()
        ..color = activeColor.withValues(alpha: 0.24)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + 8
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Swept gradient so the arc gains intensity along its travel, which reads
    // as direction. Rotated to the arc's own start so the light end always sits
    // at the leading tip whatever the value.
    canvas.drawArc(
      rect,
      _startRad,
      sweep,
      false,
      Paint()
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: _fullSweepRad,
          transform: const GradientRotation(_startRad),
          colors: [
            activeColor.withValues(alpha: 0.55),
            activeColor,
          ],
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _FluidGaugePainter old) {
    return old.fraction != fraction ||
        old.strokeWidth != strokeWidth ||
        old.trackColor != trackColor ||
        old.activeColor != activeColor;
  }
}

/// A horizontal fill bar with the same tweening behaviour, for the film-space
/// hero where a bar reads better than a ring: it maps onto "how full is the
/// disk" directly, and it can carry a much larger number beside it.
class FluidBar extends StatelessWidget {
  const FluidBar({
    super.key,
    required this.fraction,
    this.color,
    this.height = 10,
    this.duration = const Duration(milliseconds: 700),
  });

  final double fraction;
  final Color? color;
  final double height;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final f = fraction.clamp(0.0, 1.0);
    final active = color ?? FluidGauge.rampFor(f * 100);

    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Stack(
        children: [
          Container(
            height: height,
            color: colors.text4.withValues(alpha: 0.14),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: f),
            duration: duration,
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => FractionallySizedBox(
              widthFactor: v,
              child: Container(
                height: height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(height),
                  gradient: LinearGradient(
                    colors: [active.withValues(alpha: 0.65), active],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: active.withValues(alpha: 0.45),
                      blurRadius: 8,
                      spreadRadius: -1,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}