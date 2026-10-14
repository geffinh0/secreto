import 'package:flutter/material.dart';

/// Motion tokens. Only transform and opacity ever animate.
class AppMotion {
  AppMotion._();

  static const Duration fast = Duration(milliseconds: 90);
  static const Duration base = Duration(milliseconds: 160);
  static const Duration slow = Duration(milliseconds: 240);
  static const Curve curve = Curves.easeOutCubic;
  static const Duration stagger = Duration(milliseconds: 60);

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}
