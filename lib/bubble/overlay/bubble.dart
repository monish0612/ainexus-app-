import 'package:flutter/widgets.dart';

import 'glass.dart';
import 'tokens.dart';

/// The collapsed liquid-glass bubble: small, round, breathing, with a wand
/// glyph.
///
/// Purely visual. Taps, drags and long-presses are handled natively by
/// `BubbleTouchContainer`, which moves the overlay window directly under the
/// finger — routing gestures through Dart added a round trip per frame and made
/// dragging feel rubbery.
class RephraseBubble extends StatefulWidget {
  const RephraseBubble({super.key});

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
    _breath.repeat(reverse: true);
    _entrance.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reducedMotion(context)) {
      _breath.stop();
      _entrance.value = 1;
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = bubbleSize(context);
    final still = reducedMotion(context);

    return Center(
      child: FadeTransition(
        opacity: _entranceFade,
        child: ScaleTransition(
          scale: _entranceScale,
          child: ScaleTransition(
            scale: still ? const AlwaysStoppedAnimation(1.0) : _breath,
            child: SizedBox(
              width: size,
              height: size,
              child: GlassContainer(
                radius: kBubbleRadius,
                padding: EdgeInsets.zero,
                // Large shadows clip to the rectangular overlay window and
                // paint an ugly square plate behind the round bubble.
                showShadow: false,
                child: Center(
                  child: CustomPaint(
                    size: Size(size * 0.44, size * 0.44),
                    painter: _WandGlyph(),
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

/// A small wand-and-sparkle glyph — reads as "rewrite this".
class _WandGlyph extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final paint = Paint()
      ..color = kAccent
      ..strokeWidth = s.width * 0.12
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(s.width * 0.18, s.height * 0.82),
      Offset(s.width * 0.68, s.height * 0.32),
      paint,
    );
    final centre = Offset(s.width * 0.78, s.height * 0.22);
    final r = s.width * 0.16;
    canvas.drawLine(
      Offset(centre.dx - r, centre.dy),
      Offset(centre.dx + r, centre.dy),
      paint,
    );
    canvas.drawLine(
      Offset(centre.dx, centre.dy - r),
      Offset(centre.dx, centre.dy + r),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
