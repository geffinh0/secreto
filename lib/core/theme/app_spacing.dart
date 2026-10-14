import 'package:flutter/material.dart';

/// 4/8 spacing scale and the two breakpoints the whole app shares.
/// Phone < 600, tablet 600-899, desktop >= 900.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  static const double tablet = 600;
  static const double desktop = 900;

  /// Content never grows wider than this, even on an ultrawide monitor.
  static const double maxContentWidth = 1200;

  /// Minimum touch target.
  static const double touch = 48;

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < tablet;

  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= desktop;

  /// 16 on phones, 24 on tablets, 32 on desktop.
  static double pageHorizontal(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < tablet) return md;
    if (w < desktop) return lg;
    return xl;
  }

  static EdgeInsets page(BuildContext context) {
    final h = pageHorizontal(context);
    return EdgeInsets.fromLTRB(h, lg, h, xxl);
  }

  /// Gap between major sections.
  static double section(BuildContext context) => isCompact(context) ? xl : xxl;
}
