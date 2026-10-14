import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// One family (Inter), four sizes, three weights. Left aligned, tight
/// display tracking, 14px floor.
class AppType {
  AppType._();

  static TextStyle _inter(double size, FontWeight weight,
      {double height = 1.4, double tracking = 0, Color color = AppColors.ink}) {
    return GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: tracking,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  /// 40 / 800 - login, hero numbers. Never more than two lines.
  static TextStyle get display =>
      _inter(40, FontWeight.w800, height: 1.05, tracking: -1.6);

  /// 24 / 800 - page title.
  static TextStyle get title =>
      _inter(24, FontWeight.w800, height: 1.15, tracking: -0.6);

  /// 16 / 800 - section heading.
  static TextStyle get heading => _inter(16, FontWeight.w800, height: 1.3);

  /// 16 / 400 - body.
  static TextStyle get body => _inter(16, FontWeight.w400, height: 1.5);

  /// 16 / 600 - emphasised body, buttons.
  static TextStyle get bodyStrong => _inter(16, FontWeight.w600, height: 1.4);

  /// 14 / 600 - labels, nav, chips.
  static TextStyle get label => _inter(14, FontWeight.w600, height: 1.3);

  /// 14 / 400 muted - secondary notes only.
  static TextStyle get meta =>
      _inter(14, FontWeight.w400, height: 1.45, color: AppColors.muted);
}
