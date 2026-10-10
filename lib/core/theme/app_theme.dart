import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Palette from GUIA_DESIGN_ATILAS_CLIENT.md ("A toca de comando"): fox
/// orange, warm burrow browns, soft cream. Flat and restrained on purpose -
/// no neon glows, no decorative multi-hue gradients. Names kept stable so
/// existing screens don't need touching; only the hex values moved to the
/// new guide's tokens (bgDark=canvas, bgCard=surface, bgSurface=surface
/// used as a slightly lighter field fill, bgElevated=surfaceRaised).
class AppTheme {
  // Brand Colors
  static const Color primary = Color(0xFFE07B39); // fox
  static const Color primaryDark = Color(0xFFB95F29); // fox-pressed

  static const Color secondary = Color(0xFFA24A32); // ember
  static const Color accent = Color(0xFFD9A441); // gold

  // Background (a den at dusk, not a cold black)
  static const Color bgDark = Color(0xFF17110D); // canvas
  static const Color bgCard = Color(0xFF211811); // surface
  static const Color bgSurface = Color(0xFF2B2017); // surface-raised (fields)
  static const Color bgElevated = Color(0xFF35271D); // surface-hover

  // Text
  static const Color textPrimary = Color(0xFFF8F0E7); // ink
  static const Color textSecondary = Color(0xFFCBB8A5); // ink-muted
  static const Color textMuted = Color(0xFF9B8673); // ink-subtle
  static const Color textDisabled = Color(0xFF6B5A49);

  // Status (muted, same warm family)
  static const Color success = Color(0xFF79A86A);
  static const Color warning = Color(0xFFE0B45B);
  static const Color error = Color(0xFFD66A52); // danger
  static const Color info = Color(0xFF82AFC0);

  // Borders
  static const Color border = Color(0xFF463428);
  static const Color borderLight = Color(0xFF634733); // border-strong

  // Dark ink for text/icons sitting on top of a bright fill (primary button,
  // status pills, chips) - measured higher contrast than textPrimary there.
  static const Color onAccent = Color(0xFF211811);

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgDark,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        surface: bgSurface,
        error: error,
        onPrimary: textPrimary,
        onSecondary: textPrimary,
        onSurface: textPrimary,
      ),
      textTheme: GoogleFonts.nunitoTextTheme(
        ThemeData.dark().textTheme.copyWith(
              displayLarge: const TextStyle(
                color: textPrimary,
                fontSize: 32,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
              displayMedium: const TextStyle(
                color: textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
              titleLarge: const TextStyle(
                color: textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
              titleMedium: const TextStyle(
                color: textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              bodyLarge: const TextStyle(
                color: textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w400,
              ),
              bodyMedium: const TextStyle(
                color: textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
              labelLarge: const TextStyle(
                color: textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
      ),
      cardTheme: CardThemeData(
        color: bgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgSurface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: error),
        ),
        labelStyle: const TextStyle(color: textMuted),
        hintStyle: const TextStyle(color: textDisabled),
        prefixIconColor: textMuted,
        suffixIconColor: textMuted,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onAccent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return textPrimary;
          return textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primary;
          return bgElevated;
        }),
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
      ),
      iconTheme: const IconThemeData(
        color: textSecondary,
        size: 20,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: bgElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
        ),
        textStyle: const TextStyle(color: textPrimary, fontSize: 13),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: bgElevated,
        contentTextStyle: const TextStyle(color: textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
