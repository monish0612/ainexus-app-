import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

abstract final class AppTheme {
  /// Type scale.
  ///
  /// The roles previously carried weights but no sizes, so every role fell
  /// back to the M3 default (bodyMedium 14, titleLarge 22, displayLarge 57 …)
  /// — far too loose for a 390pt phone surface, which is why hundreds of call
  /// sites bypass the theme with an inline `GoogleFonts.plusJakartaSans(
  /// fontSize: …)`. These sizes are tuned to what the app actually renders, so
  /// those call sites can start collapsing into `Theme.of(context).textTheme`.
  static TextTheme _textTheme(Color textColor) {
    return GoogleFonts.plusJakartaSansTextTheme(
      TextTheme(
        // Display — currency hero, onboarding numerals.
        displayLarge: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w900,
          fontSize: 40,
          height: 1.08,
          letterSpacing: -1.2,
        ),
        displayMedium: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w800,
          fontSize: 34,
          height: 1.1,
          letterSpacing: -0.9,
        ),
        displaySmall: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w700,
          fontSize: 28,
          height: 1.14,
          letterSpacing: -0.6,
        ),
        // Headline — screen titles, section heroes.
        headlineLarge: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w800,
          fontSize: 24,
          height: 1.2,
          letterSpacing: -0.6,
        ),
        headlineMedium: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w700,
          fontSize: 21,
          height: 1.22,
          letterSpacing: -0.4,
        ),
        headlineSmall: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w700,
          fontSize: 18,
          height: 1.26,
          letterSpacing: -0.3,
        ),
        // Title — card headers, sheet titles, list leads.
        titleLarge: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w700,
          fontSize: 17,
          height: 1.3,
          letterSpacing: -0.3,
        ),
        titleMedium: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w600,
          fontSize: 15,
          height: 1.33,
          letterSpacing: -0.15,
        ),
        titleSmall: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w600,
          fontSize: 13.5,
          height: 1.36,
        ),
        // Body — prose, answers, descriptions.
        bodyLarge: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w400,
          fontSize: 15,
          height: 1.5,
        ),
        bodyMedium: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w400,
          fontSize: 13.5,
          height: 1.5,
        ),
        bodySmall: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w400,
          fontSize: 12,
          height: 1.45,
        ),
        // Label — buttons, chips, overline captions.
        labelLarge: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w700,
          fontSize: 13,
          height: 1.25,
        ),
        labelMedium: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w600,
          fontSize: 11.5,
          height: 1.25,
        ),
        labelSmall: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w500,
          fontSize: 10,
          height: 1.3,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  static final ThemeData darkTheme = _buildDark();

  static ThemeData _buildDark() {
    const colors = AppColors.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: colors.bg,
      colorScheme: ColorScheme.dark(
        surface: colors.bg,
        primary: AppColors.accent,
        secondary: AppColors.accentCyan,
        tertiary: colors.modeDeep,
        error: colors.danger,
        onPrimary: Colors.white,
        onError: Colors.white,
        onSurface: colors.text,
        onSurfaceVariant: colors.text2,
        outline: colors.border,
        outlineVariant: colors.border2,
        shadow: colors.shadowColor,
        scrim: colors.scrim,
      ),
      textTheme: _textTheme(colors.text),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.headerBg,
        foregroundColor: colors.text,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      dividerTheme: DividerThemeData(color: colors.border, thickness: 1),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.accent,
        selectionHandleColor: AppColors.accent,
      ),
      extensions: const <ThemeExtension<dynamic>>[colors],
    );
  }

  static final ThemeData whiteTheme = _buildWhite();

  static ThemeData _buildWhite() {
    const colors = AppColors.white;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: colors.bg,
      colorScheme: ColorScheme.light(
        surface: colors.bg,
        primary: AppColors.accent,
        secondary: AppColors.accentCyan,
        tertiary: colors.modeDeep,
        error: colors.danger,
        onPrimary: Colors.white,
        onError: Colors.white,
        onSurface: colors.text,
        onSurfaceVariant: colors.text2,
        outline: colors.border,
        outlineVariant: colors.border2,
        shadow: colors.shadowColor,
        scrim: colors.scrim,
      ),
      textTheme: _textTheme(colors.text),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.headerBg,
        foregroundColor: colors.text,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      dividerTheme: DividerThemeData(color: colors.border, thickness: 1),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.accent,
        selectionHandleColor: AppColors.accent,
      ),
      extensions: const <ThemeExtension<dynamic>>[colors],
    );
  }
}
