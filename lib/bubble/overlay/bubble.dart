import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// The collapsed bubble: a small brand-blue disc with a white wand glyph, a
/// separation ring and a live cyan rim arc.
///
/// It sits over arbitrary third-party apps, so it carries its own contrast
/// rather than tinting the backdrop — a translucent glass blob disappeared
/// against light chat surfaces. White on [kBrandAccent] is ~7:1, and the
/// white ring plus the tight shadow keep the silhouette readable on both
/// black and white backgrounds.
///
/// Purely visual. Taps, drags and long-presses are handled natively by
/// `BubbleTouchContainer`, which moves the overlay window directly under the
/// finger — routing gestures through Dart added a round trip per frame and made
/// dragging feel rubbery.
class RephraseBubble extends StatefulWidget {
  const RephraseBubble({super.key, this.animate = true});

  /// Breath + rim sweep. Off while the overlay is hidden or the host is paused.
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
    upperBound: 1.03,
  );

  /// The cyan rim arc drifting once around the disc. Slow on purpose: this
  /// runs over other apps, so it must read as "alive", not as a spinner.
  late final AnimationController _rim = AnimationController(
    vsync: this,
    duration: kSheen,
  );

  /// Liquid pop-in: the bubble swells from a droplet with a soft overshoot.
  /// Replays each time the bubble is remounted for a new target.
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: kBubbleEntrance,
  );
  late final Animation<double> _entranceScale = CurvedAnimation(
    parent: _entrance,
    curve: Curves.easeOutBack,
  ).drive(Tween(begin: 0.55, end: 1.0));
  late final Animation<double> _entranceFade = CurvedAnimation(
    parent: _entrance,
    curve: const Interval(0, 0.6, curve: Curves.easeOut),
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
    final onDarkBackdrop =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;

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
                    painter: _BubbleSurface(
                      phase: still ? 0 : _rim.value,
                      still: still,
                      onDarkBackdrop: onDarkBackdrop,
                    ),
                    child: child,
                  ),
                  child: Center(
                    child: CustomPaint(
                      size: Size(size * 0.46, size * 0.46),
                      painter: _WandGlyph(),
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

/// Opaque disc + separation ring + live rim arc.
class _BubbleSurface extends CustomPainter {
  const _BubbleSurface({
    required this.phase,
    required this.still,
    required this.onDarkBackdrop,
  });

  /// 0–1 sweep position of the cyan rim arc.
  final double phase;
  final bool still;
  final bool onDarkBackdrop;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    // Leave room for the ring stroke and the shadow inside the window.
    final ring = size.width * 0.055;
    final radius = size.width / 2 - ring;
    final rect = Rect.fromCircle(center: centre, radius: radius);

    // Contact shadow. Kept tight — the overlay window is only 76dp, and a
    // large blur clips to a visible square plate behind the round bubble.
    canvas.drawCircle(
      centre.translate(0, size.height * 0.045),
      radius,
      Paint()
        ..color = kBubbleShadow
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.11),
    );

    // Opaque brand core with a top-left light source.
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kBrandAccentLift, kBrandAccent, kBrandAccentDeep],
          stops: [0.0, 0.52, 1.0],
        ).createShader(rect),
    );

    // Specular cap — a soft highlight across the upper third so the disc
    // reads as a physical object rather than a flat dot.
    canvas.save();
    canvas.clipPath(Path()..addOval(rect));
    canvas.drawOval(
      Rect.fromCenter(
        center: centre.translate(0, -radius * 0.72),
        width: radius * 2.1,
        height: radius * 1.05,
      ),
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFFFFF).withValues(alpha: 0.34),
            const Color(0xFFFFFFFF).withValues(alpha: 0.0),
          ],
        ).createShader(
          Rect.fromCenter(
            center: centre.translate(0, -radius * 0.72),
            width: radius * 2.1,
            height: radius * 1.05,
          ),
        ),
    );
    canvas.restore();

    // Separation ring. White carries the silhouette on dark backdrops; the
    // hairline adds an edge on light ones. Both are drawn so the bubble
    // never depends on knowing what is behind it.
    canvas.drawCircle(
      centre,
      radius + ring * 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ring
        ..color = onDarkBackdrop
            ? kBubbleRingLight
            : kBubbleRingLight.withValues(
                alpha: kBubbleRingLight.a * 0.82,
              ),
    );
    canvas.drawCircle(
      centre,
      radius + ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ring * 0.45
        ..color = kBubbleRingDark,
    );

    // Live cyan rim arc. Static at the 10-o'clock highlight under reduced
    // motion, so the same mark is present without the travel.
    const sweep = math.pi * 0.55;
    final start = still ? -math.pi * 0.95 : (phase * 2 * math.pi) - math.pi / 2;
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius - ring * 0.35),
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = ring * 0.85
        ..shader = SweepGradient(
          startAngle: start,
          endAngle: start + sweep,
          colors: [
            kBrandCyan.withValues(alpha: 0.0),
            kBrandCyan.withValues(alpha: 0.85),
            kBrandCyan.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.5, 1.0],
          transform: GradientRotation(start),
        ).createShader(Rect.fromCircle(center: centre, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(covariant _BubbleSurface old) =>
      old.phase != phase ||
      old.still != still ||
      old.onDarkBackdrop != onDarkBackdrop;
}

/// A wand-and-sparkle glyph — reads as "rewrite this". White on the brand
/// core (~7:1), with a cyan spark for the AI cue.
class _WandGlyph extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final wand = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..strokeWidth = s.width * 0.155
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(s.width * 0.16, s.height * 0.84),
      Offset(s.width * 0.64, s.height * 0.36),
      wand,
    );

    _star(
      canvas,
      Offset(s.width * 0.79, s.height * 0.21),
      s.width * 0.21,
      const Color(0xFFFFFFFF),
    );
    _star(
      canvas,
      Offset(s.width * 0.26, s.height * 0.27),
      s.width * 0.11,
      kBrandCyan,
    );
  }

  /// Four-point sparkle with concave sides — the 2026 "AI" mark, not a plus.
  void _star(Canvas canvas, Offset c, double r, Color color) {
    final waist = r * 0.30;
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + waist * 0.4, c.dy - waist * 0.4, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + waist * 0.4, c.dy + waist * 0.4, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - waist * 0.4, c.dy + waist * 0.4, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - waist * 0.4, c.dy - waist * 0.4, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
