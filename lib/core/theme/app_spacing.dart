import 'package:flutter/material.dart';

/// Responsive spacing helpers per GUIA_DESIGN_ATILAS_CLIENT.md section 3:
/// mobile gets tighter side padding (16-20px), desktop gets more room
/// (28-36px), and content never stretches edge-to-edge past [maxContentWidth]
/// on very wide screens. Breakpoints match the guide's own table.
class AppSpacing {
  AppSpacing._();

  static const double compact = 599;
  static const double intermediate = 899;
  static const double desktop = 1199;

  /// Content never grows wider than this, even on an ultrawide monitor -
  /// keeps lines of text and forms from stretching into unreadable widths.
  static const double maxContentWidth = 1200;

  static bool isCompact(BuildContext context) =>
      MediaQuery.of(context).size.width <= compact;

  static bool isWide(BuildContext context) =>
      MediaQuery.of(context).size.width > intermediate;

  /// Horizontal page padding: 18px on phones, scaling up to 32px on wide
  /// desktop layouts, per the guide's spacing table.
  static double pageHorizontal(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w <= compact) return 18;
    if (w <= intermediate) return 22;
    if (w <= desktop) return 28;
    return 32;
  }

  /// Full page padding (all sides) for a top-level scrollable screen body.
  static EdgeInsets page(BuildContext context) {
    final h = pageHorizontal(context);
    return EdgeInsets.fromLTRB(h, 20, h, 20);
  }

  /// Vertical gap between major sections of a page (24-32px per the guide).
  static double section(BuildContext context) =>
      MediaQuery.of(context).size.width <= compact ? 20 : 24;
}
