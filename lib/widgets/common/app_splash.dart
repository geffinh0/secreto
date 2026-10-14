import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_type.dart';
import 'fox_art.dart';

/// Shown while the saved session is being checked: the fox seen from behind
/// and a quiet progress line.
class AppSplash extends StatelessWidget {
  const AppSplash({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const FoxArt(FoxPose.back, height: 132),
            const SizedBox(height: 24),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: AppColors.accent),
            ),
            const SizedBox(height: 16),
            Text('Abrindo o painel', style: AppType.meta),
          ],
        ),
      ),
    );
  }
}
