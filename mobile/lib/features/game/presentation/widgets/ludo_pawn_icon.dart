import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/models/ludo_color.dart';

/// Compact rendering of the same glossy pawn used on the game board.
class LudoPawnIcon extends StatelessWidget {
  final LudoColor color;
  final double size;

  const LudoPawnIcon({super.key, required this.color, required this.size});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: GlossyPawnPainter(
            color: color.color,
            highlightColor: color.lightColor,
          ),
        ),
      );
}

class GlossyPawnPainter extends CustomPainter {
  final Color color;
  final Color highlightColor;

  const GlossyPawnPainter({
    required this.color,
    required this.highlightColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final unit = math.min(size.width, size.height);
    final cx = size.width / 2;

    final body = Path()
      ..moveTo(cx - unit * 0.12, unit * 0.37)
      ..cubicTo(cx - unit * 0.11, unit * 0.48, cx - unit * 0.27, unit * 0.53,
          cx - unit * 0.35, unit * 0.68)
      ..cubicTo(cx - unit * 0.44, unit * 0.83, cx - unit * 0.41, unit * 0.94,
          cx - unit * 0.29, unit * 0.97)
      ..cubicTo(cx - unit * 0.16, unit * 1.01, cx + unit * 0.16, unit * 1.01,
          cx + unit * 0.29, unit * 0.97)
      ..cubicTo(cx + unit * 0.41, unit * 0.94, cx + unit * 0.44, unit * 0.83,
          cx + unit * 0.35, unit * 0.68)
      ..cubicTo(cx + unit * 0.27, unit * 0.53, cx + unit * 0.11, unit * 0.48,
          cx + unit * 0.12, unit * 0.37)
      ..close();

    final headCenter = Offset(cx, unit * 0.245);
    final headRadius = unit * 0.225;
    final silhouette = Path()
      ..addPath(body, Offset.zero)
      ..addOval(Rect.fromCircle(center: headCenter, radius: headRadius));

    canvas.drawPath(
      silhouette.shift(Offset(0, unit * 0.035)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.50)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, unit * 0.10),
    );

    final bodyBounds = body.getBounds();
    final bodyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(highlightColor, Colors.white, 0.28)!,
          highlightColor,
          color,
          Color.lerp(color, Colors.black, 0.62)!,
        ],
        stops: const [0, 0.22, 0.62, 1],
      ).createShader(bodyBounds);
    canvas.drawPath(body, bodyPaint);

    final bodyOutline = Paint()
      ..color = Color.lerp(color, Colors.black, 0.48)!
      ..style = PaintingStyle.stroke
      ..strokeWidth = unit * 0.025;
    canvas.drawPath(body, bodyOutline);

    final bodyGloss = Path()
      ..moveTo(cx - unit * 0.27, unit * 0.68)
      ..cubicTo(cx - unit * 0.34, unit * 0.77, cx - unit * 0.32, unit * 0.91,
          cx - unit * 0.23, unit * 0.94)
      ..cubicTo(cx - unit * 0.18, unit * 0.95, cx - unit * 0.19, unit * 0.90,
          cx - unit * 0.21, unit * 0.84)
      ..cubicTo(cx - unit * 0.22, unit * 0.78, cx - unit * 0.17, unit * 0.72,
          cx - unit * 0.13, unit * 0.66)
      ..close();
    canvas.drawPath(
      bodyGloss,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.52),
            Colors.white.withValues(alpha: 0.08),
          ],
        ).createShader(bodyBounds),
    );

    final headBounds = Rect.fromCircle(center: headCenter, radius: headRadius);
    canvas.drawCircle(
      headCenter,
      headRadius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.42, -0.58),
          radius: 1.25,
          colors: [
            Color.lerp(highlightColor, Colors.white, 0.68)!,
            highlightColor,
            color,
            Color.lerp(color, Colors.black, 0.55)!,
          ],
          stops: const [0, 0.22, 0.68, 1],
        ).createShader(headBounds),
    );
    canvas.drawCircle(
      headCenter,
      headRadius,
      Paint()
        ..color = Color.lerp(color, Colors.black, 0.36)!
        ..style = PaintingStyle.stroke
        ..strokeWidth = unit * 0.022,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx - unit * 0.075, unit * 0.17),
        width: unit * 0.13,
        height: unit * 0.055,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.58),
    );
  }

  @override
  bool shouldRepaint(covariant GlossyPawnPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.highlightColor != highlightColor;
}
