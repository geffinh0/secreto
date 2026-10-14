import 'package:flutter/material.dart';

/// Swiss palette: one ground, one ink, one accent. Surfaces are separated by
/// tone steps, never by lines or shadows. The accent is the fox orange and
/// marks the action; status colours always travel with an icon and a word.
class AppColors {
  AppColors._();

  static const Color canvas = Color(0xFF121212);
  static const Color surface = Color(0xFF1C1C1C);
  static const Color raised = Color(0xFF262626);
  static const Color raisedHover = Color(0xFF303030);

  static const Color ink = Color(0xFFF4F4F0);
  static const Color muted = Color(0xFFA8A8A4);

  static const Color accent = Color(0xFFE07B39);
  static const Color accentHover = Color(0xFFEA8C4D);
  static const Color accentPressed = Color(0xFFC96A2D);
  static const Color onAccent = Color(0xFF121212);

  static const Color danger = Color(0xFFE5484D);
  static const Color success = Color(0xFF5FA36A);
  static const Color warning = Color(0xFFE0B45B);
}
