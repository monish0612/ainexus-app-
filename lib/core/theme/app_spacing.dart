import 'package:flutter/widgets.dart';

/// 4pt spacing scale, with the two half-steps (2, 6) the existing layouts
/// already depend on.
abstract final class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double s = 6;
  static const double sm = 8;
  static const double md = 12;

  /// The default gutter: section padding, card padding, sheet insets.
  static const double lg = 16;

  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 40;

  /// Minimum interactive target. Matches the 48dp nav buttons.
  static const double tapTarget = 48;

  // Vertical gaps — `const` so they cost nothing in a children list.
  static const Widget gapXxs = SizedBox(height: xxs);
  static const Widget gapXs = SizedBox(height: xs);
  static const Widget gapS = SizedBox(height: s);
  static const Widget gapSm = SizedBox(height: sm);
  static const Widget gapMd = SizedBox(height: md);
  static const Widget gapLg = SizedBox(height: lg);
  static const Widget gapXl = SizedBox(height: xl);
  static const Widget gapXxl = SizedBox(height: xxl);

  // Horizontal gaps.
  static const Widget hGapXs = SizedBox(width: xs);
  static const Widget hGapS = SizedBox(width: s);
  static const Widget hGapSm = SizedBox(width: sm);
  static const Widget hGapMd = SizedBox(width: md);
  static const Widget hGapLg = SizedBox(width: lg);

  /// Standard horizontal page gutter.
  static const EdgeInsets pageH = EdgeInsets.symmetric(horizontal: lg);

  /// Standard card padding.
  static const EdgeInsets card = EdgeInsets.all(lg);

  /// Settings-style section gutter (the sheet already uses 18).
  static const EdgeInsets sectionH = EdgeInsets.symmetric(horizontal: 18);
}
