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

  const LudoBoardWidget({
    super.key,
    required this.gameState,
    required this.onPawnTap,
  });

  @override
  State<LudoBoardWidget> createState() => _LudoBoardWidgetState();
}

class _LudoBoardWidgetState extends State<LudoBoardWidget>
    with TickerProviderStateMixin {
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
          if (currentVisualStep != targetStep &&
              !_activeControllers.containsKey(key)) {
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
    final pathSequence = BoardPosition.calculatePathSequence(
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
    final durationMicroseconds =
        toStep == -1 ? totalSteps * 130000 ~/ 3 : totalSteps * 130000;

    final controller = AnimationController(
      vsync: this,
      duration: Duration(microseconds: durationMicroseconds),
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
            child: Stack(
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(painter: const _LudoBoardPainter()),
                  ),
                ),
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final tileSize = constraints.maxWidth / 15.0;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ..._buildPawnWidgets(tileSize),
                          if (widget.gameState.lastCaptureEvent != null)
                            _CaptureBurst(
                              key: ValueKey(
                                widget.gameState.lastCaptureEvent!.timestamp,
                              ),
                              capture: widget.gameState.lastCaptureEvent!,
                              tileSize: tileSize,
                            ),
                          ..._buildPlayerNamePlates(tileSize),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Renders all pawns driven by single visual source of truth
  List<Widget> _buildPawnWidgets(double tileSize) {
    final widgets = <Widget>[];

    // Group static pawns by current visual tile coordinate key "x_y"
    final Map<String, List<Map<String, dynamic>>> staticTileOccupants = {};

    for (final player in widget.gameState.players) {
      for (final pawn in player.pawns) {
        final key = '${pawn.color.name}_${pawn.id}';
        final animationController = _activeControllers[key];

        if (animationController != null) {
          final path = _animationPaths[key]!;
          final totalSteps = math.max(1, path.length - 1);
          final start = path.first;
          widgets.add(
            Positioned(
              key: ValueKey('anim_$key'),
              left: start.x * tileSize + tileSize * 0.09,
              top: start.y * tileSize + tileSize * 0.09,
              width: tileSize * 0.82,
              height: tileSize * 0.82,
              child: AnimatedBuilder(
                animation: animationController,
                child: RepaintBoundary(
                  child: SizedBox(
                    width: tileSize * 0.82,
                    height: tileSize * 0.82,
                    child: _PawnTileWidget(
                      color: pawn.color,
                      isMovable: false,
                      size: tileSize * 0.82,
                    ),
                  ),
                ),
                builder: (context, child) {
                  final progress = animationController.value * totalSteps;
                  final currentIdx =
                      progress.floor().clamp(0, totalSteps - 1).toInt();
                  final nextIdx = (currentIdx + 1).clamp(0, totalSteps).toInt();
                  final stepProgress = progress - currentIdx;
                  final from = path[currentIdx];
                  final to = path[nextIdx];
                  final posX = from.x + (to.x - from.x) * stepProgress;
                  final posY = from.y + (to.y - from.y) * stepProgress;
                  final bounce = math.sin(stepProgress * math.pi);
                  final scale = 1 + (0.16 * bounce);

                  return Transform.translate(
                    offset: Offset((posX - start.x) * tileSize,
                        (posY - start.y) * tileSize),
                    child: Transform.scale(scale: scale, child: child),
                  );
                },
              ),
            ),
          );
        } else {
          // Static pawn position based on current visual step
          final visualStep = _visualSteps[key] ?? pawn.stepCount;
          final pos =
              BoardPosition.getPositionForStep(pawn.color, pawn.id, visualStep);

          final tileKey = '${pos.x}_${pos.y}';
          final isMovable =
              widget.gameState.turnPhase == GameTurnPhase.selectPawn &&
                  widget.gameState.currentPlayer.color == pawn.color &&
                  widget.gameState.movablePawns
                      .any((p) => p.id == pawn.id && p.color == pawn.color);

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

        final left =
            (pos.x * tileSize) + (tileSize * (1.0 - pawnScale) / 2) + offsetX;
        final top =
            (pos.y * tileSize) + (tileSize * (1.0 - pawnScale) / 2) + offsetY;
        final size = tileSize * pawnScale;

        widgets.add(
          Positioned(
            key: ValueKey('static_${pawn.color.name}_${pawn.id}'),
            left: left,
            top: top,
            width: size,
            height: size,
            child: RepaintBoundary(
              child: _PawnTileWidget(
                color: pawn.color,
                isMovable: isMovable,
                size: size,
                onTap: isMovable ? () => widget.onPawnTap(pawn) : null,
              ),
            ),
          ),
        );
      }
    });

    return widgets;
  }

  List<Widget> _buildPlayerNamePlates(double tileSize) {
    return widget.gameState.players.map((player) {
      final isTop =
          player.color == LudoColor.red || player.color == LudoColor.green;
      final isLeft =
          player.color == LudoColor.red || player.color == LudoColor.blue;
      final left = isLeft ? tileSize * 0.55 : tileSize * 9.5;
      final top = isTop ? tileSize * 0.12 : tileSize * 14.08;

      return Positioned(
        key: ValueKey('name_plate_${player.color.name}'),
        left: left,
        top: top,
        width: tileSize * 5,
        height: tileSize * 0.78,
        child: IgnorePointer(
          child: RepaintBoundary(
            child: _PlayerNamePlate(
              name: player.name,
              color: player.color,
              isActive: widget.gameState.currentPlayer.id == player.id &&
                  !widget.gameState.isGameOver,
            ),
          ),
        ),
      );
    }).toList();
  }
}

class _PlayerNamePlate extends StatefulWidget {
  final String name;
  final LudoColor color;
  final bool isActive;

  const _PlayerNamePlate({
    required this.name,
    required this.color,
    required this.isActive,
  });

  @override
  State<_PlayerNamePlate> createState() => _PlayerNamePlateState();
}

class _PlayerNamePlateState extends State<_PlayerNamePlate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 680),
  );

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant _PlayerNamePlate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) _syncPulse();
  }

  void _syncPulse() {
    if (widget.isActive) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final amount = _pulse.value;
        return Opacity(
          opacity: widget.isActive ? 0.82 + amount * 0.18 : 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF10182F).withValues(
                alpha: widget.isActive ? 0.82 : 0.92,
              ),
              border: Border.all(
                color: widget.color.color.withValues(
                  alpha: widget.isActive ? 0.55 + amount * 0.45 : 0.8,
                ),
                width: widget.isActive ? 1.2 : 0.8,
              ),
              borderRadius: BorderRadius.circular(3),
              boxShadow: [
                if (widget.isActive)
                  BoxShadow(
                    color: widget.color.color
                        .withValues(alpha: 0.24 + amount * 0.2),
                    blurRadius: 6 + amount * 3,
                  ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.name,
                    maxLines: 1,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CaptureBurst extends StatefulWidget {
  final PawnCaptureEvent capture;
  final double tileSize;

  const _CaptureBurst({
    super.key,
    required this.capture,
    required this.tileSize,
  });

  @override
  State<_CaptureBurst> createState() => _CaptureBurstState();
}

class _CaptureBurstState extends State<_CaptureBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final position = BoardPosition.mainTrack[widget.capture.globalTrackIndex];
    final tile = widget.tileSize;
    final extent = tile * 1.8;
    final colors = [
      widget.capture.color.color,
      AppColors.gold,
      Colors.white,
      widget.capture.color.color,
      AppColors.gold,
      Colors.white,
    ];

    return Positioned(
      left: (position.x + 0.5) * tile - extent / 2,
      top: (position.y + 0.5) * tile - extent / 2,
      width: extent,
      height: extent,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final progress = _controller.value;
            if (progress >= 1) return const SizedBox.shrink();
            return Stack(
              children: List.generate(colors.length, (index) {
                final angle = (math.pi * 2 * index) / colors.length;
                final distance = tile * 0.58 * progress;
                final dotSize = tile * 0.10 * (1 - progress * 0.45);
                return Positioned(
                  left: extent / 2 + math.cos(angle) * distance - dotSize / 2,
                  top: extent / 2 + math.sin(angle) * distance - dotSize / 2,
                  width: dotSize,
                  height: dotSize,
                  child: Opacity(
                    opacity: (1 - progress).clamp(0.0, 1.0).toDouble(),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors[index],
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: colors[index].withValues(alpha: 0.55),
                            blurRadius: 5,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}

/// 3D Styled Pawn Token Widget
class _PawnTileWidget extends StatefulWidget {
  final LudoColor color;
  final bool isMovable;
  final double size;
  final VoidCallback? onTap;

  const _PawnTileWidget({
    required this.color,
    required this.isMovable,
    required this.size,
    this.onTap,
  });

  @override
  State<_PawnTileWidget> createState() => _PawnTileWidgetState();
}

class _PawnTileWidgetState extends State<_PawnTileWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  );

  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant _PawnTileWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isMovable != widget.isMovable) _syncPulse();
  }

  void _syncPulse() {
    if (widget.isMovable) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.value = 0;
      _pressed = false;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.color.color;

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown:
          widget.onTap == null ? null : (_) => setState(() => _pressed = true),
      onTapCancel:
          widget.onTap == null ? null : () => setState(() => _pressed = false),
      onTapUp:
          widget.onTap == null ? null : (_) => setState(() => _pressed = false),
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final pulse = _pulseController.value;
          return Transform.scale(
            scale:
                _pressed ? 0.90 : (widget.isMovable ? 0.97 + pulse * 0.06 : 1),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (widget.isMovable)
                  Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.gold
                            .withValues(alpha: 0.72 + pulse * 0.28),
                        width: 2.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.gold
                              .withValues(alpha: 0.36 + pulse * 0.28),
                          blurRadius: 7 + pulse * 4,
                          spreadRadius: 1 + pulse,
                        ),
                      ],
                    ),
                  ),
                Container(
                  width: widget.size * 0.88,
                  height: widget.size * 0.88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        widget.color.lightColor,
                        baseColor,
                        Color.lerp(baseColor, Colors.black, 0.45)!,
                      ],
                      center: const Alignment(-0.3, -0.35),
                      radius: 0.85,
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.9),
                      width: 1.8,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black54,
                        blurRadius: 5,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: widget.isMovable
                      ? const Icon(
                          Icons.arrow_downward_rounded,
                          color: Colors.white,
                          size: 12,
                        )
                      : null,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Commercial Grade Custom Painter for Ludo World Free Board
class _LudoBoardPainter extends CustomPainter {
  const _LudoBoardPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final tileSize = size.width / 15.0;

    final redGradient = _createGradient(AppColors.red, const Color(0xFFD32F2F));
    final greenGradient =
        _createGradient(AppColors.green, const Color(0xFF2E7D32));
    final yellowGradient =
        _createGradient(AppColors.gold, const Color(0xFFF57F17));
    final blueGradient =
        _createGradient(AppColors.royalBlue, const Color(0xFF1565C0));

    final whitePaint = Paint()..color = const Color(0xFFFAFAFA);
    final gridLinePaint = Paint()
      ..color = Colors.black26
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // 1. Draw 4 Corner Home Yards (6x6 cells with 3D Pawn Seats)
    _drawYard(canvas, 0, 0, tileSize * 6, LudoColor.red, redGradient, tileSize);
    _drawYard(canvas, tileSize * 9, 0, tileSize * 6, LudoColor.green,
        greenGradient, tileSize);
    _drawYard(canvas, tileSize * 9, tileSize * 9, tileSize * 6,
        LudoColor.yellow, yellowGradient, tileSize);
    _drawYard(canvas, 0, tileSize * 9, tileSize * 6, LudoColor.blue,
        blueGradient, tileSize);

    // 2. Draw 52 Main Track Tiles
    for (int i = 0; i < BoardPosition.mainTrack.length; i++) {
      final pos = BoardPosition.mainTrack[i];
      final rect =
          Rect.fromLTWH(pos.x * tileSize, pos.y * tileSize, tileSize, tileSize);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3));

      // Entry squares stay white and show a colored arrow into the track.
      canvas.drawRRect(rrect, whitePaint);
      if (i == LudoColor.red.actualEntryTrackIndex) {
        _drawStartArrow(canvas, rect, LudoColor.red, tileSize);
      } else if (i == LudoColor.green.actualEntryTrackIndex) {
        _drawStartArrow(canvas, rect, LudoColor.green, tileSize);
      } else if (i == LudoColor.yellow.actualEntryTrackIndex) {
        _drawStartArrow(canvas, rect, LudoColor.yellow, tileSize);
      } else if (i == LudoColor.blue.actualEntryTrackIndex) {
        _drawStartArrow(canvas, rect, LudoColor.blue, tileSize);
      }

      canvas.drawRRect(rrect, gridLinePaint);

      // Entry-safe tiles use arrows. The other four safe tiles use outlined stars.
      if (GameEngine.sharedSafeTiles.contains(i)) {
        _drawSafeStar(canvas, rect.center, tileSize * 0.32);
      }
    }

    // 3. Draw Home Stretches
    _drawHomeStretch(canvas, BoardPosition.getHomeStretch(LudoColor.red),
        redGradient, gridLinePaint, tileSize);
    _drawHomeStretch(canvas, BoardPosition.getHomeStretch(LudoColor.green),
        greenGradient, gridLinePaint, tileSize);
    _drawHomeStretch(canvas, BoardPosition.getHomeStretch(LudoColor.yellow),
        yellowGradient, gridLinePaint, tileSize);
    _drawHomeStretch(canvas, BoardPosition.getHomeStretch(LudoColor.blue),
        blueGradient, gridLinePaint, tileSize);

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

  void _drawStartArrow(
      Canvas canvas, Rect tileRect, LudoColor color, double tileSize) {
    final arrowPaint = Paint()
      ..color = color.color
      ..style = PaintingStyle.fill;

    final path = Path();
    final center = tileRect.center;

    switch (color) {
      case LudoColor.red:
        path.moveTo(center.dx - tileSize * 0.25, center.dy - tileSize * 0.25);
        path.lineTo(center.dx + tileSize * 0.25, center.dy);
        path.lineTo(center.dx - tileSize * 0.25, center.dy + tileSize * 0.25);
        break;
      case LudoColor.green:
        path.moveTo(center.dx - tileSize * 0.25, center.dy - tileSize * 0.25);
        path.lineTo(center.dx, center.dy + tileSize * 0.25);
        path.lineTo(center.dx + tileSize * 0.25, center.dy - tileSize * 0.25);
        break;
      case LudoColor.yellow:
        path.moveTo(center.dx + tileSize * 0.25, center.dy - tileSize * 0.25);
        path.lineTo(center.dx - tileSize * 0.25, center.dy);
        path.lineTo(center.dx + tileSize * 0.25, center.dy + tileSize * 0.25);
        break;
      case LudoColor.blue:
        path.moveTo(center.dx - tileSize * 0.25, center.dy + tileSize * 0.25);
        path.lineTo(center.dx, center.dy - tileSize * 0.25);
        path.lineTo(center.dx + tileSize * 0.25, center.dy + tileSize * 0.25);
        break;
    }
    path.close();
    canvas.drawPath(path, arrowPaint);
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
      Rect.fromLTWH(
          left + tileSize, top + tileSize, tileSize * 4, tileSize * 4),
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

      final seatBgPaint = Paint()
        ..color = color.lightColor.withValues(alpha: 0.35);
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
      final rect =
          Rect.fromLTWH(pos.x * tileSize, pos.y * tileSize, tileSize, tileSize);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3));
      canvas.drawRRect(rrect, stretchPaint);
      canvas.drawRRect(rrect, borderPaint);
    }
  }

  void _drawSafeStar(Canvas canvas, Offset center, double radius) {
    final starPaint = Paint()
      ..color = const Color(0xFF777777)
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
    final centerOffset =
        Offset(centerLeft + centerSize / 2, centerTop + centerSize / 2);

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
      ).createShader(
          Rect.fromCircle(center: centerOffset, radius: tileSize * 0.75))
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
    return false;
  }
}
