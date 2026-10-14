import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// A block of tone. No border, no shadow, no radius - the step from canvas to
/// surface to raised does the separating.
class AppSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool raised;
  final Color? color;
  final VoidCallback? onTap;

  const AppSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.raised = false,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = color ?? (raised ? AppColors.raised : AppColors.surface);
    final body = Padding(padding: padding, child: child);
    return Material(
      color: bg,
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
