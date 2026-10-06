import 'package:flutter/material.dart';

/// Palette lifted from the design mockups (design/*.png).
class AppColors {
  static const bg = Color(0xFFF3F2EE);
  static const card = Colors.white;
  static const border = Color(0xFFE4E2DB);
  static const ink = Color(0xFF1A1A1A);
  static const muted = Color(0xFF6B6B66);
  static const green = Color(0xFF1F5F4A);
  static const greenSoft = Color(0xFFDCEBE3);
  static const amber = Color(0xFFC4780E);
  static const amberSoft = Color(0xFFFAEED8);
  static const amberInk = Color(0xFF7A4A00);
  static const blue = Color(0xFF2B4BC9);
  static const blueSoft = Color(0xFFE3EAFA);
  static const chip = Color(0xFFECEAE4);
  static const track = Color(0xFFE4E2DB);
}

const monoFamily = 'Menlo';
const monoFallback = ['Roboto Mono', 'Courier New', 'monospace'];

TextStyle mono({double size = 16, FontWeight weight = FontWeight.w700, Color? color}) =>
    TextStyle(
      fontFamily: monoFamily,
      fontFamilyFallback: monoFallback,
      fontSize: size,
      fontWeight: weight,
      color: color ?? AppColors.ink,
    );

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.green,
    primary: AppColors.green,
    surface: AppColors.bg,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle:
          TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.ink),
    ),
    cardTheme: CardThemeData(
      color: AppColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.green,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, space: 1),
  );
}
