import 'package:flutter/material.dart';

class DekkColors {
  static const green = Color(0xFF0B6E4F);
  static const greenDark = Color(0xFF08513A);
  static const greenTint = Color(0xFFE4F0EA);
  static const ochre = Color(0xFFE3A72F);
  static const ochreTint = Color(0xFFF8D9A0);
  static const ochreInk = Color(0xFF8A4B08);
  static const warnBg = Color(0xFFFDF3E1);
  static const urgent = Color(0xFFB45309);
  static const ground = Color(0xFFF4F3EF);
  static const ink = Color(0xFF14211B);
  static const muted = Color(0xFF4A5650);
  static const line = Color(0xFFC9CFCB);
  static const lineSoft = Color(0xFFECEDEA);
  static const badge = Color(0xFFC2410C);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: DekkColors.green,
    primary: DekkColors.green,
    secondary: DekkColors.ochre,
    surface: Colors.white,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: DekkColors.ground,
    appBarTheme: const AppBarTheme(
      backgroundColor: DekkColors.ground,
      foregroundColor: DekkColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: DekkColors.ink),
    ),
    textTheme: const TextTheme(
      headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.15, color: DekkColors.ink),
      titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: DekkColors.ink),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: DekkColors.ink),
      bodyLarge: TextStyle(fontSize: 16, color: DekkColors.ink),
      bodyMedium: TextStyle(fontSize: 14, color: DekkColors.ink),
      bodySmall: TextStyle(fontSize: 13, color: DekkColors.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: shape,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: shape,
        foregroundColor: DekkColors.ink,
        side: const BorderSide(color: DekkColors.line, width: 1.5),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: DekkColors.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: DekkColors.line, width: 1.5)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: DekkColors.green, width: 2)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: DekkColors.green,
      labelStyle: const TextStyle(fontWeight: FontWeight.w600),
      secondaryLabelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      side: const BorderSide(color: DekkColors.line, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      showCheckmark: false,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: DekkColors.greenTint,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}
