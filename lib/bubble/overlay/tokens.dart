import 'package:flutter/widgets.dart';

/// Design tokens for the floating rephrase overlay.
///
/// The collapsed bubble is liquid glass. The expanded panel is solid AMOLED
/// black — translucent glass behind reading text made the panel unreadable
/// over busy chat backgrounds (see Telegram Saved Messages).

// ── Sizing: small and responsive across phones and tablets ──────────────────

/// Scales with the shortest screen side so tablets don't get a giant bubble,
/// then clamps to a small range.
double bubbleSize(BuildContext context) {
  final shortest = MediaQuery.sizeOf(context).shortestSide;
  return (shortest * 0.13).clamp(44.0, 56.0);
}

const double kPanelMaxWidth = 308;
const double kPanelRadius = 22;
const double kBubbleRadius = 999;
const double kCopyButtonSize = 28;

const EdgeInsets kPanelPadding = EdgeInsets.fromLTRB(12, 10, 12, 12);

/// Space kept between the panel and the window edge so the soft drop shadow
/// isn't clipped by the overlay window.
const double kPanelShadowMargin = 10;

/// Upper bound on system font scaling inside the overlay. A floating panel has
/// to stay compact, so huge accessibility scales are capped rather than allowed
/// to push the layout past the window; body text still grows noticeably.
const double kMaxTextScale = 1.3;

/// The effective linear text-scale factor, already clamped.
double textScale(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1).clamp(1.0, kMaxTextScale);

// ── Liquid-glass palette (collapsed bubble only) ────────────────────────────

const Color kGlassTintLight = Color(0x3D101828);
const Color kGlassTintDark = Color(0x59060B14);
const Color kGlassStrokeTop = Color(0x66FFFFFF);
const Color kGlassStrokeBot = Color(0x14FFFFFF);
const Color kGlassShadow = Color(0x59000000);

Color glassTint(Brightness brightness) =>
    brightness == Brightness.dark ? kGlassTintDark : kGlassTintLight;

// ── AMOLED panel palette (expanded pop-up) ──────────────────────────────────

/// True black — every OLED pixel off. Never translucent.
const Color kPanelBg = Color(0xFF000000);

/// Slightly lifted surface for the result card and tone field.
const Color kPanelSurface = Color(0xFF121212);

/// Hairline borders that read on black without looking washed out.
const Color kPanelStroke = Color(0xFF2A2A2A);

/// Soft elevation so the opaque panel lifts off the app underneath.
const Color kPanelShadow = Color(0x99000000);

const Color kAccent = Color(0xFF6EA8FF);
const Color kAccent2 = Color(0xFFB98CFF);
const Color kTextPrimary = Color(0xFFF4F6FF);
const Color kTextMuted = Color(0x99F4F6FF);
const Color kDanger = Color(0xFFFF6E8A);

/// Idle chip fill — opaque enough that chat text never bleeds through.
const Color kChipIdle = Color(0xFF1A1A1A);

// ── Motion ──────────────────────────────────────────────────────────────────

/// Bubble → panel morph: quick in, quicker out — the panel must feel instant.
const Duration kMorphIn = Duration(milliseconds: 220);
const Duration kMorphOut = Duration(milliseconds: 140);

/// Liquid entrance when the bubble first appears after a typing pause.
const Duration kBubbleEntrance = Duration(milliseconds: 280);

/// Result text swap and the Use-button morph (label → spinner → check).
const Duration kResultSwap = Duration(milliseconds: 180);

/// How long the green check shows before the panel closes itself.
const Duration kAcceptFlash = Duration(milliseconds: 380);

const Duration kBreath = Duration(milliseconds: 2400);
const Duration kSheen = Duration(milliseconds: 5200);

bool reducedMotion(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;
