import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// The collapsed bubble: a milky liquid-glass bead with a dark wand.
///
/// It floats over other apps, and those apps can be white or black, so the
/// bead carries its own edge: a bright rim, a dark hairline, and a tight
/// shadow. The fill stays translucent enough to read as glass, and dense
/// enough that it does not vanish on a light chat.
///
/// Purely visual. Taps, drags and long-presses are handled natively by
/// `BubbleTouchContainer`, which moves the overlay window directly under the
/// finger — routing gestures through Dart added a round trip per frame and made
/// dragging feel rubbery.
class RephraseBubble extends StatefulWidget {
  const RephraseBubble({super.key, this.animate = true});

  /// Breath + rim glint. Off while the overlay is hidden or the host is paused.
  final bool animate;

  @override
  State<RephraseBubble> createState() => _RephraseBubbleState();
}

class _RephraseBubbleState extends State<RephraseBubble>
    with TickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: kBreath,
    lowerBound: 1.0,
    upperBound: 1.025,
  );

  /// A highlight walking the rim. Slow so it reads as glass catching light,
  /// not as a spinner.
  late final AnimationController _rim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3400),
  );

  /// A short pop, not a slow swell. Replays whenever the bubble is remounted
  /// for a new field.
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );
  late final Animation<double> _entranceScale = CurvedAnimation(
    parent: _entrance,
    curve: Curves.easeOutBack,
  ).drive(Tween(begin: 0.78, end: 1.0));
  late final Animation<double> _entranceFade = CurvedAnimation(
    parent: _entrance,
    curve: const Interval(0, 0.45, curve: Curves.easeOut),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _breath.repeat(reverse: true);
      _rim.repeat();
    }
    _entrance.forward();
  }

  @override
  void didUpdateWidget(RephraseBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTickers();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTickers();
  }

  void _syncTickers() {
    final still = reducedMotion(context) || !widget.animate;
    if (still) {
      _breath.stop();
      _rim.stop();
      _entrance.value = 1;
    } else {
      if (!_breath.isAnimating) _breath.repeat(reverse: true);
      if (!_rim.isAnimating) _rim.repeat();
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    _rim.dispose();
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = bubbleSize(context);
    final still = reducedMotion(context) || !widget.animate;

    return Center(
      child: FadeTransition(
        opacity: _entranceFade,
        child: ScaleTransition(
          scale: _entranceScale,
          child: ScaleTransition(
            scale: still ? const AlwaysStoppedAnimation(1.0) : _breath,
            child: RepaintBoundary(
              child: SizedBox(
                width: size,
                height: size,
                child: AnimatedBuilder(
                  animation: _rim,
                  builder: (context, child) => CustomPaint(
                    painter: _GlassOrb(phase: still ? 0.08 : _rim.value),
                    child: child,
                  ),
                  child: Center(
                    child: CustomPaint(
                      size: Size(size * 0.50, size * 0.50),
                      painter: const _WandGlyph(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Frosted bead. Inset so the contact shadow stays inside the 76dp overlay
/// window instead of clipping into a square plate.
class _GlassOrb extends CustomPainter {
  const _GlassOrb({required this.phase});

  /// 0–1 position of the rim glint.
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final margin = size.width * 0.08;
    final radius = size.width / 2 - margin;
    final disc = Rect.fromCircle(center: centre, radius: radius);

    canvas.drawCircle(
      centre.translate(0, size.width * 0.035),
      radius * 0.94,
      Paint()
        ..color = kBubbleShadow
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.055),
    );

    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xF2FFFFFF),
            Color(0xD4E4ECF8),
            Color(0xC2C5D4E8),
          ],
          stops: [0.0, 0.48, 1.0],
        ).createShader(disc),
    );

    canvas.save();
    canvas.clipPath(Path()..addOval(disc));

    // Cool shade along the bottom so the bead has volume.
    canvas.drawOval(
      Rect.fromCenter(
        center: centre.translate(radius * 0.15, radius * 0.72),
        width: radius * 2.4,
        height: radius * 1.15,
      ),
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF6EA8FF).withValues(alpha: 0.28),
            const Color(0xFFB98CFF).withValues(alpha: 0.0),
          ],
        ).createShader(
          Rect.fromCenter(
            center: centre.translate(radius * 0.15, radius * 0.72),
            width: radius * 2.4,
            height: radius * 1.15,
          ),
        ),
    );

    // Specular cap — the top of the glass catching a light.
    canvas.drawOval(
      Rect.fromCenter(
        center: centre.translate(-radius * 0.12, -radius * 0.46),
        width: radius * 1.45,
        height: radius * 0.78,
      ),
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFFFFF).withValues(alpha: 0.95),
            const Color(0xFFFFFFFF).withValues(alpha: 0.0),
          ],
        ).createShader(
          Rect.fromCenter(
            center: centre.translate(-radius * 0.12, -radius * 0.46),
            width: radius * 1.45,
            height: radius * 0.78,
          ),
        ),
    );
    canvas.restore();

    final ring = size.width * 0.028;
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ring
        ..color = const Color(0x66101828),
    );
    canvas.drawCircle(
      centre,
      radius - ring * 0.35,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ring * 0.7
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xF5FFFFFF),
            Color(0x88FFFFFF),
            Color(0x22FFFFFF),
          ],
          stops: [0.0, 0.42, 1.0],
        ).createShader(disc),
    );

    const sweep = math.pi * 0.38;
    final start = (phase * 2 * math.pi) - math.pi * 0.85;
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius - ring * 0.15),
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = ring * 1.35
        ..shader = const LinearGradient(
          colors: [Color(0xFF7DD3FC), Color(0xF2FFFFFF), Color(0xFFC4B5FD)],
        ).createShader(disc),
    );
  }

  @override
  bool shouldRepaint(covariant _GlassOrb old) => old.phase != phase;
}

/// Dark wand and two sparkles. The mark has to stay readable on the bright
/// glass cap, so it is ink, not white.
class _WandGlyph extends CustomPainter {
  const _WandGlyph();

  @override
  void paint(Canvas canvas, Size s) {
    final wand = Paint()
      ..color = const Color(0xFF102044)
      ..strokeWidth = s.width * 0.10
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(s.width * 0.14, s.height * 0.86),
      Offset(s.width * 0.58, s.height * 0.42),
      wand,
    );

    _star(
      canvas,
      Offset(s.width * 0.76, s.height * 0.24),
      s.width * 0.24,
      const Color(0xFF102044),
    );
    _star(
      canvas,
      Offset(s.width * 0.34, s.height * 0.28),
      s.width * 0.12,
      const Color(0xFF0891B2),
    );
  }

  void _star(Canvas canvas, Offset c, double r, Color color) {
    final waist = r * 0.22;
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + waist * 0.2, c.dy - waist * 0.2, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + waist * 0.2, c.dy + waist * 0.2, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - waist * 0.2, c.dy + waist * 0.2, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - waist * 0.2, c.dy - waist * 0.2, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
