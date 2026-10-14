import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_shape.dart';
import '../../core/theme/app_type.dart';

/// A 56px-minimum row. It draws no box of its own: rows live inside an
/// [AppRowList], which groups them in one panel with hairlines between.
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
        : (raised ? AppColors.raised : Colors.transparent);
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

/// Vertical list: all rows in one lighter-paper panel with a hairline and
/// hairline dividers, instead of a stack of separate boxes.
class AppRowList extends StatelessWidget {
  final List<Widget> children;

  const AppRowList({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: AppShape.quiet,
        side: AppShape.hairline,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(),
            children[i],
          ],
        ],
      ),
    );
  }
}
