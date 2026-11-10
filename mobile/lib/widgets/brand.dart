import 'package:flutter/material.dart';

const appName = 'Arifway';

/// The Arifway mark: an "A" drawn as two roads meeting at a point, with a destination dot. One flat colour.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 28, this.color = Colors.white});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: CustomPaint(painter: _MarkPainter(color)));
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 100;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 13 * k
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(26 * k, 78 * k)
      ..lineTo(50 * k, 22 * k)
      ..lineTo(74 * k, 78 * k);
    canvas.drawPath(path, stroke);
    canvas.drawCircle(Offset(50 * k, 63 * k), 7.5 * k, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.color != color;
}

/// The mark next to the name.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.color = Colors.white, this.fontSize = 22});
  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) => FittedBox(
        // Shrinks rather than overflowing when a narrow top bar leaves little room.
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          BrandMark(size: fontSize * 1.25, color: color),
          const SizedBox(width: 6),
          Text(appName, style: TextStyle(color: color, fontSize: fontSize, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
        ]),
      );
}
