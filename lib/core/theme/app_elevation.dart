import 'package:flutter/widgets.dart';

import 'app_colors.dart';

/// Shadow scale.
///
/// Elevation is expressed as a shadow recipe rather than a Material
/// `elevation:` number because both palettes paint their own `shadowColor`
/// (a hard black wash on AMOLED, a soft cool slate on white) and Material's
/// tonal elevation would fight the true-black background.
abstract final class AppElevation {
  /// Flat. Use for surfaces that rely on `border` alone.
  static const List<BoxShadow> none = <BoxShadow>[];

  /// Resting card.
  static List<BoxShadow> low(AppColors c) => <BoxShadow>[
        BoxShadow(
          color: c.shadowColor,
          blurRadius: 12,
          offset: const Offset(0, 2),
        ),
      ];

  /// Raised card, popover, floating pill.
  static List<BoxShadow> medium(AppColors c) => <BoxShadow>[
        BoxShadow(
          color: c.shadowColor,
          blurRadius: 20,
          offset: const Offset(0, 6),
        ),
      ];

  /// Bottom sheet, chooser panel, dialog.
  static List<BoxShadow> high(AppColors c) => <BoxShadow>[
        BoxShadow(
          color: c.shadowColor,
          blurRadius: 30,
          offset: const Offset(0, 8),
        ),
      ];

  /// A colored bloom under an active control, used for focus rings and the
  /// send button. [color] should be the active mode's color.
  static List<BoxShadow> glow(Color color, {double opacity = 0.35}) =>
      <BoxShadow>[
        BoxShadow(
          color: color.withValues(alpha: opacity),
          blurRadius: 18,
          spreadRadius: -2,
        ),
      ];
}
