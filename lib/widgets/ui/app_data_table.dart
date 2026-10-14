import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_shape.dart';
import '../../core/theme/app_type.dart';

class AppTableColumn {
  final String label;
  final int flex;
  final Alignment alignment;

  const AppTableColumn(this.label,
      {this.flex = 1, this.alignment = Alignment.centerLeft});
}

/// Table from 900px up (header on pale sage, rows separated by hairlines, no
/// zebra); below that every row becomes a stacked block of "label / value"
/// pairs, so nothing scrolls sideways on a phone.
class AppDataTable extends StatelessWidget {
  final List<AppTableColumn> columns;
  final List<List<Widget>> rows;
  final void Function(int index)? onRowTap;

  /// Which column carries the row's name on the stacked layout (shown first
  /// and in bold, without a label).
  final int titleColumn;

  /// Available width from which the table layout replaces the stacked one.
  final double breakpoint;

  const AppDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.onRowTap,
    this.titleColumn = 0,
    this.breakpoint = 840,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => c.maxWidth >= breakpoint ? _table() : _stacked(),
    );
  }

  Widget _table() {
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
            Container(
              color: AppColors.raised,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  for (final c in columns)
                    Expanded(
                      flex: c.flex,
                      child: Align(
                        alignment: c.alignment,
                        child: Text(c.label, style: AppType.label),
                      ),
                    ),
                ],
              ),
            ),
            for (int i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onRowTap == null ? null : () => onRowTap!(i),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 56),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          for (int c = 0; c < columns.length; c++)
                            Expanded(
                              flex: columns[c].flex,
                              child: Align(
                                alignment: columns[c].alignment,
                                child: rows[i][c],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ));
  }

  Widget _stacked() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          Material(
            color: AppColors.surface,
            shape: const RoundedRectangleBorder(
              borderRadius: AppShape.quiet,
              side: AppShape.hairline,
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onRowTap == null ? null : () => onRowTap!(i),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    rows[i][titleColumn],
                    for (int c = 0; c < columns.length; c++)
                      if (c != titleColumn)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Flexible(
                                flex: 2,
                                child:
                                    Text(columns[c].label, style: AppType.meta),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 3,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: rows[i][c],
                                ),
                              ),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
