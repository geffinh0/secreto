import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_shape.dart';
import '../../core/theme/app_type.dart';

enum AppTone { neutral, accent, success, warning, danger }

/// Status or filter chip. Status tones keep a pale-sage ground and put the
/// colour on the icon, so meaning never depends on colour alone (icon + word).
/// With [onTap] it works as a filter: selected fills with the ink colour.
class AppChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final AppTone tone;
  final bool selected;
  final VoidCallback? onTap;

  const AppChip({
    super.key,
    required this.label,
    this.icon,
    this.tone = AppTone.neutral,
    this.selected = false,
    this.onTap,
  });

  Color get _toneColor {
    switch (tone) {
      case AppTone.accent:
        return AppColors.accentInk;
      case AppTone.success:
        return AppColors.success;
      case AppTone.warning:
        return AppColors.warning;
      case AppTone.danger:
        return AppColors.danger;
      case AppTone.neutral:
        return AppColors.muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Selected = inverted ink: dark chip on paper, cream chip at night.
    final fill = selected ? AppColors.ink : AppColors.raised;
    final fg = selected ? AppColors.canvas : AppColors.ink;
    final iconColor = selected ? AppColors.canvas : _toneColor;

    final body = ConstrainedBox(
      constraints: BoxConstraints(minHeight: onTap == null ? 32 : 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                style: AppType.label.copyWith(color: fg),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );

    if (onTap == null) {
      return DecoratedBox(
        decoration: BoxDecoration(color: fill, borderRadius: AppShape.quiet),
        child: body,
      );
    }
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: fill,
        shape: AppShape.quietBorder,
        clipBehavior: Clip.antiAlias,
        // The theme's hover colour is opaque pale sage: over a selected (ink)
        // fill it would hide the fill and leave the light label unreadable.
        child: InkWell(
          onTap: onTap,
          hoverColor: selected
              ? AppColors.canvas.withValues(alpha: 0.16)
              : AppColors.raisedHover,
          child: body,
        ),
      ),
    );
  }
}
