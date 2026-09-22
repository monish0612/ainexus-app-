import 'package:flutter/material.dart';

/// Motion tokens (Material 3).
///
/// Everything here resolves to a real Flutter SDK API — `Easing` (which lives
/// in the *material* library, not `animation`), `Curves`, and
/// `SpringDescription.withDampingRatio`. Nothing is re-derived by hand.
///
/// `AppConstants.animDuration` / `animDurationSlow` / `animationCurve` remain
/// in place for existing call sites; new work should use these instead.
abstract final class AppMotion {
  // ── Durations ─────────────────────────────────────────────────────────

  /// Press-down / release. Small, immediate, no easing drama.
  static const Duration microPress = Duration(milliseconds: 100);

  /// Hover, focus tint, icon swap.
  static const Duration microHover = Duration(milliseconds: 150);

  /// An element entering the screen.
  static const Duration standardEnter = Duration(milliseconds: 250);

  /// An element leaving. Exits are always faster than entrances.
  static const Duration standardExit = Duration(milliseconds: 200);

  /// A hero surface arriving: sheet, full-screen route, chooser panel.
  static const Duration emphasizedEnter = Duration(milliseconds: 500);

  /// The matching exit. Still fast — the user already decided.
  static const Duration emphasizedExit = Duration(milliseconds: 200);

  // ── Curves ────────────────────────────────────────────────────────────

  /// M3 standard: `Cubic(0.2, 0.0, 0.0, 1.0)`.
  static const Curve standard = Easing.standard;
  static const Curve standardDecelerate = Easing.standardDecelerate;
  static const Curve standardAccelerate = Easing.standardAccelerate;

  /// The M3 emphasized curve. A real `ThreePointCubic` in the SDK.
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;
  static const Curve emphasizedDecelerate = Easing.emphasizedDecelerate;
  static const Curve emphasizedAccelerate = Easing.emphasizedAccelerate;
}

/// Spring descriptions for gesture-driven and overshooting motion.
///
/// Drive these with
/// `controller.animateWith(SpringSimulation(spring, from, to, velocity))`.
/// `SpringDescription.withDampingRatio` already performs the
/// `damping = ratio * 2 * sqrt(mass * stiffness)` conversion, so pass the
/// ratio directly.
abstract final class AppSprings {
  /// Segmented pills, toggles, chips. Snappy with a hint of settle.
  static final SpringDescription fast = SpringDescription.withDampingRatio(
    mass: 1.0,
    stiffness: 800,
    ratio: 0.6,
  );

  /// Composer auto-grow, card settle. The everyday spring.
  static final SpringDescription standard = SpringDescription.withDampingRatio(
    mass: 1.0,
    stiffness: 380,
    ratio: 0.8,
  );

  /// Hero / full-screen transitions.
  static final SpringDescription slow = SpringDescription.withDampingRatio(
    mass: 1.0,
    stiffness: 200,
    ratio: 0.8,
  );

  /// Color and opacity. Critically damped — never overshoots, because an
  /// overshooting color is just a flicker.
  static final SpringDescription effects = SpringDescription.withDampingRatio(
    mass: 1.0,
    stiffness: 1600,
    ratio: 1.0,
  );

  /// Deliberately under-damped, for the send button's magnetic overshoot.
  static final SpringDescription magnetic = SpringDescription.withDampingRatio(
    mass: 1.0,
    stiffness: 420,
    ratio: 0.5,
  );
}
