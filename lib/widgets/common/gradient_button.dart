import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class GradientButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isLoading;
  final String? id;
  final Color? startColor;
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
          duration: const Duration(milliseconds: 150),
          width: widget.width ?? double.infinity,
          height: 50,
          transform: _pressed
              ? (Matrix4.identity()..scaleByDouble(0.98, 0.98, 1.0, 1.0))
              : Matrix4.identity(),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: isDisabled
                ? null
                : widget.isOutlined
                    ? null
                    : LinearGradient(
                        colors: [
                          widget.startColor ?? AppTheme.primary,
                          widget.endColor ?? AppTheme.secondary,
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
            color: isDisabled ? AppTheme.textDisabled : null,
            border: widget.isOutlined
                ? Border.all(color: AppTheme.primary, width: 1.5)
                : null,
            borderRadius: BorderRadius.circular(12),
            boxShadow: !isDisabled && !widget.isOutlined
                ? [
                    BoxShadow(
                      color: (widget.startColor ?? AppTheme.primary)
                          .withValues(alpha: _hovered ? 0.45 : 0.25),
                      blurRadius: _hovered ? 20 : 12,
                      spreadRadius: _hovered ? 2 : 0,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: widget.isLoading
              ? const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      widget.label,
                      style: const TextStyle(
                        color: Colors.white,
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
