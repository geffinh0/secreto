import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Palette drawn from Atila's own fur: fox orange, warm burrow browns, a
/// soft cream for the belly fur. Flat and restrained on purpose - no neon
/// glows, no decorative multi-hue gradients.
class AppTheme {
  // Brand Colors
  static const Color primary = Color(0xFFE07B39); // Fox orange
  static const Color primaryDark = Color(0xFFB35F26); // pressed/hover state

  static const Color secondary = Color(0xFFA24A32); // Ember (deep rust)
  static const Color accent = Color(0xFFD9A441); // Warm gold

  // Background (a den at dusk, not a cold black)
  static const Color bgDark = Color(0xFF1B140F);
  static const Color bgCard = Color(0xFF241B15);
  static const Color bgSurface = Color(0xFF2C2119);
  static const Color bgElevated = Color(0xFF362820);

  // Text
  static const Color textPrimary = Color(0xFFF7EEE3);
  static const Color textSecondary = Color(0xFFCBB8A4);
  static const Color textMuted = Color(0xFF8C7968);
  static const Color textDisabled = Color(0xFF5A4C40);

  // Status (muted, same warm family)
  static const Color success = Color(0xFF6E9B5E);
  static const Color warning = Color(0xFFD9A441);
  static const Color error = Color(0xFFC2543A);

  // Borders
  static const Color border = Color(0xFF3A2D22);
  static const Color borderLight = Color(0xFF4A3A2C);

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
          foregroundColor: textPrimary,
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
