import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Corners. Everything is quiet (small radius) except the "leaf": large radius
/// on two opposite corners, small on the other two. The leaf is the one
/// signature shape and is reserved for the primary button, dialogs and the
/// feature panel; ordinary panels, fields and chips never use it.
class AppShape {
  AppShape._();

  static const double small = 4;
  static const double field = 6;
  static const double leafBig = 18;

  static const BorderRadius quiet = BorderRadius.all(Radius.circular(small));
  static const BorderRadius fieldRadius =
      BorderRadius.all(Radius.circular(field));
  static const BorderRadius leaf = BorderRadius.only(
    topLeft: Radius.circular(leafBig),
    bottomRight: Radius.circular(leafBig),
    topRight: Radius.circular(small),
    bottomLeft: Radius.circular(small),
  );

  static const RoundedRectangleBorder quietBorder =
      RoundedRectangleBorder(borderRadius: quiet);
  static const RoundedRectangleBorder leafBorder =
      RoundedRectangleBorder(borderRadius: leaf);

  /// 1px hairline used between rows and around ordinary panels.
  static const BorderSide hairline = BorderSide(color: AppColors.rule);
}
