import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The robot's own mascot icon ("Atila's Client"): a little fox face. Used
/// wherever the robot represents itself (app logo, its avatar placeholder),
/// as opposed to generic navigation/section icons that stay on
/// [Icons.smart_toy_rounded].
class FoxIcon extends StatelessWidget {
  final double size;
  final Color color;

  const FoxIcon({super.key, this.size = 24, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/icons/fox.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}
