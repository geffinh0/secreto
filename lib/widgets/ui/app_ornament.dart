import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Gold hairline with a small vine at its centre. Drawn in code because it is
/// only a stroke and two leaves; the detailed illustration lives in the fox
/// assets. Use it where a screen changes register (sign-in, the Painel), not
/// as a header decoration on every page.
class OrnamentDivider extends StatelessWidget {
  final double ornamentWidth;

  const OrnamentDivider({super.key, this.ornamentWidth = 72});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Row(
        children: [
          const Expanded(child: _GoldLine()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: CustomPaint(
              size: Size(ornamentWidth, ornamentWidth * 0.3),
              painter: _VinePainter(),
            ),
          ),
          const Expanded(child: _GoldLine()),
        ],
      ),
    );
  }
}

class _GoldLine extends StatelessWidget {
  const _GoldLine();

  @override
  Widget build(BuildContext context) =>
      const SizedBox(height: 1, child: ColoredBox(color: AppColors.gold));
}

/// A whiplash S-curve with two leaves and a bud, in a 100 x 30 box.
class _VinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 30);

    final stroke = Paint()
      ..color = AppColors.gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = AppColors.gold;

    final stem = Path()
      ..moveTo(4, 17)
      ..cubicTo(18, 2, 34, 2, 50, 15)
      ..cubicTo(66, 28, 82, 28, 96, 13);
    canvas.drawPath(stem, stroke);

    void leaf(Offset at, double angle) {
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate(angle);
      final p = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(7, -6, 15, 0)
        ..quadraticBezierTo(7, 6, 0, 0);
      canvas.drawPath(p, fill);
      canvas.restore();
    }

    leaf(const Offset(24, 6), -0.5);
    leaf(const Offset(74, 24), 0.55);
    canvas.drawCircle(const Offset(50, 15), 2.6, fill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
