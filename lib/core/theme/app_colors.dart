import 'package:flutter/material.dart';

/// Herbarium palette in two moods: day (paper, forest ink, terracotta) and
/// night (the same garden after dark: deep green ground, cream ink).
///
/// Every token is a getter that reads [dark], so widgets keep writing
/// `AppColors.ink` and pick up the active mood. [dark] is set once by the app
/// root (see ThemeController / main.dart) before the tree is rebuilt; nothing
/// else should write to it.
///
/// Contrast (WCAG, computed). Day: ink on canvas 10.5, muted on canvas 6.2,
/// onAccent on accent 5.5. Night: ink on canvas 14.4, muted on surface 8.3,
/// onAccent on accent 5.2, status colours >= 4.7 on surface and raised.
/// [gold], [sage] and [rule] are decoration only: never text, never the only
/// border of a control.
class AppColors {
  AppColors._();

  /// True while the night palette is active.
  static bool dark = false;

  static Color _pick(Color day, Color night) => dark ? night : day;

  // Grounds, from the page outwards.
  static Color get canvas =>
      _pick(const Color(0xFFF4ECDC), const Color(0xFF121C17));
  static Color get surface =>
      _pick(const Color(0xFFFBF6EA), const Color(0xFF1B2A22));
  static Color get raised =>
      _pick(const Color(0xFFE3E8D6), const Color(0xFF263A2F));
  static Color get raisedHover =>
      _pick(const Color(0xFFD3DBC2), const Color(0xFF304839));

  // Ink.
  static Color get ink =>
      _pick(const Color(0xFF1F3A2E), const Color(0xFFF1E9D8));
  static Color get muted =>
      _pick(const Color(0xFF4A5B4F), const Color(0xFFB9C4B4));

  // Action: terracotta. [accent] is a fill (with [onAccent] on top);
  // [accentInk] is terracotta used as text or an icon on the ground.
  static Color get accent =>
      _pick(const Color(0xFFA8461F), const Color(0xFFB04B21));
  static Color get accentHover =>
      _pick(const Color(0xFF8F3A18), const Color(0xFFBA5429));
  static Color get accentPressed =>
      _pick(const Color(0xFF7A3114), const Color(0xFF9A411B));
  static Color get onAccent =>
      _pick(const Color(0xFFFBF6EA), const Color(0xFFFFFBF2));
  static Color get accentInk =>
      _pick(const Color(0xFFA8461F), const Color(0xFFEE8F63));

  // Forest block (sidebar, status panel): the area of contrast. Identical in
  // both moods, so the brand block never changes.
  static const Color forest = Color(0xFF1F3A2E);
  static const Color forestSoft = Color(0xFF2D5242);
  static const Color onForest = Color(0xFFFBF6EA);
  static const Color onForestMuted = Color(0xFFDCD6C6);
  static const Color goldLight = Color(0xFFD2B568); // gold on forest

  // Decoration only.
  static Color get gold =>
      _pick(const Color(0xFF9A7B2F), const Color(0xFFC9A95C));
  static Color get sage =>
      _pick(const Color(0xFF6F8A6A), const Color(0xFF8FB08A));
  static Color get rule =>
      _pick(const Color(0xFFCFC3A8), const Color(0xFF35493D)); // hairlines

  // Status: always paired with an icon and a word.
  static Color get danger =>
      _pick(const Color(0xFFA82A24), const Color(0xFFF0837B));
  static Color get success =>
      _pick(const Color(0xFF2F6B3F), const Color(0xFF78C28E));
  static Color get warning =>
      _pick(const Color(0xFF8A5A00), const Color(0xFFE3B55F));
}
