import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Loads bundled Google Fonts before a widget test paints.
///
/// Asset fonts resolve asynchronously. In debug, TextPainter asserts if a
/// family finishes loading between layout and paint (`debugSize == size`).
/// Production does not hit that assert. Call this from tests that pump UI
/// using `GoogleFonts.*` — not from a global `flutter_test_config.dart`,
/// which would install `TestWidgetsFlutterBinding` and stub live HTTP.
Future<void> preloadBundledGoogleFonts() async {
  GoogleFonts.config.allowRuntimeFetching = false;
  GoogleFonts.plusJakartaSans();
  GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w500);
  GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600);
  GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700);
  GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800);
  GoogleFonts.plusJakartaSans(fontStyle: FontStyle.italic);
  GoogleFonts.plusJakartaSans(
    fontWeight: FontWeight.w500,
    fontStyle: FontStyle.italic,
  );
  GoogleFonts.jetBrainsMono();
  GoogleFonts.jetBrainsMono(fontWeight: FontWeight.w700);
  GoogleFonts.lora();
  GoogleFonts.lora(fontWeight: FontWeight.w700);
  GoogleFonts.lora(fontStyle: FontStyle.italic);
  GoogleFonts.dmSans();
  GoogleFonts.dmSans(fontWeight: FontWeight.w700);
  await GoogleFonts.pendingFonts();
}
