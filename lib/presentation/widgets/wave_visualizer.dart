import 'dart:math' as math;

import 'package:flutter/material.dart';

/// High-performance procedural wave visualizer driven by [CustomPainter].
///
/// Animates capsule-shaped bars with overlapping sine waves.
/// When [isActive] is true the bars dance; when false they settle
/// to a subtle breathing idle with a smooth amplitude transition.
class WaveVisualizer extends StatefulWidget {
  const WaveVisualizer({
    super.key,
    required this.isActive,
    this.color = const Color(0xFF0D59F2),
    this.height = 40,
    this.barCount = 7,
  });

  final bool isActive;
  final Color color;
  final double height;
  final int barCount;

  @override
  State<WaveVisualizer> createState() => _WaveVisualizerState();
}

class _WaveVisualizerState extends State<WaveVisualizer>
    with TickerProviderStateMixin {
  late final AnimationController _waveCtrl;
  late final AnimationController _ampCtrl;
  late final Animation<double> _ampCurve;

  @override
  void initState() {
    super.initState();

    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _ampCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );

    _ampCurve = CurvedAnimation(
      parent: _ampCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    if (widget.isActive) _ampCtrl.forward();
  }

  @override
  void didUpdateWidget(covariant WaveVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      widget.isActive ? _ampCtrl.forward() : _ampCtrl.reverse();
    }
  }

  @override
  void dispose() {
    _waveCtrl.dispose();
    _ampCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_waveCtrl, _ampCurve]),
      builder: (context, _) {
        return CustomPaint(
          size: Size(double.infinity, widget.height),
          painter: _WavePainter(
            phase: _waveCtrl.value,
            amplitude: _ampCurve.value,
            color: widget.color,
            barCount: widget.barCount,
          ),
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  const _WavePainter({
    required this.phase,
    required this.amplitude,
    required this.color,
    required this.barCount,
  });

  final double phase;
  final double amplitude;
  final Color color;
  final int barCount;

  static const double _barW = 3.5;
  static const double _gap = 3.5;

  @override
  void paint(Canvas canvas, Size size) {
    final totalW = barCount * _barW + (barCount - 1) * _gap;
    final startX = (size.width - totalW) / 2;
    final centerY = size.height / 2;
    final maxH = size.height * 0.9;
    final minH = size.height * 0.12;
    const pi2 = 2 * math.pi;

    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < barCount; i++) {
      // Three overlapping sine waves at different frequencies for organic motion
      final w1 = math.sin(phase * pi2 + i * 0.8);
      final w2 = math.sin(phase * pi2 * 1.4 + i * 1.2 + 0.6);
      final w3 = math.sin(phase * pi2 * 0.6 + i * 0.4 + 2.1);
      final combined = (w1 * 0.5 + w2 * 0.3 + w3 * 0.2 + 1.0) / 2.0;

      final activeH = minH + (maxH - minH) * combined;
      final idleH = minH +
          maxH *
              0.06 *
              (math.sin(phase * pi2 * 0.25 + i * 0.9) + 1.0) /
              2.0;

      final h = idleH + (activeH - idleH) * amplitude;
      final x = startX + i * (_barW + _gap);
      final opacity = (0.45 + 0.55 * (h / maxH)).clamp(0.0, 1.0);

      paint.color = color.withValues(alpha: opacity);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, centerY - h / 2, _barW, h),
          const Radius.circular(_barW / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.phase != phase || old.amplitude != amplitude;
}
