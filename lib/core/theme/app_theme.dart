import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

ThemeData buildAppTheme() {
  const base = Color(0xFF153B52);
  const accent = Color(0xFFD97C42);
  const soft = Color(0xFFE9DED0);

  final colorScheme = ColorScheme.fromSeed(
    seedColor: base,
    primary: base,
    secondary: accent,
    surface: soft,
    brightness: Brightness.light,
  );

  final textTheme = GoogleFonts.ibmPlexSansTextTheme().copyWith(
    displaySmall: GoogleFonts.fraunces(
      fontSize: 34,
      fontWeight: FontWeight.w700,
      color: base,
    ),
    headlineMedium: GoogleFonts.fraunces(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      color: base,
    ),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    textTheme: textTheme,
    scaffoldBackgroundColor: const Color(0xFFF9F5EE),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
  );
}
