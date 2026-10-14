import 'package:flutter/material.dart';
import 'fox_art.dart';

/// The robot's brand mark: the round fox medallion.
class FoxIcon extends StatelessWidget {
  final double size;

  const FoxIcon({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) =>
      FoxArt(FoxPose.medallionCalm, height: size);
}
