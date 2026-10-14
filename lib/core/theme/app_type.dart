import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Two local families. Fraunces (soft serif) only for display type from 20px
/// up: page titles, section headings, hero numbers. Source Sans 3 for body,
/// forms, tables, buttons and every small size (14px floor).
class AppType {
  AppType._();

  static TextStyle _serif(double size, FontWeight weight,
      {double height = 1.15, double tracking = 0, Color color = AppColors.ink}) {
    return TextStyle(
      fontFamily: 'Fraunces',
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: tracking,
      color: color,
    );
  }

  // The variable file carries the weight on the wght axis.
  static TextStyle _sans(double size, FontWeight weight,
      {double height = 1.45, double tracking = 0, Color color = AppColors.ink}) {
    return TextStyle(
      fontFamily: 'SourceSans3',
      fontSize: size,
      fontWeight: weight,
      fontVariations: [FontVariation('wght', weight.value.toDouble())],
      height: height,
      letterSpacing: tracking,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  /// Fraunces 44 / 700 - login title, the big status line. Max two lines.
  static TextStyle get display =>
      _serif(44, FontWeight.w700, height: 1.05, tracking: -0.8);

  /// Fraunces 28 / 600 - page title, dialog title.
  static TextStyle get title =>
      _serif(28, FontWeight.w600, height: 1.15, tracking: -0.3);

  /// Fraunces 20 / 600 - section heading.
  static TextStyle get heading => _serif(20, FontWeight.w600, height: 1.25);

  /// Fraunces 36 / 600 - hero numbers (stats, counters).
  static TextStyle get numeral =>
      _serif(36, FontWeight.w600, height: 1.05, tracking: -0.4);

  /// Source Sans 16 / 400 - body.
  static TextStyle get body => _sans(16, FontWeight.w400, height: 1.5);

  /// Source Sans 16 / 600 - emphasised body, buttons.
  static TextStyle get bodyStrong => _sans(16, FontWeight.w600, height: 1.4);

  /// Source Sans 14 / 600 - labels, nav, chips, table headers.
  static TextStyle get label => _sans(14, FontWeight.w600, height: 1.3);

  /// Source Sans 14 / 400 muted - secondary notes, captions.
  static TextStyle get meta =>
      _sans(14, FontWeight.w400, height: 1.45, color: AppColors.muted);
}
