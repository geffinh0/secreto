import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_shape.dart';
import '../../core/theme/app_type.dart';
import 'app_button.dart';

/// Confirmation that names its effect. Initial focus sits on Cancel; the
/// confirm button repeats the action ("Remover palavra", not "OK"). Returns
/// true only when confirmed.
Future<bool> showAppConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancelar',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: AppColors.surface,
      shape: AppShape.leafBorder,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppType.title),
              const SizedBox(height: 8),
              Text(message, style: AppType.body),
              const SizedBox(height: 24),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  AppButton.secondary(
                    label: cancelLabel,
                    autofocus: true,
                    onPressed: () => Navigator.of(ctx).pop(false),
                  ),
                  destructive
                      ? AppButton.danger(
                          label: confirmLabel,
                          onPressed: () => Navigator.of(ctx).pop(true),
                        )
                      : AppButton(
                          label: confirmLabel,
                          onPressed: () => Navigator.of(ctx).pop(true),
                        ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return result ?? false;
}

/// Short feedback message. Errors carry an icon, not just a colour.
void showAppSnack(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(
          borderRadius: AppShape.quiet,
          side: BorderSide(color: AppColors.ink, width: 1.5),
        ),
        content: Row(
          children: [
            Icon(
              error ? Icons.error_outline : Icons.check,
              size: 20,
              color: error ? AppColors.danger : AppColors.success,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: AppType.body)),
          ],
        ),
      ),
    );
}
