import 'package:flutter/material.dart';

/// The engraved fox sheet, cut into separate transparent WebP pieces in
/// assets/fox/. Each pose has one job; do not use a pose outside its job.
enum FoxPose {
  /// Sitting among flowers: the sign-in scene.
  gardenSitting('fox_garden_sitting', 586 / 818),

  /// Laughing head: the robot is moderating a live.
  headLaugh('fox_head_laugh', 242 / 324),

  /// Calm head: the robot is connected and waiting.
  headCalm('fox_head_calm', 241 / 351),

  /// Curled up asleep: nothing here yet, or the robot is off.
  sleeping('fox_sleeping', 377 / 289),

  /// Looking back over the shoulder: something went wrong.
  lookback('fox_lookback', 239 / 377),

  /// Seen from behind: loading and splash.
  back('fox_back', 246 / 336),

  /// Round medallion: brand mark, app icon.
  medallionCalm('fox_medallion_calm', 1),

  /// Round medallion, smiling: a confirmation.
  medallionSmile('fox_medallion_smile', 1);

  final String file;

  /// width / height of the artwork.
  final double aspect;

  const FoxPose(this.file, this.aspect);

  String get asset => 'assets/fox/$file.webp';
}

/// A fox illustration at a given [height]. Purely decorative, so it is
/// excluded from the semantics tree.
class FoxArt extends StatelessWidget {
  final FoxPose pose;
  final double height;

  const FoxArt(this.pose, {super.key, required this.height});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      pose.asset,
      height: height,
      width: height * pose.aspect,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      excludeFromSemantics: true,
      errorBuilder: (context, error, stackTrace) =>
          SizedBox(height: height, width: height * pose.aspect),
    );
  }
}
