import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../domain/game_engine.dart';
import '../../domain/models/board_position.dart';
import '../../domain/models/game_state.dart';
import '../../domain/models/ludo_color.dart';
import '../../domain/models/pawn_model.dart';

class LudoBoardWidget extends StatefulWidget {
  final GameState gameState;
  final ValueChanged<PawnModel> onPawnTap;
  final ValueChanged<PawnModel>? onPairPawnTap;
  final int orientationQuarterTurns;
  final bool compactFrame;

  const LudoBoardWidget({
    super.key,
    required this.gameState,
    required this.onPawnTap,
    this.onPairPawnTap,
    this.orientationQuarterTurns = 0,
    this.compactFrame = false,
  });

  @override
  State<LudoBoardWidget> createState() => _LudoBoardWidgetState();
}

class _LudoBoardWidgetState extends State<LudoBoardWidget> with TickerProviderStateMixin {
  /// Stores current visual step for each pawn: key = "${color.name}_${pawnId}"
  final Map<String, int> _visualSteps = {};

  /// Stores active animation controllers per pawn key
  final Map<String, AnimationController> _activeControllers = {};

  /// Stores paths for moving pawns so only each pawn subtree animates.
  final Map<String, List<BoardPosition>> _animationPaths = {};

  @override
  void initState() {
    super.initState();
    _syncVisualStepsWithGameState(isInitial: true);
  }

  @override
  void didUpdateWidget(covariant LudoBoardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncVisualStepsWithGameState(isInitial: false);
  }

  @override
  void dispose() {
    for (final controller in _activeControllers.values) {
      controller.dispose();
    }
    _activeControllers.clear();
    _animationPaths.clear();
    super.dispose();
  }

  /// Synchronizes logical GameState positions with Visual Animated Positions
  void _syncVisualStepsWithGameState({required bool isInitial}) {
    for (final player in widget.gameState.players) {
      for (final pawn in player.pawns) {
        final key = '${pawn.color.name}_${pawn.id}';
        final targetStep = pawn.stepCount;

        if (isInitial) {
          _visualSteps[key] = targetStep;
        } else {
          final currentVisualStep = _visualSteps[key] ?? targetStep;

          // Check if pawn needs to animate to a new target step
          if (currentVisualStep != targetStep && !_activeControllers.containsKey(key)) {
            _startPawnMovementAnimation(
              key: key,
              color: pawn.color,
              pawnId: pawn.id,
              fromStep: currentVisualStep,
              toStep: targetStep,
            );
          }
        }
      }
    }
  }

  /// Animates pawn square-by-square from [fromStep] to [toStep]
  void _startPawnMovementAnimation({
    required String key,
    required LudoColor color,
    required int pawnId,
    required int fromStep,
    required int toStep,
  }) {
    final isCaptureReturn = toStep == -1 && fromStep >= 0;

    final pathSequence = isCaptureReturn
        ? BoardPosition.calculateReturnPathSequence(
            color: color,
            pawnId: pawnId,
            fromStep: fromStep,
          )
        : BoardPosition.calculatePathSequence(
            color: color,
            pawnId: pawnId,
            fromStep: fromStep,
            toStep: toStep,
          );

    if (pathSequence.isEmpty) {
      _visualSteps[key] = toStep;
      return;
    }

    final totalSteps = math.max(1, pathSequence.length - 1);
    final durationMs = isCaptureReturn ? (totalSteps * 65) : (totalSteps * 130);

    final controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: durationMs),
    );

    _activeControllers[key] = controller;
    _animationPaths[key] = pathSequence;

    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        controller.dispose();
        _activeControllers.remove(key);
        _animationPaths.remove(key);

        if (mounted) {
          setState(() {
            _visualSteps[key] = toStep;
          });
        }
      }
    });

    controller.forward();
  }

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
              painter: _LudoBoardPainter(gameState: widget.gameState),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final tileSize = constraints.maxWidth / 15.0;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ..._buildPawnWidgets(tileSize),
                      ..._buildFinishedPlayerCrowns(tileSize),
                      ..._buildEliminatedPlayerSigns(tileSize),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Renders 3D Golden Crowns and Large Rank Numbers (1, 2, 3) in Yard when a player finishes
  List<Widget> _buildFinishedPlayerCrowns(double tileSize) {
    return widget.gameState.players
        .where((player) => player.rank > 0 && player.rank <= 3 && !player.isEliminated)
        .map((player) {
      final topLeft = switch (player.color) {
        LudoColor.red => const Offset(1, 1),
        LudoColor.green => const Offset(10, 1),
        LudoColor.yellow => const Offset(10, 10),
        LudoColor.blue => const Offset(1, 10),
      };
      final size = tileSize * 4;

      return Positioned(
        key: ValueKey('crown_yard_${player.id}'),
        left: topLeft.dx * tileSize,
        top: topLeft.dy * tileSize,
        width: size,
        height: size,
        child: IgnorePointer(
          child: RotatedBox(
            quarterTurns: (4 - widget.orientationQuarterTurns % 4) % 4,
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 3D Golden Crown Symbol
                  Icon(
                    Icons.workspace_premium_rounded,
                    size: tileSize * 3.4,
                    color: AppColors.gold,
                    shadows: const [
                      Shadow(color: Colors.black87, blurRadius: 12, offset: Offset(0, 4)),
                      Shadow(color: Color(0xFFFFD700), blurRadius: 8),
                    ],
                  ),

                  // Large Rank Number (1, 2, 3)
                  Positioned(
                    top: tileSize * 0.9,
                    child: Text(
                      '${player.rank}',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: tileSize * 1.5,
                        fontWeight: FontWeight.w900,
                        color: Colors.black87,
                        shadows: const [
                          Shadow(color: Colors.white, blurRadius: 4),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  List<Widget> _buildEliminatedPlayerSigns(double tileSize) {
    return widget.gameState.players
        .where((player) => player.isEliminated)
        .map((player) {
      final topLeft = switch (player.color) {
        LudoColor.red => const Offset(1, 1),
        LudoColor.green => const Offset(10, 1),
        LudoColor.yellow => const Offset(10, 10),
        LudoColor.blue => const Offset(1, 10),
      };
      final size = tileSize * 4;

      return Positioned(
        key: ValueKey('eliminated_sign_${player.id}'),
        left: topLeft.dx * tileSize,
        top: topLeft.dy * tileSize,
        width: size,
        height: size,
        child: IgnorePointer(
          child: RotatedBox(
            quarterTurns: (4 - widget.orientationQuarterTurns % 4) % 4,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: Image.asset(
                    'assets/images/exit_sign.png',
                    fit: BoxFit.fill,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.exit_to_app_rounded, color: Colors.red, size: 48),
                  ),
                ),
                Positioned(
                  top: tileSize * 0.1,
                  child: Text(
                    '${player.eliminationOrder}',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: tileSize * 0.58,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  /// Renders all pawns driven by single visual source of truth
  List<Widget> _buildPawnWidgets(double tileSize) {
    final widgets = <Widget>[];

    // Group static pawns by current visual tile coordinate key "x_y"
    final Map<String, List<Map<String, dynamic>>> staticTileOccupants = {};

    for (final player in widget.gameState.players) {
      for (final pawn in player.pawns) {
        if (pawn.isFinished) continue;

        final key = '${pawn.color.name}_${pawn.id}';
        final isAnimating = _activeControllers.containsKey(key);

        if (isAnimating) {
          final path = _animationPaths[key]!;
          final controller = _activeControllers[key]!;
          final totalSteps = math.max(1, path.length - 1);

          widgets.add(
            AnimatedBuilder(
              animation: controller,
              builder: (context, child) {
                final double progress = controller.value * totalSteps;
                final int currentIdx = progress.floor().clamp(0, totalSteps - 1);
                final int nextIdx = (currentIdx + 1).clamp(0, totalSteps);
                final double stepProgress = progress - currentIdx;

                final posA = path[currentIdx];
                final posB = path[nextIdx];

                final double posX = posA.x + (posB.x - posA.x) * stepProgress;
                final double posY = posA.y + (posB.y - posA.y) * stepProgress;

                final double bounceFactor = math.sin(stepProgress * math.pi);
                final double pawnScale = 0.82 + (0.24 * bounceFactor);

                final size = tileSize * pawnScale;
                final left = (posX * tileSize) + (tileSize * (1.0 - pawnScale) / 2);
                final top = (posY * tileSize) + (tileSize * (1.0 - pawnScale) / 2);

                return Positioned(
                  key: ValueKey('anim_$key'),
                  left: left,
                  top: top,
                  width: size,
                  height: size,
                  child: _PawnTileWidget(
                    color: pawn.color,
                    isMovable: false,
                    isPaired: pawn.isPaired,
                    isPairSelected: pawn.isPairSelected,
                    size: size,
                  ),
                );
              },
            ),
          );
        } else {
          // Static pawn position based on current visual step
          final visualStep = _visualSteps[key] ?? pawn.stepCount;
          final pos = BoardPosition.getPositionForStep(pawn.color, pawn.id, visualStep);

          final tileKey = '${pos.x}_${pos.y}';
          final isMovable = widget.gameState.turnPhase == GameTurnPhase.selectPawn &&
              widget.gameState.currentPlayer.color == pawn.color &&
              widget.gameState.movablePawns.any((p) => p.id == pawn.id && p.color == pawn.color);

          staticTileOccupants.putIfAbsent(tileKey, () => []);
          staticTileOccupants[tileKey]!.add({
            'pawn': pawn,
            'pos': pos,
            'isMovable': isMovable,
          });
        }
      }
    }

    // Generate static pawn widgets with sub-grid offsets for stacked pawns
    staticTileOccupants.forEach((tileKey, occupantList) {
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
          Positioned(
            key: ValueKey('static_${pawn.color.name}_${pawn.id}'),
            left: left,
            top: top,
            width: size,
            height: size,
            child: GestureDetector(
              onTap: () {
                // If pawn is eligible for pair creation or selection, toggle pair selection
                if (!pawn.isPaired && pawn.isOnBoard && widget.onPairPawnTap != null) {
                  final sameTileUnpaired = widget.gameState.currentPlayer.pawns.where((p) =>
                      p.id != pawn.id && !p.isPaired && p.stepCount == pawn.stepCount);
                  if (sameTileUnpaired.isNotEmpty || pawn.isPairSelected) {
                    widget.onPairPawnTap!(pawn);
                    return;
                  }
                }
                if (isMovable) {
                  widget.onPawnTap(pawn);
                }
              },
              child: _PawnTileWidget(
                color: pawn.color,
                isMovable: isMovable,
                isPaired: pawn.isPaired,
                isPairSelected: pawn.isPairSelected,
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

/// 3D Styled Pawn Token Widget with Person Silhouette Artwork
class _PawnTileWidget extends StatelessWidget {
  final LudoColor color;
  final bool isMovable;
  final bool isPaired;
  final bool isPairSelected;
  final double size;

  const _PawnTileWidget({
    required this.color,
    required this.isMovable,
    this.isPaired = false,
    this.isPairSelected = false,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final baseColor = color.color;

    return Stack(
      alignment: Alignment.center,
      children: [
        // Team-Color Coating Highlight during Pair Selection
        if (isPairSelected)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: size * 1.15,
            height: size * 1.15,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.lightColor.withValues(alpha: 0.6),
              border: Border.all(color: baseColor, width: 3),
              boxShadow: [
                BoxShadow(
                  color: baseColor.withValues(alpha: 0.9),
                  blurRadius: 12,
                  spreadRadius: 3,
                ),
              ],
            ),
          ),

        // Selection Halo Ring when Movable
        if (isMovable && !isPairSelected)
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

        // 3D Sphere Token Body with Person Silhouette
        Container(
          width: size * 0.88,
          height: size * 0.88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(
              color: isPaired ? AppColors.gold : baseColor,
              width: isPaired ? 2.5 : 2.0,
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black45,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: isPaired
                ? const Icon(Icons.link_rounded, color: AppColors.gold, size: 14)
                : Icon(
                    Icons.accessibility_new_rounded,
                    color: baseColor,
                    size: size * 0.58,
                  ),
          ),
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

      // Draw Colored Visual Start Markers & Arrows on indices 0, 13, 26, 39
      if (i == LudoColor.red.visualStartMarkerIndex) {
        canvas.drawRRect(rrect, redGradient);
        _drawStartArrow(canvas, rect, LudoColor.red, tileSize);
      } else if (i == LudoColor.green.visualStartMarkerIndex) {
        canvas.drawRRect(rrect, greenGradient);
        _drawStartArrow(canvas, rect, LudoColor.green, tileSize);
      } else if (i == LudoColor.yellow.visualStartMarkerIndex) {
        canvas.drawRRect(rrect, yellowGradient);
        _drawStartArrow(canvas, rect, LudoColor.yellow, tileSize);
      } else if (i == LudoColor.blue.visualStartMarkerIndex) {
        canvas.drawRRect(rrect, blueGradient);
        _drawStartArrow(canvas, rect, LudoColor.blue, tileSize);
      } else {
        canvas.drawRRect(rrect, whitePaint);
      }

      canvas.drawRRect(rrect, gridLinePaint);

      // Draw Outlined 5-Point Safe Stars on (8, 21, 34, 47) and Start Markers (0, 13, 26, 39)
      if (GameEngine.safeGlobalTiles.contains(i)) {
        _drawSafeStar(canvas, rect.center, tileSize * 0.35);
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

  void _drawSafeStar(Canvas canvas, Offset center, double radius) {
    final starPaint = Paint()
      ..color = const Color(0xFF616161)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    const numPoints = 5;
    final innerRadius = radius * 0.5;

    for (int i = 0; i < numPoints * 2; i++) {
      final r = i.isEven ? radius : innerRadius;
      final angle = -math.pi / 2 + i * math.pi / numPoints;
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
