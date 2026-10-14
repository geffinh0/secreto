import 'package:flutter/material.dart';

/// Herbarium palette (light only): paper ground, forest-green ink, terracotta
/// for the action, sage for secondary tone, aged gold for ornament.
///
/// Contrast (WCAG, computed): ink on canvas 10.5, muted on canvas 6.2,
/// onAccent on accent 5.5, status colours >= 4.7 on surface and raised.
/// [gold], [sage] and [rule] are decoration only (3.4 / 3.2 / 1.5 on canvas):
/// never text, never the only border of a control.
class AppColors {
  AppColors._();

  // Grounds, from the page outwards.
  static const Color canvas = Color(0xFFF4ECDC); // paper
  static const Color surface = Color(0xFFFBF6EA); // lighter paper: fields, panels
  static const Color raised = Color(0xFFE3E8D6); // pale sage: chips, secondary fills
  static const Color raisedHover = Color(0xFFD3DBC2);

  // Ink.
  static const Color ink = Color(0xFF1F3A2E); // forest
  static const Color muted = Color(0xFF4A5B4F); // secondary text

  // Action: terracotta.
  static const Color accent = Color(0xFFA8461F);
  static const Color accentHover = Color(0xFF8F3A18);
  static const Color accentPressed = Color(0xFF7A3114);
  static const Color onAccent = Color(0xFFFBF6EA);

  // Forest block (sidebar, status panel): the area of contrast.
  static const Color forest = Color(0xFF1F3A2E);
  static const Color forestSoft = Color(0xFF2D5242);
  static const Color onForest = Color(0xFFFBF6EA);
  static const Color onForestMuted = Color(0xFFDCD6C6);
  static const Color goldLight = Color(0xFFD2B568); // gold on forest

  // Decoration only.
  static const Color gold = Color(0xFF9A7B2F);
  static const Color sage = Color(0xFF6F8A6A);
  static const Color rule = Color(0xFFCFC3A8); // hairlines between rows

  // Status: always paired with an icon and a word.
  static const Color danger = Color(0xFFA82A24);
  static const Color success = Color(0xFF2F6B3F);
  static const Color warning = Color(0xFF8A5A00);
}
