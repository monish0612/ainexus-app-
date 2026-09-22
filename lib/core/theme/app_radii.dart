import 'package:flutter/widgets.dart';

/// Corner-radius scale.
///
/// Before this existed, radii were inline literals (8/12/14/16/20/22/24/999)
/// chosen per call site. The scale below covers every value already in use;
/// `card` and `sheet` are the two that most screens should reach for.
abstract final class AppRadii {
  /// Chips, badges, tiny stamps.
  static const double xs = 8;

  /// Inputs, small buttons, model-id chips.
  static const double sm = 12;

  /// Inline option tiles, segmented-control children.
  static const double md = 14;

  /// The default card corner.
  static const double card = 16;

  /// Grouped surfaces, settings blocks, toggles.
  static const double lg = 20;

  /// Bottom sheets, chooser panels.
  static const double sheet = 24;

  /// Hero surfaces and full-bleed dialogs.
  static const double xl = 28;

  /// Fully rounded. Matches the `999` literal already in the codebase.
  static const double pill = 999;

  // ── Provider identity ────────────────────────────────────────────────
  //
  // Gemini reads round, xGrok reads angular. Paired with the flat-vs-gradient
  // fill in `AppColors`, the two stay distinguishable in grayscale.
  static const double providerGemini = pill;
  static const double providerXgrok = 4;

  static const BorderRadius brXs = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius brSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius brMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius brCard = BorderRadius.all(Radius.circular(card));
  static const BorderRadius brLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius brSheet = BorderRadius.all(Radius.circular(sheet));
  static const BorderRadius brXl = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius brPill = BorderRadius.all(Radius.circular(pill));

  /// Top-only rounding for sheets docked to the bottom edge.
  static const BorderRadius brSheetTop =
      BorderRadius.vertical(top: Radius.circular(sheet));
}
