import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/reduced_motion.dart';

/// Live brand mark used on Login / Landing.
///
/// Matches the launcher: charcoal plate `#0B0B0D` + the provided payment
/// glyph, with a slow rotating accent ring and a soft glow. The PNG is
/// already padded for adaptive-icon safe-zone; we scale it slightly so the
/// glyph fills the in-app circle without touching the original asset.
class NexusBrandMark extends StatefulWidget {
  const NexusBrandMark({super.key, this.size = 96});

  static const assetPath = 'assets/icon/ic_foreground.png';
  static const plateColor = Color(0xFF0B0B0D);

  final double size;

  @override
  State<NexusBrandMark> createState() => _NexusBrandMarkState();
}

class _NexusBrandMarkState extends State<NexusBrandMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reducedMotion(context)) {
      _spin.stop();
      _spin.value = 0;
    } else if (!_spin.isAnimating) {
      _spin.repeat();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    assert(size > 0, 'NexusBrandMark size must be positive');
    final ring = (size * 0.023).clamp(2.0, 3.5).toDouble();
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 2.0;
    final cachePx = (size * 1.28 * dpr).round().clamp(64, 512);

    return Semantics(
      label: 'Nexus AI',
      image: true,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.40),
                    blurRadius: size * 0.30,
                  ),
                  BoxShadow(
                    color: AppColors.accentCyan.withValues(alpha: 0.22),
                    blurRadius: size * 0.18,
                    spreadRadius: -size * 0.04,
                  ),
                ],
              ),
              child: SizedBox(width: size * 0.72, height: size * 0.72),
            ),
            RotationTransition(
              turns: _spin,
              child: RepaintBoundary(
                child: CustomPaint(
                  size: Size.square(size),
                  painter: _BrandRingPainter(strokeWidth: ring),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(ring + 2),
              child: ClipOval(
                child: ColoredBox(
                  color: NexusBrandMark.plateColor,
                  child: Transform.scale(
                    scale: 1.28,
                    child: Image.asset(
                      NexusBrandMark.assetPath,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                      gaplessPlayback: true,
                      cacheWidth: cachePx,
                      cacheHeight: cachePx,
                      errorBuilder: (_, __, ___) => const ColoredBox(
                        color: NexusBrandMark.plateColor,
                        child: Center(
                          child: Text(
                            r'$',
                            style: TextStyle(
                              color: AppColors.accent,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandRingPainter extends CustomPainter {
  const _BrandRingPainter({required this.strokeWidth});

  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..shader = const SweepGradient(
        colors: [
          AppColors.accent,
          AppColors.accentCyan,
          Color(0xFF38BDF8),
          AppColors.accent,
        ],
        stops: [0.0, 0.35, 0.65, 1.0],
        transform: GradientRotation(-1.2),
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _BrandRingPainter oldDelegate) =>
      oldDelegate.strokeWidth != strokeWidth;
}
