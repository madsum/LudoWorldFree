import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Floating Ludo Pieces background widget for a rich gaming aesthetic
class FloatingLudoPieces extends StatefulWidget {
  final Widget child;

  const FloatingLudoPieces({super.key, required this.child});

  @override
  State<FloatingLudoPieces> createState() => _FloatingLudoPiecesState();
}

class _FloatingLudoPiecesState extends State<FloatingLudoPieces>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _LudoPiecesBackgroundPainter(_controller.value),
          child: widget.child,
        );
      },
    );
  }
}

class _LudoPiecesBackgroundPainter extends CustomPainter {
  final double animationValue;

  _LudoPiecesBackgroundPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    // Gradient Background
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0xFF090D20),
          Color(0xFF0F1735),
          Color(0xFF1B2245),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final floatOffset1 = math.sin(animationValue * math.pi * 2) * 15;
    final floatOffset2 = math.cos(animationValue * math.pi * 2) * 12;

    // Draw Floating Ludo Pawn Icons (Red, Green, Blue, Gold)
    _drawPawn(canvas, Offset(size.width * 0.12, size.height * 0.15 + floatOffset1),
        32, const Color(0xFFE53935).withValues(alpha: 0.35)); // Red
    _drawPawn(canvas, Offset(size.width * 0.85, size.height * 0.22 - floatOffset2),
        40, const Color(0xFF36C86B).withValues(alpha: 0.35)); // Green
    _drawPawn(canvas, Offset(size.width * 0.15, size.height * 0.78 - floatOffset1),
        36, const Color(0xFFF4C542).withValues(alpha: 0.35)); // Gold
    _drawPawn(canvas, Offset(size.width * 0.88, size.height * 0.82 + floatOffset2),
        34, const Color(0xFF0B5ED7).withValues(alpha: 0.35)); // Blue

    // Floating Dice Orbs
    _drawDiceDot(canvas, Offset(size.width * 0.25, size.height * 0.40 + floatOffset2), 18);
    _drawDiceDot(canvas, Offset(size.width * 0.78, size.height * 0.58 - floatOffset1), 14);
  }

  void _drawPawn(Canvas canvas, Offset center, double radius, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);

    // Glow circle
    canvas.drawCircle(center, radius * 1.2, glowPaint);

    // Pawn head
    canvas.drawCircle(Offset(center.dx, center.dy - radius * 0.4), radius * 0.35, paint);

    // Pawn body
    final path = Path();
    path.moveTo(center.dx - radius * 0.45, center.dy + radius * 0.5);
    path.quadraticBezierTo(
      center.dx,
      center.dy - radius * 0.1,
      center.dx + radius * 0.45,
      center.dy + radius * 0.5,
    );
    path.close();
    canvas.drawPath(path, paint);

    // Pawn base
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(center.dx, center.dy + radius * 0.55),
          width: radius * 1.1,
          height: radius * 0.22,
        ),
        const Radius.circular(4),
      ),
      paint,
    );
  }

  void _drawDiceDot(Canvas canvas, Offset center, double size) {
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final fillPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..style = PaintingStyle.fill;

    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: size, height: size),
      const Radius.circular(4),
    );

    canvas.drawRRect(rect, fillPaint);
    canvas.drawRRect(rect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _LudoPiecesBackgroundPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}
