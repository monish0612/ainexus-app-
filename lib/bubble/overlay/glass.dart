import 'dart:ui';

import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// A reusable liquid-glass surface: a soft top-light fill, a 1px refracted
/// gradient edge, a soft shadow, and a slow moving sheen.
///
/// [blur] is off by default, and deliberately so. A BackdropFilter can only
/// frost what Flutter itself has already painted behind it; the app underneath
/// lives in another window and is frosted natively instead (Android 12+). Inside
/// this overlay the backdrop is transparent, so a filter here would cost a
/// saveLayer and a gaussian blur every frame and show nothing. Pass a blur only
/// when this surface sits over real Flutter content.
class GlassContainer extends StatefulWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.radius = kPanelRadius,
    this.blur = 0,
    this.padding = const EdgeInsets.all(14),
    this.animateSheen = true,
    this.showShadow = true,
  });

  final Widget child;
  final double radius;
  final double blur;
  final EdgeInsets padding;
  final bool animateSheen;

  /// Soft drop shadow. Off for the collapsed bubble — the native overlay
  /// window is only ~76dp, so a large blur clips into a visible square plate.
  final bool showShadow;

  @override
  State<GlassContainer> createState() => _GlassContainerState();
}

class _GlassContainerState extends State<GlassContainer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sheen =
      AnimationController(vsync: this, duration: kSheen);

  @override
  void initState() {
    super.initState();
    if (widget.animateSheen) _sheen.repeat();
  }

  @override
  void dispose() {
    _sheen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tint = glassTint(MediaQuery.platformBrightnessOf(context));
    final still = reducedMotion(context) || !widget.animateSheen;
    if (still && _sheen.isAnimating) _sheen.stop();
    final radius = BorderRadius.circular(widget.radius);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: widget.showShadow
            ? const [
                BoxShadow(
                  color: kGlassShadow,
                  blurRadius: 30,
                  offset: Offset(0, 12),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: _frost(
          CustomPaint(
            foregroundPainter: _EdgePainter(widget.radius),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    tint,
                    tint.withValues(alpha: (tint.a * 0.72).clamp(0.0, 1.0)),
                  ],
                ),
              ),
              child: Stack(
                children: [
                  if (!still)
                    Positioned.fill(
                      child: IgnorePointer(
                        // Its own layer, so the drifting highlight repaints
                        // without dirtying the content painted over it.
                        child: RepaintBoundary(
                          child: AnimatedBuilder(
                            animation: _sheen,
                            builder: (_, __) => CustomPaint(
                              painter: _SheenPainter(_sheen.value, widget.radius),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Padding(padding: widget.padding, child: widget.child),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _frost(Widget child) {
    if (widget.blur <= 0) return child;
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: widget.blur, sigmaY: widget.blur),
      child: child,
    );
  }
}

/// 1px refracted edge: bright top-left fading to faint bottom-right.
class _EdgePainter extends CustomPainter {
  _EdgePainter(this.radius);

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [kGlassStrokeTop, kGlassStrokeBot],
      ).createShader(Offset.zero & size);
    canvas.drawRRect(rrect.deflate(0.5), paint);
  }

  @override
  bool shouldRepaint(covariant _EdgePainter old) => old.radius != radius;
}

/// A soft diagonal highlight drifting across the surface — the "living" glass.
class _SheenPainter extends CustomPainter {
  _SheenPainter(this.t, this.radius);

  final double t;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final dx = (t * 2 - 0.5) * size.width;
    final rect = Rect.fromLTWH(
      dx - size.width * 0.4,
      -size.height * 0.2,
      size.width * 0.8,
      size.height * 1.4,
    );
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          kAccent.withValues(alpha: 0.0),
          kAccent.withValues(alpha: 0.10),
          kAccent2.withValues(alpha: 0.12),
          kAccent2.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.45, 0.6, 1.0],
      ).createShader(rect);
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
    );
    canvas.drawRect(rect, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SheenPainter old) => old.t != t;
}
