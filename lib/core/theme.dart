
import 'package:flutter/material.dart';

/// Design tokens from design/HANDOFF.md. Light and dark share the same roles.
///
/// Screens read colors through [AppColors] (static getters that follow the
/// active brightness). [DietownikApp] rebuilds the tree when brightness
/// changes, so no screen needs a BuildContext to pick a color.
class AppColors {
  static bool _dark = false;
  static bool get isDark => _dark;
  static void setBrightness(Brightness b) => _dark = b == Brightness.dark;

  static Color _p(int light, int dark) => Color(_dark ? dark : light);

  // --- tokens
  static Color get bg => _p(0xFFFFFFFF, 0xFF0F1613);
  static Color get hero => _p(0xFFE3EDE8, 0xFF1A2822);
  static Color get track => _p(0xFFC5D9CF, 0xFF2C3E37);
  static Color get text => _p(0xFF17201C, 0xFFEAF0EC);
  static Color get text2 => _p(0xFF566059, 0xFFB7C4BD);
  static Color get text3 => _p(0xFF3A463F, 0xFFC9D5CE);
  static Color get line => _p(0xFFE1E6E3, 0xFF263630);
  static Color get outline => _p(0xFFCBD3CE, 0xFF3A4D45);
  static Color get field => _p(0xFFEEF2EF, 0xFF1F2D27);
  static Color get accent => _p(0xFF1F5F4A, 0xFF5CC3A0);
  static Color get onAccent => _p(0xFFFFFFFF, 0xFF0F1613);
  static Color get accentDeep => _p(0xFF12392C, 0xFF5CC3A0);
  static Color get protein => _p(0xFF2B4BC9, 0xFF8FA6FF);
  static Color get carbs => _p(0xFFB56A0A, 0xFFF0B05A);
  static Color get fat => _p(0xFFB04A35, 0xFFF08A73);
  static Color get warn => _p(0xFF8A4B06, 0xFFF0B05A);
  static Color get warnBar => _p(0xFFB56A0A, 0xFFF0B05A);
  static Color get warnTrack => _p(0xFFF0DDBF, 0xFF3A3020);
  static Color get danger => _p(0xFFB04A35, 0xFFF08A73);
  static Color get income => _p(0xFF12392C, 0xFF5CC3A0);

  // --- legacy names still used by screens that are not restyled yet
  static Color get card => bg;
  static Color get border => line;
  static Color get ink => text;
  static Color get muted => text2;
  static Color get green => accent;
  static Color get greenSoft => hero;
  static Color get amber => warnBar;
  static Color get amberSoft => warnTrack;
  static Color get amberInk => warn;
  static Color get blue => protein;
  static Color get blueSoft => field;
  static Color get chip => field;
}

const _tabular = [FontFeature.tabularFigures()];

/// Figtree body text. Weight is also set as a variation so the variable font
/// renders the exact weight on every platform.
TextStyle fig(double size, {int weight = 400, Color? color, double? height}) => TextStyle(
      fontFamily: 'Figtree',
      fontSize: size,
      fontWeight: FontWeight.values[(weight ~/ 100) - 1],
      fontVariations: [FontVariation('wght', weight.toDouble())],
      fontFeatures: _tabular,
      color: color ?? AppColors.text,
      height: height,
    );

/// Bricolage Grotesque for headings and the big numbers.
TextStyle display(double size, {int weight = 800, Color? color, double? height}) => TextStyle(
      fontFamily: 'Bricolage',
      fontSize: size,
      fontWeight: FontWeight.values[(weight ~/ 100) - 1],
      fontVariations: [FontVariation('wght', weight.toDouble()), const FontVariation('opsz', 48)],
      fontFeatures: _tabular,
      letterSpacing: size * -0.02,
      color: color ?? AppColors.text,
      height: height ?? 1.0,
    );

/// Number in a row or a card (replaces the old monospace style).
TextStyle figure({double size = 16, Object weight = 700, Color? color}) =>
    fig(size, weight: weight is FontWeight ? (weight.value) : weight as int, color: color);

ThemeData buildTheme(Brightness b) {
  AppColors.setBrightness(b);
  final c = AppColors.text;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF1F5F4A),
    brightness: b,
  ).copyWith(
    primary: AppColors.accent,
    onPrimary: AppColors.onAccent,
    surface: AppColors.bg,
    onSurface: c,
    outline: AppColors.outline,
    outlineVariant: AppColors.line,
    error: AppColors.fat,
  );
  OutlinedBorder r(double v) => RoundedRectangleBorder(borderRadius: BorderRadius.circular(v));
  OutlineInputBorder ib(Color col, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: col, width: w),
      );

  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    fontFamily: 'Figtree',
    textTheme: TextTheme(
      displayLarge: display(72),
      displayMedium: display(56),
      headlineLarge: display(32, weight: 800),
      headlineMedium: display(30, weight: 800),
      titleLarge: fig(18, weight: 700),
      titleMedium: fig(16, weight: 700),
      titleSmall: fig(15, weight: 600),
      bodyLarge: fig(17),
      bodyMedium: fig(16),
      bodySmall: fig(14, color: AppColors.text2),
      labelLarge: fig(16, weight: 700),
      labelMedium: fig(14, weight: 600),
      labelSmall: fig(12, weight: 600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: c,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: display(30),
    ),
    dividerTheme: DividerThemeData(color: AppColors.line, space: 1, thickness: 1),
    cardTheme: CardThemeData(color: AppColors.bg, elevation: 0, margin: EdgeInsets.zero, shape: r(16)),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.onAccent,
        minimumSize: const Size.fromHeight(56),
        shape: r(16),
        elevation: 0,
        textStyle: fig(17, weight: 700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c,
        minimumSize: const Size.fromHeight(56),
        side: BorderSide(color: AppColors.outline),
        shape: r(16),
        textStyle: fig(16, weight: 600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accent,
        minimumSize: const Size(48, 48),
        textStyle: fig(16, weight: 700),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: const Size(48, 48))),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.field,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      hintStyle: fig(16, color: AppColors.text2),
      labelStyle: fig(15, color: AppColors.text2),
      border: ib(Colors.transparent),
      enabledBorder: ib(Colors.transparent),
      focusedBorder: ib(AppColors.accent, 2),
      errorBorder: ib(AppColors.fat),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.hero,
      selectedColor: AppColors.accent,
      labelStyle: fig(14, weight: 600, color: AppColors.accentDeep),
      secondaryLabelStyle: fig(14, weight: 600, color: AppColors.onAccent),
      side: BorderSide.none,
      shape: r(24),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      showDragHandle: false,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      shape: r(24),
      titleTextStyle: fig(20, weight: 700),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: b == Brightness.dark ? AppColors.hero : const Color(0xFF17201C),
      contentTextStyle: fig(15, weight: 600, color: b == Brightness.dark ? AppColors.text : Colors.white),
      shape: r(14),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.onAccent : (b == Brightness.dark ? AppColors.text2 : Colors.white)),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.accent : AppColors.outline),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: fig(16, weight: 600),
      subtitleTextStyle: fig(14, color: AppColors.text2),
      minVerticalPadding: 8,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: AppColors.accent, linearTrackColor: AppColors.track),
  );
}
