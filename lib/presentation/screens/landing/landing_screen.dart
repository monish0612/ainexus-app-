import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';

/// Onboarding / welcome screen — follows the selected app theme.
class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _entranceController;

  late final Animation<double> _pulseScale;
  late final Animation<double> _orbEnter;
  late final Animation<double> _aiFade;
  late final Animation<double> _nexusFade;
  late final Animation<double> _taglineFade;
  late final Animation<Offset> _buttonSlide;
  late final Animation<double> _buttonFade;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _pulseScale = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..forward();

    _orbEnter = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 0.35, curve: Curves.easeOutCubic),
    );
    _aiFade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.12, 0.42, curve: Curves.easeOut),
    );
    _nexusFade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.22, 0.52, curve: Curves.easeOut),
    );
    _taglineFade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.38, 0.72, curve: Curves.easeOut),
    );
    _buttonSlide = Tween<Offset>(
      begin: const Offset(0, 0.35),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.5, 1.0, curve: Curves.easeOutCubic),
      ),
    );
    _buttonFade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.55, 0.95, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final textOnBlack = colors.text;
    final taglineColor = colors.text2;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: colors.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _CornerOrbsLayer(),
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),
                FadeTransition(
                  opacity: _orbEnter,
                  child: ScaleTransition(
                    scale: _pulseScale,
                    child: const _HeroOrb(),
                  ),
                ),
                const SizedBox(height: 36),
                FadeTransition(
                  opacity: _aiFade,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ShaderMask(
                        blendMode: BlendMode.srcIn,
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [
                            AppColors.accent,
                            AppColors.accentCyan,
                          ],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ).createShader(bounds),
                        child: Text(
                          'NEXUS',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 44,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      FadeTransition(
                        opacity: _nexusFade,
                        child: Text(
                          'AI',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 44,
                            fontWeight: FontWeight.w700,
                            color: textOnBlack,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                FadeTransition(
                  opacity: _taglineFade,
                  child: Text(
                    'Your Next-Gen AI Companion',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: taglineColor,
                      height: 1.35,
                    ),
                  ),
                ),
                const Spacer(flex: 3),
                Padding(
                  padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + bottomInset),
                  child: SlideTransition(
                    position: _buttonSlide,
                    child: FadeTransition(
                      opacity: _buttonFade,
                      child: SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: Material(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            onTap: () => context.go('/'),
                            borderRadius: BorderRadius.circular(14),
                            child: Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Get Started',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(
                                    LucideIcons.arrowRight,
                                    size: 20,
                                    color: Colors.white,
                                  ),
                                ],
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
        ],
      ),
    );
  }
}

class _CornerOrbsLayer extends StatelessWidget {
  const _CornerOrbsLayer();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: -100,
            left: -80,
            child: _BlurOrb(
              diameter: 280,
              colors: [
                AppColors.accent.withValues(alpha: 0.14),
                AppColors.accentCyan.withValues(alpha: 0.06),
                Colors.transparent,
              ],
            ),
          ),
          Positioned(
            top: 40,
            right: -100,
            child: _BlurOrb(
              diameter: 260,
              colors: [
                AppColors.accentCyan.withValues(alpha: 0.12),
                AppColors.accent.withValues(alpha: 0.05),
                Colors.transparent,
              ],
            ),
          ),
          Positioned(
            bottom: 120,
            left: -60,
            child: _BlurOrb(
              diameter: 220,
              colors: [
                AppColors.accent.withValues(alpha: 0.08),
                Colors.transparent,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BlurOrb extends StatelessWidget {
  const _BlurOrb({
    required this.diameter,
    required this.colors,
  });

  final double diameter;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 48, sigmaY: 48),
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: colors,
            stops: colors.length == 3 ? const [0.0, 0.45, 1.0] : const [0.0, 1.0],
          ),
        ),
      ),
    );
  }
}

/// 128px pulsing core with [SweepGradient] ring (accent → cyan).
class _HeroOrb extends StatelessWidget {
  const _HeroOrb();

  static const double _size = 128;
  static const double _ringWidth = 3;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(_size, _size),
            painter: _SweepRingPainter(
              strokeWidth: _ringWidth,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(_ringWidth + 2),
            child: Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Color(0xFF1A4A9E),
                    AppColors.accent,
                    AppColors.accentCyan,
                  ],
                  stops: [0.0, 0.55, 1.0],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x660D59F2),
                    blurRadius: 32,
                    spreadRadius: 0,
                  ),
                  BoxShadow(
                    color: Color(0x4422D3EE),
                    blurRadius: 24,
                    spreadRadius: -4,
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  LucideIcons.sparkles,
                  size: 40,
                  color: Color(0xE6FFFFFF),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SweepRingPainter extends CustomPainter {
  _SweepRingPainter({required this.strokeWidth});

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
        startAngle: 0,
        endAngle: 6.2831853,
        transform: GradientRotation(-1.2),
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _SweepRingPainter oldDelegate) =>
      oldDelegate.strokeWidth != strokeWidth;
}
