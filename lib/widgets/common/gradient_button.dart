import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// A flat, solid-color primary action button. No gradient, no glow - just a
/// confident fill that darkens a touch on hover/press.
class GradientButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isLoading;
  final String? id;

  /// The button's fill color. Defaults to [AppTheme.primary].
  final Color? startColor;

  /// Unused - kept so existing call sites compiled for the old two-tone
  /// gradient don't need to change. The button is a flat fill now.
  final Color? endColor;
  final bool isOutlined;
  final double? width;

  const GradientButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.isLoading = false,
    this.id,
    this.startColor,
    this.endColor,
    this.isOutlined = false,
    this.width,
  });

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isDisabled = widget.onPressed == null || widget.isLoading;
    final fill = widget.startColor ?? AppTheme.primary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: isDisabled
          ? SystemMouseCursors.forbidden
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: isDisabled ? null : widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: widget.width ?? double.infinity,
          height: 50,
          decoration: BoxDecoration(
            color: isDisabled
                ? AppTheme.textDisabled
                : widget.isOutlined
                    ? null
                    : (_pressed || _hovered)
                        ? Color.lerp(fill, Colors.black, 0.12)
                        : fill,
            border: widget.isOutlined
                ? Border.all(color: AppTheme.primary, width: 1.5)
                : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: widget.isLoading
              ? Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: widget.isOutlined ? AppTheme.primary : AppTheme.onAccent,
                      strokeWidth: 2,
                    ),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon,
                          color: widget.isOutlined ? AppTheme.primary : AppTheme.onAccent,
                          size: 18),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      widget.label,
                      style: TextStyle(
                        color: widget.isOutlined ? AppTheme.primary : AppTheme.onAccent,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
