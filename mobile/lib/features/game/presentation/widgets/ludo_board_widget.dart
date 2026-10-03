import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../domain/game_engine.dart';
import '../../domain/models/board_position.dart';
import '../../domain/models/game_state.dart';
import '../../domain/models/ludo_color.dart';
import '../../domain/models/pawn_model.dart';

class LudoBoardWidget extends StatelessWidget {
  final GameState gameState;
  final ValueChanged<PawnModel> onPawnTap;

  const LudoBoardWidget({
    super.key,
    required this.gameState,
    required this.onPawnTap,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.0,
      child: Container(
        margin: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            colors: [Color(0xFFFFEA00), Color(0xFFFF8F00), Color(0xFFB76E00)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: AppColors.gold.withValues(alpha: 0.4),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(6.0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: CustomPaint(
              painter: _LudoBoardPainter(gameState: gameState),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final tileSize = constraints.maxWidth / 15.0;
                  return Stack(
                    children: _buildPawnWidgets(tileSize),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Calculates pawn positions with multi-token stacking offsets
  List<Widget> _buildPawnWidgets(double tileSize) {
    final widgets = <Widget>[];

    // Map to group pawns by target tile coordinate key "x_y"
    final Map<String, List<Map<String, dynamic>>> tileOccupants = {};

    for (final player in gameState.players) {
      for (final pawn in player.pawns) {
        if (pawn.isFinished) continue;

        BoardPosition pos;
        if (pawn.isYard) {
          pos = BoardPosition.getYardPositions(pawn.color)[pawn.id];
        } else if (pawn.isInHomeStretch) {
          final stretch = BoardPosition.getHomeStretch(pawn.color);
          pos = stretch[pawn.stepCount - 51];
        } else {
          final globalIdx = pawn.globalTileIndex!;
          pos = BoardPosition.mainTrack[globalIdx];
        }

        final key = '${pos.x}_${pos.y}';
        final isMovable = gameState.turnPhase == GameTurnPhase.selectPawn &&
            gameState.currentPlayer.color == pawn.color &&
            gameState.movablePawns.any((p) => p.id == pawn.id && p.color == pawn.color);

        tileOccupants.putIfAbsent(key, () => []);
        tileOccupants[key]!.add({
          'pawn': pawn,
          'pos': pos,
          'isMovable': isMovable,
        });
      }
    }

    // Generate pawn widgets with sub-grid offsets for stacked pawns
    tileOccupants.forEach((key, occupantList) {
      final totalOnTile = occupantList.length;

      for (int i = 0; i < totalOnTile; i++) {
        final item = occupantList[i];
        final PawnModel pawn = item['pawn'];
        final BoardPosition pos = item['pos'];
        final bool isMovable = item['isMovable'];

        // Sub-grid stacking offsets
        double offsetX = 0.0;
        double offsetY = 0.0;
        double pawnScale = 0.82;

        if (totalOnTile == 2) {
          pawnScale = 0.58;
          offsetX = (i == 0 ? -0.18 : 0.18) * tileSize;
        } else if (totalOnTile >= 3) {
          pawnScale = 0.50;
          final row = i ~/ 2;
          final col = i % 2;
          offsetX = (col == 0 ? -0.20 : 0.20) * tileSize;
          offsetY = (row == 0 ? -0.20 : 0.20) * tileSize;
        }

        final left = (pos.x * tileSize) + (tileSize * (1.0 - pawnScale) / 2) + offsetX;
        final top = (pos.y * tileSize) + (tileSize * (1.0 - pawnScale) / 2) + offsetY;
        final size = tileSize * pawnScale;

        widgets.add(
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOutQuad,
            left: left,
            top: top,
            width: size,
            height: size,
            child: GestureDetector(
              onTap: isMovable ? () => onPawnTap(pawn) : null,
              child: _PawnTileWidget(
                color: pawn.color,
                isMovable: isMovable,
                size: size,
              ),
            ),
          ),
        );
      }
    });

    return widgets;
  }
}

/// 3D Styled Pawn Token Widget
class _PawnTileWidget extends StatelessWidget {
  final LudoColor color;
  final bool isMovable;
  final double size;

  const _PawnTileWidget({
    required this.color,
    required this.isMovable,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final baseColor = color.color;

    return Stack(
      alignment: Alignment.center,
      children: [
        // Selection Halo Ring when Movable
        if (isMovable)
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.gold, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: AppColors.gold.withValues(alpha: 0.85),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),

        // 3D Sphere Token Body
        Container(
          width: size * 0.88,
          height: size * 0.88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.lightColor,
                baseColor,
                Color.lerp(baseColor, Colors.black, 0.45)!,
              ],
              center: const Alignment(-0.3, -0.35),
              radius: 0.85,
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 1.8),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 5,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: isMovable
              ? const Icon(Icons.arrow_downward_rounded, color: Colors.white, size: 12)
              : null,
        ),
      ],
    );
  }
}

/// Commercial Grade Custom Painter for Ludo World Free Board
class _LudoBoardPainter extends CustomPainter {
  final GameState gameState;

  _LudoBoardPainter({required this.gameState});

  @override
  void paint(Canvas canvas, Size size) {
    final tileSize = size.width / 15.0;

    final redGradient = _createGradient(AppColors.red, const Color(0xFFD32F2F));
    final greenGradient = _createGradient(AppColors.green, const Color(0xFF2E7D32));
    final yellowGradient = _createGradient(AppColors.gold, const Color(0xFFF57F17));
    final blueGradient = _createGradient(AppColors.royalBlue, const Color(0xFF1565C0));

    final whitePaint = Paint()..color = const Color(0xFFFAFAFA);
    final gridLinePaint = Paint()
      ..color = Colors.black26
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // 1. Draw 4 Corner Home Yards (6x6 cells with 3D Pawn Seats)
    _drawYard(canvas, 0, 0, tileSize * 6, LudoColor.red, redGradient, tileSize);
    _drawYard(canvas, tileSize * 9, 0, tileSize * 6, LudoColor.green, greenGradient, tileSize);
    _drawYard(canvas, tileSize * 9, tileSize * 9, tileSize * 6, LudoColor.yellow, yellowGradient, tileSize);
    _drawYard(canvas, 0, tileSize * 9, tileSize * 6, LudoColor.blue, blueGradient, tileSize);

    // 2. Draw 52 Main Track Tiles
    for (int i = 0; i < BoardPosition.mainTrack.length; i++) {
      final pos = BoardPosition.mainTrack[i];
      final rect = Rect.fromLTWH(pos.x * tileSize, pos.y * tileSize, tileSize, tileSize);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3));

      // Check if start tile
      if (i == 0) {
        canvas.drawRRect(rrect, redGradient);
        _drawStartArrow(canvas, rect, LudoColor.red, tileSize);
      } else if (i == 13) {
        canvas.drawRRect(rrect, greenGradient);
        _drawStartArrow(canvas, rect, LudoColor.green, tileSize);
      } else if (i == 26) {
        canvas.drawRRect(rrect, yellowGradient);
        _drawStartArrow(canvas, rect, LudoColor.yellow, tileSize);
      } else if (i == 39) {
        canvas.drawRRect(rrect, blueGradient);
        _drawStartArrow(canvas, rect, LudoColor.blue, tileSize);
      } else {
        canvas.drawRRect(rrect, whitePaint);
      }

      canvas.drawRRect(rrect, gridLinePaint);

      // Draw 8-Point Star Medallion on Safe Tiles (8, 21, 34, 47 and start tiles)
      if (GameEngine.safeGlobalTiles.contains(i)) {
        _drawStarMedallion(canvas, rect.center, tileSize * 0.35);
      }
    }

    // 3. Draw Home Stretches
    _drawHomeStretch(canvas, BoardPosition.getHomeStretch(LudoColor.red), redGradient, gridLinePaint, tileSize);
    _drawHomeStretch(canvas, BoardPosition.getHomeStretch(LudoColor.green), greenGradient, gridLinePaint, tileSize);
    _drawHomeStretch(canvas, BoardPosition.getHomeStretch(LudoColor.yellow), yellowGradient, gridLinePaint, tileSize);
    _drawHomeStretch(canvas, BoardPosition.getHomeStretch(LudoColor.blue), blueGradient, gridLinePaint, tileSize);

    // 4. Draw Center 4-Triangle Victory Home (3x3 Center Area)
    _drawCenterHome(canvas, tileSize);
  }

  Paint _createGradient(Color c1, Color c2) {
    return Paint()
      ..shader = LinearGradient(
        colors: [c1, c2],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(const Rect.fromLTWH(0, 0, 300, 300));
  }

  void _drawYard(
    Canvas canvas,
    double left,
    double top,
    double size,
    LudoColor color,
    Paint yardPaint,
    double tileSize,
  ) {
    final yardRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, size, size),
      const Radius.circular(14),
    );
    canvas.drawRRect(yardRect, yardPaint);

    // Inner White Box with Drop Shadow
    final innerRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left + tileSize, top + tileSize, tileSize * 4, tileSize * 4),
      const Radius.circular(10),
    );

    final shadowPaint = Paint()
      ..color = Colors.black26
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawRRect(innerRect.shift(const Offset(0, 2)), shadowPaint);

    final whitePaint = Paint()..color = const Color(0xFFFAFAFA);
    canvas.drawRRect(innerRect, whitePaint);

    // Draw 4 Circular 3D Pawn Seats
    final yardPositions = BoardPosition.getYardPositions(color);
    for (final pos in yardPositions) {
      final seatCenter = Offset(
        (pos.x + 0.5) * tileSize,
        (pos.y + 0.5) * tileSize,
      );

      final seatBgPaint = Paint()..color = color.lightColor.withValues(alpha: 0.35);
      canvas.drawCircle(seatCenter, tileSize * 0.38, seatBgPaint);

      final seatBorderPaint = Paint()
        ..color = color.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(seatCenter, tileSize * 0.38, seatBorderPaint);
    }
  }

  void _drawHomeStretch(
    Canvas canvas,
    List<BoardPosition> stretch,
    Paint stretchPaint,
    Paint borderPaint,
    double tileSize,
  ) {
    for (final pos in stretch) {
      final rect = Rect.fromLTWH(pos.x * tileSize, pos.y * tileSize, tileSize, tileSize);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3));
      canvas.drawRRect(rrect, stretchPaint);
      canvas.drawRRect(rrect, borderPaint);
    }
  }

  void _drawStartArrow(Canvas canvas, Rect tileRect, LudoColor color, double tileSize) {
    final arrowPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;

    final path = Path();
    final center = tileRect.center;

    // Arrow pointing into main path
    switch (color) {
      case LudoColor.red: // Arrow points right
        path.moveTo(center.dx - tileSize * 0.25, center.dy - tileSize * 0.25);
        path.lineTo(center.dx + tileSize * 0.25, center.dy);
        path.lineTo(center.dx - tileSize * 0.25, center.dy + tileSize * 0.25);
        break;
      case LudoColor.green: // Arrow points down
        path.moveTo(center.dx - tileSize * 0.25, center.dy - tileSize * 0.25);
        path.lineTo(center.dx, center.dy + tileSize * 0.25);
        path.lineTo(center.dx + tileSize * 0.25, center.dy - tileSize * 0.25);
        break;
      case LudoColor.yellow: // Arrow points left
        path.moveTo(center.dx + tileSize * 0.25, center.dy - tileSize * 0.25);
        path.lineTo(center.dx - tileSize * 0.25, center.dy);
        path.lineTo(center.dx + tileSize * 0.25, center.dy + tileSize * 0.25);
        break;
      case LudoColor.blue: // Arrow points up
        path.moveTo(center.dx - tileSize * 0.25, center.dy + tileSize * 0.25);
        path.lineTo(center.dx, center.dy - tileSize * 0.25);
        path.lineTo(center.dx + tileSize * 0.25, center.dy + tileSize * 0.25);
        break;
    }
    path.close();
    canvas.drawPath(path, arrowPaint);
  }

  void _drawStarMedallion(Canvas canvas, Offset center, double radius) {
    final starPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFFFEA00), Color(0xFFFF8F00)],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.black45
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final path = Path();
    const numPoints = 8;
    final innerRadius = radius * 0.5;

    for (int i = 0; i < numPoints * 2; i++) {
      final r = i.isEven ? radius : innerRadius;
      final angle = i * math.pi / numPoints;
      final x = center.dx + r * math.cos(angle);
      final y = center.dy + r * math.sin(angle);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    canvas.drawPath(path, starPaint);
    canvas.drawPath(path, borderPaint);
  }

  void _drawCenterHome(Canvas canvas, double tileSize) {
    final centerLeft = tileSize * 6;
    final centerTop = tileSize * 6;
    final centerSize = tileSize * 3;
    final centerOffset = Offset(centerLeft + centerSize / 2, centerTop + centerSize / 2);

    final pRed = Paint()..color = AppColors.red;
    final pGreen = Paint()..color = AppColors.green;
    final pYellow = Paint()..color = AppColors.gold;
    final pBlue = Paint()..color = AppColors.royalBlue;

    // Left Triangle (Red)
    final pathRed = Path()
      ..moveTo(centerLeft, centerTop)
      ..lineTo(centerOffset.dx, centerOffset.dy)
      ..lineTo(centerLeft, centerTop + centerSize)
      ..close();
    canvas.drawPath(pathRed, pRed);

    // Top Triangle (Green)
    final pathGreen = Path()
      ..moveTo(centerLeft, centerTop)
      ..lineTo(centerOffset.dx, centerOffset.dy)
      ..lineTo(centerLeft + centerSize, centerTop)
      ..close();
    canvas.drawPath(pathGreen, pGreen);

    // Right Triangle (Yellow)
    final pathYellow = Path()
      ..moveTo(centerLeft + centerSize, centerTop)
      ..lineTo(centerOffset.dx, centerOffset.dy)
      ..lineTo(centerLeft + centerSize, centerTop + centerSize)
      ..close();
    canvas.drawPath(pathYellow, pYellow);

    // Bottom Triangle (Blue)
    final pathBlue = Path()
      ..moveTo(centerLeft, centerTop + centerSize)
      ..lineTo(centerOffset.dx, centerOffset.dy)
      ..lineTo(centerLeft + centerSize, centerTop + centerSize)
      ..close();
    canvas.drawPath(pathBlue, pBlue);

    // Central Golden Victory Crown Medallion
    final centerMedallionPaint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFFFFEA00), Color(0xFFFF8F00), Color(0xFFB76E00)],
      ).createShader(Rect.fromCircle(center: centerOffset, radius: tileSize * 0.75))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(centerOffset, tileSize * 0.75, centerMedallionPaint);

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(centerOffset, tileSize * 0.75, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _LudoBoardPainter oldDelegate) {
    return oldDelegate.gameState != gameState;
  }
}
