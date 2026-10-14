import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_type.dart';

/// A 56px-minimum row on a surface tone. Rows in a list are separated by an
/// 8px gap (use [AppRowList]) - no dividers.
class AppListRow extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;
  final bool raised;

  const AppListRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.selected = false,
    this.raised = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? AppColors.raisedHover
        : (raised ? AppColors.raised : AppColors.surface);
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: AppType.bodyStrong,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  if (subtitle != null)
                    Text(subtitle!,
                        style: AppType.meta,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    );
    return Material(
      color: bg,
      child: onTap == null
          ? row
          : InkWell(
              onTap: onTap,
              hoverColor: AppColors.raisedHover,
              child: row,
            ),
    );
  }
}

/// Vertical list with the 8px gap between rows.
class AppRowList extends StatelessWidget {
  final List<Widget> children;
  final double gap;

  const AppRowList({super.key, required this.children, this.gap = 8});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(height: gap),
          children[i],
        ],
      ],
    );
  }
}
