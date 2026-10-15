import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_shape.dart';
import '../../core/theme/app_type.dart';

enum AppButtonKind { primary, secondary, text, danger, inverse }

/// 48px minimum. One primary (terracotta fill, leaf shape) per screen. The
/// secondary kind is an ink outline; the danger kind is a danger outline with
/// a danger label and icon, so a destructive action never reads as the main
/// call to action. Text buttons are terracotta words with no box.
class AppButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonKind kind;
  final IconData? icon;
  final bool loading;
  final bool expand;
  final bool autofocus;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = AppButtonKind.primary,
    this.icon,
    this.loading = false,
    this.expand = false,
    this.autofocus = false,
  });

  const AppButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = false,
    this.autofocus = false,
  }) : kind = AppButtonKind.secondary;

  const AppButton.text({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = false,
    this.autofocus = false,
  }) : kind = AppButtonKind.text;

  /// Paper fill with forest ink: the call to action on a forest-green block,
  /// where terracotta would sink into the ground.
  const AppButton.inverse({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = false,
    this.autofocus = false,
  }) : kind = AppButtonKind.inverse;

  const AppButton.danger({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = false,
    this.autofocus = false,
  }) : kind = AppButtonKind.danger;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  bool get _enabled => widget.onPressed != null && !widget.loading;

  Color get _fill {
    switch (widget.kind) {
      case AppButtonKind.primary:
        if (!_enabled) return AppColors.raised;
        if (_pressed) return AppColors.accentPressed;
        return _hovered ? AppColors.accentHover : AppColors.accent;
      case AppButtonKind.inverse:
        if (!_enabled) return AppColors.forestSoft;
        return _pressed || _hovered ? AppColors.raised : AppColors.onForest;
      case AppButtonKind.secondary:
      case AppButtonKind.danger:
      case AppButtonKind.text:
        return (_pressed || _hovered) && _enabled
            ? AppColors.raised
            : Colors.transparent;
    }
  }

  Color get _foreground {
    if (!_enabled) {
      return widget.kind == AppButtonKind.inverse
          ? AppColors.onForestMuted
          : AppColors.muted;
    }
    switch (widget.kind) {
      case AppButtonKind.inverse:
        return AppColors.forest;
      case AppButtonKind.primary:
        return AppColors.onAccent;
      case AppButtonKind.danger:
        return AppColors.danger;
      case AppButtonKind.secondary:
        return AppColors.ink;
      case AppButtonKind.text:
        return AppColors.accentInk;
    }
  }

  Border? get _border {
    if (_focused) return Border.all(color: AppColors.ink, width: 2);
    switch (widget.kind) {
      case AppButtonKind.secondary:
        return Border.all(
            color: _enabled ? AppColors.ink : AppColors.rule, width: 1.5);
      case AppButtonKind.danger:
        return Border.all(
            color: _enabled ? AppColors.danger : AppColors.rule, width: 1.5);
      case AppButtonKind.primary:
      case AppButtonKind.inverse:
      case AppButtonKind.text:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fg = _foreground;
    final icon = widget.icon ??
        (widget.kind == AppButtonKind.danger
            ? Icons.warning_amber_rounded
            : null);
    final content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.loading)
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        else if (icon != null)
          Icon(icon, size: 20, color: fg),
        if (widget.loading || icon != null) const SizedBox(width: 8),
        Flexible(
          child: Text(
            widget.label,
            style: AppType.bodyStrong.copyWith(color: fg),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.label,
      excludeSemantics: true,
      onTap: _enabled ? widget.onPressed : null,
      child: MouseRegion(
        cursor:
            _enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
          onTap: _enabled ? widget.onPressed : null,
          child: Focus(
            autofocus: widget.autofocus,
            canRequestFocus: _enabled,
            onFocusChange: (v) => setState(() => _focused = v),
            onKeyEvent: (node, event) {
              if (_enabled &&
                  event is KeyDownEvent &&
                  (event.logicalKey == LogicalKeyboardKey.enter ||
                      event.logicalKey == LogicalKeyboardKey.space)) {
                widget.onPressed!();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: AnimatedContainer(
              duration: AppMotion.fast,
              constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: _fill,
                border: _border,
                borderRadius: widget.kind == AppButtonKind.primary ||
                        widget.kind == AppButtonKind.inverse
                    ? AppShape.leaf
                    : AppShape.quiet,
              ),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}
