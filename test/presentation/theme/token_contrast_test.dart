// Locks the WCAG 2.x contrast contract on the text ramp and the mode /
// semantic tokens.
//
// `text3`/`text4`/`text5` are alpha-over-substrate, so the ratio depends on
// the palette's own background. `text4` is the critical one — it renders
// composer hints and inactive toggle labels, which must stay legible.

import 'dart:math' as math;

import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _channel(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

/// Alpha-composites [fg] over the opaque [bg] in sRGB, as the framework does.
Color _over(Color fg, Color bg) {
  final a = fg.a;
  return Color.from(
    alpha: 1,
    red: fg.r * a + bg.r * (1 - a),
    green: fg.g * a + bg.g * (1 - a),
    blue: fg.b * a + bg.b * (1 - a),
  );
}

double contrast(Color fg, Color bg) {
  final a = _luminance(_over(fg, bg));
  final b = _luminance(bg);
  final hi = math.max(a, b);
  final lo = math.min(a, b);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  const dark = AppColors.dark;
  const white = AppColors.white;

  group('text ramp contrast', () {
    test('text3 clears 7:1 in both palettes', () {
      expect(contrast(dark.text3, dark.bg), greaterThanOrEqualTo(7.0));
      expect(contrast(white.text3, white.bg), greaterThanOrEqualTo(7.0));
    });

    test('text4 clears 4.5:1 in both palettes', () {
      // Composer hints and inactive toggle labels live here.
      expect(contrast(dark.text4, dark.bg), greaterThanOrEqualTo(4.5));
      expect(contrast(white.text4, white.bg), greaterThanOrEqualTo(4.5));
    });

    test('text5 clears the 3:1 non-text threshold but is not text', () {
      expect(contrast(dark.text5, dark.bg), greaterThanOrEqualTo(3.0));
      expect(contrast(white.text5, white.bg), greaterThanOrEqualTo(3.0));
      // Deliberately below AA body text — decorative use only.
      expect(contrast(dark.text5, dark.bg), lessThan(4.5));
      expect(contrast(white.text5, white.bg), lessThan(4.5));
    });

    test('the ramp is monotonic', () {
      for (final p in const <AppColors>[dark, white]) {
        expect(contrast(p.text3, p.bg), greaterThan(contrast(p.text4, p.bg)));
        expect(contrast(p.text4, p.bg), greaterThan(contrast(p.text5, p.bg)));
      }
    });
  });

  group('mode + semantic tokens clear AA in their own palette', () {
    test('lite / deep / thinking', () {
      for (final p in const <AppColors>[dark, white]) {
        expect(contrast(p.modeLite, p.bg), greaterThanOrEqualTo(4.5));
        expect(contrast(p.modeDeep, p.bg), greaterThanOrEqualTo(4.5));
        expect(contrast(p.modeThinking, p.bg), greaterThanOrEqualTo(4.5));
      }
    });

    test('danger / warning / success / listening / accentText / xGrok', () {
      for (final p in const <AppColors>[dark, white]) {
        expect(contrast(p.danger, p.bg), greaterThanOrEqualTo(4.5));
        expect(contrast(p.warning, p.bg), greaterThanOrEqualTo(4.5));
        expect(contrast(p.success, p.bg), greaterThanOrEqualTo(4.5));
        expect(contrast(p.listening, p.bg), greaterThanOrEqualTo(4.5));
        expect(contrast(p.accentText, p.bg), greaterThanOrEqualTo(4.5));
        expect(contrast(p.providerXgrok, p.bg), greaterThanOrEqualTo(4.5));
      }
    });

    test('the CTA fill is still NOT safe as text on black', () {
      // This is exactly why `accentText` exists.
      expect(contrast(AppColors.accent, dark.bg), lessThan(4.5));
      expect(dark.accentText, isNot(AppColors.accent));
    });

    test('mode edges dual-pass the 3:1 non-text threshold', () {
      for (final edge in const <Color>[
        AppColors.modeLiteEdge,
        AppColors.modeDeepEdge,
        AppColors.modeThinkingEdge,
      ]) {
        expect(contrast(edge, dark.bg), greaterThanOrEqualTo(3.0));
        expect(contrast(edge, white.bg), greaterThanOrEqualTo(3.0));
      }
    });
  });

  group('provider identity does not rely on hue', () {
    test('Gemini is a gradient, xGrok is flat', () {
      expect(AppColors.geminiGradient.colors.length, 2);
      expect(
        AppColors.geminiGradientStart,
        isNot(AppColors.geminiGradientEnd),
      );
      // A single flat slate — there is no xGrok gradient to pair with it.
      expect(dark.providerXgrok, const Color(0xFF94A3B8));
      expect(white.providerXgrok, const Color(0xFF475569));
    });

    test('neither provider borrows the CTA blue', () {
      for (final c in <Color>[
        AppColors.geminiGradientStart,
        AppColors.geminiGradientEnd,
        dark.providerXgrok,
        white.providerXgrok,
      ]) {
        expect(c, isNot(AppColors.accent));
      }
    });
  });

  group('new fields survive copyWith / lerp', () {
    test('lerp interpolates every added field', () {
      final mid = dark.lerp(white, 0.5);
      for (final pair in <(Color, Color)>[
        (mid.modeLite, dark.modeLite),
        (mid.modeDeep, dark.modeDeep),
        (mid.modeThinking, dark.modeThinking),
        (mid.providerXgrok, dark.providerXgrok),
        (mid.accentText, dark.accentText),
        (mid.danger, dark.danger),
        (mid.warning, dark.warning),
        (mid.success, dark.success),
      ]) {
        expect(pair.$1, isNot(pair.$2));
      }
    });

    test('copyWith overrides only the named token', () {
      final c = dark.copyWith(modeDeep: const Color(0xFF123456));
      expect(c.modeDeep, const Color(0xFF123456));
      expect(c.modeLite, dark.modeLite);
      expect(c.danger, dark.danger);
      expect(c.text4, dark.text4);
    });
  });
}
