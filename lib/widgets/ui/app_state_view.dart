import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_type.dart';
import 'app_button.dart';

enum AppStateKind { empty, error, loading }

/// Empty / error / loading block. Empty says what is missing and the next step;
/// error says what happened and what to do. Left aligned, no illustration.
class AppStateView extends StatelessWidget {
  final AppStateKind kind;
  final String? title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const AppStateView({
    super.key,
    this.kind = AppStateKind.empty,
    this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  const AppStateView.loading({super.key, this.message})
      : kind = AppStateKind.loading,
        title = null,
        actionLabel = null,
        onAction = null;

  @override
  Widget build(BuildContext context) {
    if (kind == AppStateKind.loading) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Flexible(child: Text(message ?? 'Carregando', style: AppType.meta)),
          ],
        ),
      );
    }
    final isError = kind == AppStateKind.error;
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isError)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child:
                  Icon(Icons.error_outline, color: AppColors.danger, size: 24),
            ),
          if (title != null) Text(title!, style: AppType.heading),
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(message!, style: AppType.meta),
            ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            AppButton.secondary(label: actionLabel!, onPressed: onAction),
          ],
        ],
      ),
    );
  }
}
