import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_shape.dart';

/// A panel on the paper. Default: lighter paper with a hairline and a quiet
/// 4px corner. [raised] is a pale sage fill with no line (a note inside a
/// panel). [feature] is the one signature surface: the leaf shape, used for a
/// single highlight per screen. No shadows.
class AppSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool raised;
  final bool feature;
  final Color? color;
  final VoidCallback? onTap;

  const AppSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.raised = false,
    this.feature = false,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = color ?? (raised ? AppColors.raised : AppColors.surface);
    final radius = feature ? AppShape.leaf : AppShape.quiet;
    final shape = RoundedRectangleBorder(
      borderRadius: radius,
      side: raised || color != null ? BorderSide.none : AppShape.hairline,
    );
    final body = Padding(padding: padding, child: child);
    return Material(
      color: bg,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? body
          : InkWell(
              onTap: onTap,
              hoverColor: AppColors.raisedHover,
              child: body,
            ),
    );
  }
}
