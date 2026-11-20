import 'package:flutter/material.dart';

/// Compact, shiny Mjölnir illustration used as a selectable game reaction.
class MjolnirIcon extends StatelessWidget {
  const MjolnirIcon({super.key, this.size = 42});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _MjolnirPainter()),
      );
}

class _MjolnirPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.shortestSide / 64;
    final center = Offset(size.width / 2, size.height / 2);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-0.48);
    canvas.scale(unit);
    canvas.translate(-32, -32);

    // Short leather-wrapped handle, drawn first so it sits behind the head.
    final handle = Path()
      ..moveTo(32, 23)
      ..lineTo(41, 58);
    final handleRect = const Rect.fromLTWH(27, 21, 19, 40);
    canvas.drawPath(
      handle,
      Paint()
        ..color = const Color(0x66000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 11
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawPath(
      handle,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFF432318), Color(0xFFB8793D), Color(0xFF57301F)],
        ).createShader(handleRect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );
    final wrapPaint = Paint()
      ..color = const Color(0xFFD5A66C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (var index = 0; index < 5; index++) {
      final y = 39.0 + index * 3.2;
      canvas.drawLine(Offset(36 + index * 0.7, y),
          Offset(42 + index * 0.7, y - 1.5), wrapPaint);
    }
    canvas.drawCircle(
      const Offset(41, 58),
      3.7,
      Paint()..color = const Color(0xFFB88950),
    );

    // Beveled rectangular hammer head with a cool steel face and bright rim.
    final head = Path()
      ..moveTo(11, 9)
      ..lineTo(48, 9)
      ..lineTo(56, 15)
      ..lineTo(52, 29)
      ..lineTo(8, 29)
      ..lineTo(4, 15)
      ..close();
    canvas.drawShadow(head, const Color(0xCC000000), 4, true);
    canvas.drawPath(
      head,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFFFF), Color(0xFFBCC9D8), Color(0xFF66788D)],
          stops: [0, 0.42, 1],
        ).createShader(const Rect.fromLTWH(4, 9, 52, 20)),
    );
    canvas.drawPath(
      head,
      Paint()
        ..color = const Color(0xFF34475C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Bright bevel and a tiny lightning rune make the hammer read as Mjölnir.
    final bevel = Path()
      ..moveTo(11, 11)
      ..lineTo(47, 11)
      ..lineTo(52, 15);
    canvas.drawPath(
      bevel,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.88)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    final rune = Path()
      ..moveTo(33, 13)
      ..lineTo(28, 19)
      ..lineTo(33, 19)
      ..lineTo(29, 25)
      ..lineTo(38, 17)
      ..lineTo(33, 17)
      ..close();
    canvas.drawPath(
      rune,
      Paint()..color = const Color(0xFF3984C5).withValues(alpha: 0.9),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MjolnirPainter oldDelegate) => false;
}
