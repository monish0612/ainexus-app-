import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

abstract final class AppTheme {
  static TextTheme _textTheme(Color textColor) {
    return GoogleFonts.plusJakartaSansTextTheme(
      TextTheme(
        displayLarge: TextStyle(color: textColor, fontWeight: FontWeight.w900),
        displayMedium: TextStyle(color: textColor, fontWeight: FontWeight.w800),
        displaySmall: TextStyle(color: textColor, fontWeight: FontWeight.w700),
        headlineLarge: TextStyle(color: textColor, fontWeight: FontWeight.w800),
        headlineMedium: TextStyle(color: textColor, fontWeight: FontWeight.w700),
        headlineSmall: TextStyle(color: textColor, fontWeight: FontWeight.w700),
        titleLarge: TextStyle(color: textColor, fontWeight: FontWeight.w700),
        titleMedium: TextStyle(color: textColor, fontWeight: FontWeight.w600),
        titleSmall: TextStyle(color: textColor, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: textColor, fontWeight: FontWeight.w400),
        bodyMedium: TextStyle(color: textColor, fontWeight: FontWeight.w400),
        bodySmall: TextStyle(color: textColor, fontWeight: FontWeight.w400),
        labelLarge: TextStyle(color: textColor, fontWeight: FontWeight.w700),
        labelMedium: TextStyle(color: textColor, fontWeight: FontWeight.w600),
        labelSmall: TextStyle(color: textColor, fontWeight: FontWeight.w500),
      ),
    );
  }

  static ThemeData get darkTheme {
    const colors = AppColors.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: colors.bg,
      colorScheme: ColorScheme.dark(
        surface: colors.bg,
        primary: AppColors.accent,
        secondary: AppColors.accentCyan,
        onPrimary: Colors.white,
        onSurface: colors.text,
        outline: colors.border,
      ),
      textTheme: _textTheme(colors.text),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.headerBg,
        foregroundColor: colors.text,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      extensions: const <ThemeExtension<dynamic>>[colors],
    );
  }

  static ThemeData get whiteTheme {
    const colors = AppColors.white;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: colors.bg,
      colorScheme: ColorScheme.light(
        surface: colors.bg,
        primary: AppColors.accent,
        secondary: AppColors.accentCyan,
        onPrimary: Colors.white,
        onSurface: colors.text,
        outline: colors.border,
      ),
      textTheme: _textTheme(colors.text),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.headerBg,
        foregroundColor: colors.text,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      extensions: const <ThemeExtension<dynamic>>[colors],
    );
  }
}
