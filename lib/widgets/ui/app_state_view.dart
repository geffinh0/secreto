import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_shape.dart';
import '../../core/theme/app_type.dart';
import '../common/fox_art.dart';
import 'app_button.dart';

enum AppStateKind { empty, error, loading }

/// Empty / error / loading block. Empty says what is missing and the next step;
/// error says what happened and what to do. Left aligned; an optional [pose]
/// puts the fox beside the text (use it only where the whole area is empty,
/// never on every small list).
class AppStateView extends StatelessWidget {
  final AppStateKind kind;
  final String? title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final FoxPose? pose;

  const AppStateView({
    super.key,
    this.kind = AppStateKind.empty,
    this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.pose,
  });

  const AppStateView.loading({super.key, this.message})
      : kind = AppStateKind.loading,
        title = null,
        actionLabel = null,
        onAction = null,
        pose = null;

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
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isError)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Icon(Icons.error_outline, color: AppColors.danger, size: 24),
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
    );
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppShape.quiet,
        border: Border.all(color: AppColors.rule),
      ),
      padding: const EdgeInsets.all(24),
      child: pose == null
          ? text
          : LayoutBuilder(builder: (context, c) {
              // Narrow (phones): the fox sits under the text, never dropped.
              if (c.maxWidth < 380) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    text,
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FoxArt(pose!, height: 84),
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: text),
                  const SizedBox(width: 16),
                  FoxArt(pose!, height: 92),
                ],
              );
            }),
    );
  }
}
