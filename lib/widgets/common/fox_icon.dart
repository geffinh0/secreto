import 'package:flutter/material.dart';

/// The robot's official mascot icon: a stylized cute fox avatar.
/// Uses the high-resolution brand asset with smooth scaling.
class FoxIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final double? borderRadius;

  const FoxIcon({
    super.key,
    this.size = 24,
    this.color,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? (size * 0.24);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        'assets/images/fox_avatar.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, error, stackTrace) {
          return Icon(
            Icons.smart_toy_rounded,
            size: size * 0.7,
            color: color ?? Colors.white,
          );
        },
      ),
    );
  }
}

