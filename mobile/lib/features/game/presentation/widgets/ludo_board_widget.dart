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
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.gold, width: 3),
          boxShadow: [
            BoxShadow(
              color: AppColors.gold.withValues(alpha: 0.3),
              blurRadius: 15,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
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
    );
  }

  List<Widget> _buildPawnWidgets(double tileSize) {
    final widgets = <Widget>[];

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

        final isMovable = gameState.turnPhase == GameTurnPhase.selectPawn &&
            gameState.currentPlayer.color == pawn.color &&
            gameState.movablePawns.any((p) => p.id == pawn.id && p.color == pawn.color);

        widgets.add(
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            left: pos.x * tileSize,
            top: pos.y * tileSize,
            width: tileSize,
            height: tileSize,
            child: GestureDetector(
              onTap: isMovable ? () => onPawnTap(pawn) : null,
              child: _PawnTileWidget(
                color: pawn.color,
                isMovable: isMovable,
                tileSize: tileSize,
              ),
            ),
          ),
        );
      }
    }

    return widgets;
  }
}

class _PawnTileWidget extends StatelessWidget {
  final LudoColor color;
  final bool isMovable;
  final double tileSize;

  const _PawnTileWidget({
    required this.color,
    required this.isMovable,
    required this.tileSize,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: tileSize * 0.8,
        height: tileSize * 0.8,
        decoration: BoxDecoration(
          color: color.color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isMovable ? AppColors.gold : Colors.white,
            width: isMovable ? 3 : 2,
          ),
          boxShadow: [
            BoxShadow(
              color: isMovable ? AppColors.gold.withValues(alpha: 0.8) : Colors.black45,
              blurRadius: isMovable ? 10 : 4,
              spreadRadius: isMovable ? 2 : 0,
            ),
          ],
        ),
        child: isMovable
            ? const Icon(Icons.arrow_downward_rounded, color: Colors.white, size: 14)
            : null,
      ),
    );
  }
}

class _LudoBoardPainter extends CustomPainter {
  final GameState gameState;

  _LudoBoardPainter({required this.gameState});

  @override
  void paint(Canvas canvas, Size size) {
    final tileSize = size.width / 15.0;

    final redPaint = Paint()..color = AppColors.red;
    final greenPaint = Paint()..color = AppColors.green;
    final yellowPaint = Paint()..color = AppColors.gold;
    final bluePaint = Paint()..color = AppColors.royalBlue;
    final whitePaint = Paint()..color = Colors.white;
    final borderPaint = Paint()
      ..color = Colors.black26
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // 1. Draw 4 Home Yards (6x6 cells in corners)
    canvas.drawRect(Rect.fromLTWH(0, 0, tileSize * 6, tileSize * 6), redPaint);
    canvas.drawRect(Rect.fromLTWH(tileSize * 9, 0, tileSize * 6, tileSize * 6), greenPaint);
    canvas.drawRect(Rect.fromLTWH(tileSize * 9, tileSize * 9, tileSize * 6, tileSize * 6), yellowPaint);
    canvas.drawRect(Rect.fromLTWH(0, tileSize * 9, tileSize * 6, tileSize * 6), bluePaint);

    // Yard Inner White Boxes
    canvas.drawRect(Rect.fromLTWH(tileSize, tileSize, tileSize * 4, tileSize * 4), whitePaint);
    canvas.drawRect(Rect.fromLTWH(tileSize * 10, tileSize, tileSize * 4, tileSize * 4), whitePaint);
    canvas.drawRect(Rect.fromLTWH(tileSize * 10, tileSize * 10, tileSize * 4, tileSize * 4), whitePaint);
    canvas.drawRect(Rect.fromLTWH(tileSize, tileSize * 10, tileSize * 4, tileSize * 4), whitePaint);

    // 2. Draw 52 Main Track Tiles Grid
    for (int i = 0; i < BoardPosition.mainTrack.length; i++) {
      final pos = BoardPosition.mainTrack[i];
      final rect = Rect.fromLTWH(pos.x * tileSize, pos.y * tileSize, tileSize, tileSize);

      canvas.drawRect(rect, whitePaint);

      // Color Start Tiles (Red 0, Green 13, Yellow 26, Blue 39)
      if (i == 0) canvas.drawRect(rect, redPaint);
      if (i == 13) canvas.drawRect(rect, greenPaint);
      if (i == 26) canvas.drawRect(rect, yellowPaint);
      if (i == 39) canvas.drawRect(rect, bluePaint);

      canvas.drawRect(rect, borderPaint);

      // Draw Star Icons on Safe Tiles (8, 21, 34, 47)
      if (GameEngine.safeGlobalTiles.contains(i)) {
        _drawStarIcon(canvas, Offset(rect.center.dx, rect.center.dy), tileSize * 0.3);
      }
    }

    // 3. Draw Home Stretches
    for (final pos in BoardPosition.getHomeStretch(LudoColor.red)) {
      final rect = Rect.fromLTWH(pos.x * tileSize, pos.y * tileSize, tileSize, tileSize);
      canvas.drawRect(rect, redPaint);
      canvas.drawRect(rect, borderPaint);
    }
    for (final pos in BoardPosition.getHomeStretch(LudoColor.green)) {
      final rect = Rect.fromLTWH(pos.x * tileSize, pos.y * tileSize, tileSize, tileSize);
      canvas.drawRect(rect, greenPaint);
      canvas.drawRect(rect, borderPaint);
    }
    for (final pos in BoardPosition.getHomeStretch(LudoColor.yellow)) {
      final rect = Rect.fromLTWH(pos.x * tileSize, pos.y * tileSize, tileSize, tileSize);
      canvas.drawRect(rect, yellowPaint);
      canvas.drawRect(rect, borderPaint);
    }
    for (final pos in BoardPosition.getHomeStretch(LudoColor.blue)) {
      final rect = Rect.fromLTWH(pos.x * tileSize, pos.y * tileSize, tileSize, tileSize);
      canvas.drawRect(rect, bluePaint);
      canvas.drawRect(rect, borderPaint);
    }

    // 4. Center Home Triangle Finish Area (3x3 grid in middle)
    final centerRect = Rect.fromLTWH(tileSize * 6, tileSize * 6, tileSize * 3, tileSize * 3);
    canvas.drawRect(centerRect, whitePaint);
    canvas.drawRect(centerRect, borderPaint);
  }

  void _drawStarIcon(Canvas canvas, Offset center, double size) {
    final paint = Paint()
      ..color = AppColors.gold
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, size, paint);
  }

  @override
  bool shouldRepaint(covariant _LudoBoardPainter oldDelegate) {
    return oldDelegate.gameState != gameState;
  }
}
