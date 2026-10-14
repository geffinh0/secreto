import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_type.dart';

/// A 56x32 track with a round thumb. On = terracotta track and paper thumb;
/// off = pale-sage track with a muted outline. The hit area is 48px tall.
class AppSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  /// False when a surrounding row already takes focus and activation.
  final bool focusable;

  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
    this.focusable = true,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return Semantics(
      toggled: value,
      enabled: enabled,
      label: semanticLabel,
      child: InkWell(
        onTap: enabled ? () => onChanged!(!value) : null,
        canRequestFocus: focusable,
        hoverColor: Colors.transparent,
        child: SizedBox(
          width: 56,
          height: 48,
          child: Center(
            child: AnimatedContainer(
              duration: AppMotion.base,
              curve: AppMotion.curve,
              width: 56,
              height: 32,
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                color: !enabled
                    ? AppColors.surface
                    : (value ? AppColors.accent : AppColors.raised),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: !enabled
                      ? AppColors.rule
                      : (value ? AppColors.accent : AppColors.muted),
                  width: 1.5,
                ),
              ),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: value ? AppColors.onAccent : AppColors.muted,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row with text on the left and a switch on the right, tappable as a whole.
class AppSwitchRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const AppSwitchRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppType.bodyStrong),
                    if (subtitle != null) Text(subtitle!, style: AppType.meta),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              AppSwitch(
                value: value,
                onChanged: onChanged,
                semanticLabel: title,
                focusable: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
