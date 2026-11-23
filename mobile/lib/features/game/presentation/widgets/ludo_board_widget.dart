import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../domain/game_engine.dart';
import '../../domain/models/board_position.dart';
import '../../domain/models/game_state.dart';
import '../../domain/models/ludo_color.dart';
import '../../domain/models/pawn_model.dart';
import 'ludo_pawn_icon.dart';

class LudoBoardWidget extends StatefulWidget {
  final GameState gameState;
  final ValueChanged<PawnModel> onPawnTap;
  final ValueChanged<PawnModel>? onPairPawnTap;
  final int orientationQuarterTurns;
  final bool compactFrame;
  final ValueChanged<LudoColor>? onBellTap;
  final LudoColor? alertedPlayerColor;
  final Set<String> unavailableBellPlayerIds;
  final String? localPlayerId;
  final Set<String> existingBuddyOrRequestPlayerIds;
  final ValueChanged<String>? onBuddyRequestTap;

  const LudoBoardWidget({
    super.key,
    required this.gameState,
    required this.onPawnTap,
    this.onPairPawnTap,
    this.orientationQuarterTurns = 0,
    this.compactFrame = false,
    this.onBellTap,
    this.alertedPlayerColor,
    this.unavailableBellPlayerIds = const {},
    this.localPlayerId,
    this.existingBuddyOrRequestPlayerIds = const {},
    this.onBuddyRequestTap,
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

  /// Tracks the capture event currently being animated with a flame effect.
  PawnCaptureEvent? _flameCaptureEvent;

  /// Tracks the last processed capture event to ensure the flame plays ONCE and stops.
  PawnCaptureEvent? _lastProcessedCaptureEvent;

  /// Animation controller for the capture flame.
  AnimationController? _flameController;
  late final AnimationController _bellAlertController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );

  @override
  void initState() {
    super.initState();
    _syncVisualStepsWithGameState(isInitial: true);
  }

  @override
  void didUpdateWidget(covariant LudoBoardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncVisualStepsWithGameState(isInitial: false);
    if (oldWidget.alertedPlayerColor != widget.alertedPlayerColor) {
      _syncBellAlert();
    }

    // Start the capture flame animation ONCE when a new capture event occurs.
    final captureEvent = widget.gameState.lastCaptureEvent;
    if (captureEvent != null && captureEvent != _lastProcessedCaptureEvent) {
      _lastProcessedCaptureEvent = captureEvent;
      _startCaptureFlame(captureEvent);
    }
  }

  @override
  void dispose() {
    _flameController?.dispose();
    _bellAlertController.dispose();
    for (final controller in _activeControllers.values) {
      controller.dispose();
    }
    _activeControllers.clear();
    _animationPaths.clear();
    super.dispose();
  }

  void _syncBellAlert() {
    if (widget.alertedPlayerColor == null) {
      _bellAlertController.stop();
      _bellAlertController.value = 0;
    } else {
      _bellAlertController.repeat(reverse: true);
    }
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
            final moveEvent = widget.gameState.lastMoveEvent;
            final eventMatchesPawn = moveEvent != null &&
                moveEvent.color == pawn.color &&
                moveEvent.pawnId == pawn.id &&
                moveEvent.toStep == targetStep;
            // The authoritative move event is the source of truth for the
            // animation endpoints. A cached visual step can be stale when a
            // remote state update arrives during a previous animation; using
            // it here can make one roll appear to cover extra squares.
            final fromStep = eventMatchesPawn
                ? moveEvent.fromStep
                : currentVisualStep;
            _visualSteps[key] = fromStep;
            _startPawnMovementAnimation(
              key: key,
              color: pawn.color,
              pawnId: pawn.id,
              fromStep: fromStep,
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
          // A newer state may have arrived while this animation was active.
          // Reconcile it now instead of leaving the pawn visually behind
          // until another game state update happens.
          _syncVisualStepsWithGameState(isInitial: false);
        }
      }
    });

    controller.forward();
  }

  /// Starts the fire/flame and rising black smoke animation at the captured pawn's tile.
  void _startCaptureFlame(PawnCaptureEvent event) {
    if (!mounted) return;
    setState(() {
      _flameCaptureEvent = event;
    });
    _flameController?.dispose();
    _flameController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() {
            _flameCaptureEvent = null;
          });
        }
      });
    _flameController!.forward();
  }

  /// Renders a fire/flame effect at the tile where a pawn was captured.
  List<Widget> _buildCaptureFlame(double tileSize) {
    if (_flameCaptureEvent == null || _flameController == null) return [];

    final pos = BoardPosition.mainTrack[_flameCaptureEvent!.globalTrackIndex];

    return [
      Positioned(
        left: pos.x * tileSize - tileSize * 0.25,
        top: pos.y * tileSize - tileSize * 0.75,
        width: tileSize * 1.5,
        height: tileSize * 1.75,
        child: AnimatedBuilder(
          animation: _flameController!,
          builder: (context, child) {
            return _CaptureFlamePainterWidget(
              color: _flameCaptureEvent!.color.color,
              progress: _flameController!.value,
            );
          },
        ),
      ),
    ];
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
                      ..._buildBellIcons(tileSize),
                      ..._buildBellAlertText(tileSize),
                      ..._buildFinishedPlayerCrowns(tileSize),
                      ..._buildEliminatedPlayerSigns(tileSize),
                      ..._buildCaptureFlame(tileSize),
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

  List<Widget> _buildBellIcons(double tileSize) {
    final size = tileSize * 1.15;
    return widget.gameState.players.map((player) {
      final center = switch (player.color) {
        LudoColor.red => const Offset(3, 3),
        LudoColor.green => const Offset(12, 3),
        LudoColor.yellow => const Offset(12, 12),
        LudoColor.blue => const Offset(3, 12),
      };
      final canRing = widget.onBellTap != null &&
          player.id != widget.localPlayerId &&
          !player.isBot &&
          !player.isEliminated &&
          !widget.unavailableBellPlayerIds.contains(player.id);
      return Positioned(
        key: ValueKey('bell_${player.id}'),
        left: center.dx * tileSize - size / 2,
        top: center.dy * tileSize - size / 2,
        width: size,
        height: size,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: canRing ? () => widget.onBellTap!(player.color) : null,
            child: RotatedBox(
              // The board is rotated for the local player's perspective.
              // Counter-rotate the bell so its artwork stays upright.
              quarterTurns: (4 - widget.orientationQuarterTurns % 4) % 4,
              child: Image.asset(
                'assets/images/bell.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      );
    }).toList(growable: false);
  }

  List<Widget> _buildBellAlertText(double tileSize) {
    final alertColor = widget.alertedPlayerColor;
    if (alertColor == null) return const [];

    final anchor = switch (alertColor) {
      LudoColor.red => const Offset(3, 3),
      LudoColor.green => const Offset(12, 3),
      LudoColor.yellow => const Offset(12, 12),
      LudoColor.blue => const Offset(3, 12),
    };
    final textWidth = tileSize * 5.2;
    final textHeight = tileSize * 1.1;
    final isQuarterTurn = widget.orientationQuarterTurns.isOdd;
    // RotatedBox swaps its child's constraints. Swap the positioned bounds too,
    // so the upright text keeps its full width after the board rotates.
    final boundsWidth = isQuarterTurn ? textHeight : textWidth;
    final boundsHeight = isQuarterTurn ? textWidth : textHeight;
    final fontSize = tileSize < 30
        ? math.max(tileSize * 0.9, 18.0).toDouble()
        : tileSize * 0.62;

    return [
      Positioned(
        key: ValueKey('play_fast_${alertColor.name}'),
        left: anchor.dx * tileSize - boundsWidth / 2,
        top: anchor.dy * tileSize - boundsHeight / 2,
        width: boundsWidth,
        height: boundsHeight,
        child: AnimatedBuilder(
          animation: _bellAlertController,
          builder: (context, child) => Opacity(
            opacity: 0.05 + _bellAlertController.value * 0.95,
            child: Transform.scale(
              scale: 0.9 + _bellAlertController.value * 0.1,
              child: child,
            ),
          ),
          child: RotatedBox(
            // Keep the alert label readable after the board's perspective
            // rotation, like the player nameplates.
            quarterTurns: (4 - widget.orientationQuarterTurns % 4) % 4,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'PLAY FAST',
                maxLines: 1,
                style: TextStyle(
                  color: Colors.black,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  /// Renders 3D Golden Crowns and Large Rank Numbers (1, 2, 3) in Yard when a player finishes
  List<Widget> _buildFinishedPlayerCrowns(double tileSize) {
    return widget.gameState.players
        .where((player) =>
            player.rank > 0 && player.rank <= 3 && !player.isEliminated)
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
                      Shadow(
                          color: Colors.black87,
                          blurRadius: 12,
                          offset: Offset(0, 4)),
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
                    errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.exit_to_app_rounded,
                        color: Colors.red,
                        size: 48),
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
        final key = '${pawn.color.name}_${pawn.id}';
        if (pawn.isFinished) {
          final size = tileSize * 0.58;
          final (x, y) = switch (pawn.color) {
            LudoColor.red => (6.08, 6.12 + pawn.id * 0.67),
            LudoColor.green => (6.12 + pawn.id * 0.67, 6.08),
            LudoColor.yellow => (8.34, 6.12 + pawn.id * 0.67),
            LudoColor.blue => (6.12 + pawn.id * 0.67, 8.34),
          };
          widgets.add(
            Positioned(
              key: ValueKey('finished_$key'),
              left: x * tileSize,
              top: y * tileSize,
              width: size,
              height: size,
              child: _PawnTileWidget(
                color: pawn.color,
                isMovable: false,
                isPaired: pawn.isPaired,
                isPairSelected: false,
                size: size,
                orientationQuarterTurns: widget.orientationQuarterTurns,
              ),
            ),
          );
          continue;
        }

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
                final int currentIdx =
                    progress.floor().clamp(0, totalSteps - 1);
                final int nextIdx = (currentIdx + 1).clamp(0, totalSteps);
                final double stepProgress = progress - currentIdx;

                final posA = path[currentIdx];
                final posB = path[nextIdx];

                final double posX = posA.x + (posB.x - posA.x) * stepProgress;
                final double posY = posA.y + (posB.y - posA.y) * stepProgress;

                final double bounceFactor = math.sin(stepProgress * math.pi);
                final double pawnScale = 0.82 + (0.24 * bounceFactor);

                final size = tileSize * pawnScale;
                final left =
                    (posX * tileSize) + (tileSize * (1.0 - pawnScale) / 2);
                final top =
                    (posY * tileSize) + (tileSize * (1.0 - pawnScale) / 2);

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
                    orientationQuarterTurns: widget.orientationQuarterTurns,
                  ),
                );
              },
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
                  widget.gameState.legalMovablePawns
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

      // Keep movable pawns on top if their tap regions ever share a boundary.
      occupantList.sort((a, b) =>
          (a['isMovable'] as bool ? 1 : 0) - (b['isMovable'] as bool ? 1 : 0));

      for (int i = 0; i < totalOnTile; i++) {
        final item = occupantList[i];
        final PawnModel pawn = item['pawn'];
        final BoardPosition pos = item['pos'];
        final bool isMovable = item['isMovable'];

        // Divide occupied tiles into separate hit regions. Two pawns sit side
        // by side; larger stacks use a 2x2 layout so each pawn can be tapped.
        final splitPairsVertically = widget.orientationQuarterTurns.isOdd;
        final columns =
            totalOnTile == 1 || (totalOnTile == 2 && splitPairsVertically)
                ? 1
                : 2;
        final rows = totalOnTile == 1
            ? 1
            : totalOnTile == 2
                ? (splitPairsVertically ? 2 : 1)
                : 2;
        final column = totalOnTile == 1 ? 0 : i % columns;
        final row = i ~/ columns;
        final hitWidth = tileSize / columns;
        final hitHeight = tileSize / rows;
        final pawnScale = totalOnTile == 1
            ? 0.82
            : totalOnTile == 2
                ? 0.76
                : 0.50;
        final size = tileSize * pawnScale;
        final left = pos.x * tileSize + column * hitWidth;
        final top = pos.y * tileSize + row * hitHeight;

        widgets.add(
          Positioned(
            key: ValueKey('static_${pawn.color.name}_${pawn.id}'),
            left: left,
            top: top,
            width: hitWidth,
            height: hitHeight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                // If pawn is eligible for pair creation or selection, toggle pair selection
                if (!pawn.isPaired &&
                    pawn.isOnBoard &&
                    widget.onPairPawnTap != null) {
                  final sameTileUnpaired = widget.gameState.currentPlayer.pawns
                      .where((p) =>
                          p.id != pawn.id &&
                          !p.isPaired &&
                          p.stepCount == pawn.stepCount);
                  if (sameTileUnpaired.isNotEmpty || pawn.isPairSelected) {
                    widget.onPairPawnTap!(pawn);
                    return;
                  }
                }
                if (isMovable) {
                  widget.onPawnTap(pawn);
                }
              },
              child: Center(
                child: OverflowBox(
                  minWidth: size,
                  maxWidth: size,
                  minHeight: size,
                  maxHeight: size,
                  child: _PawnTileWidget(
                    color: pawn.color,
                    isMovable: isMovable,
                    isPaired: pawn.isPaired,
                    isPairSelected: pawn.isPairSelected,
                    size: size,
                    orientationQuarterTurns: widget.orientationQuarterTurns,
                  ),
                ),
              ),
            ),
          ),
        );
      }
    });

    return widgets;
  }
}

/// Pawn image with selection and paired-state overlays.
class _PawnTileWidget extends StatelessWidget {
  final LudoColor color;
  final bool isMovable;
  final bool isPaired;
  final bool isPairSelected;
  final double size;
  final int orientationQuarterTurns;

  const _PawnTileWidget({
    required this.color,
    required this.isMovable,
    this.isPaired = false,
    this.isPairSelected = false,
    required this.size,
    required this.orientationQuarterTurns,
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

        Transform.rotate(
          // The board rotates into the active player's perspective. Counter-
          // rotate the pawn artwork so each piece remains upright on screen.
          angle: ((4 - orientationQuarterTurns % 4) % 4) * math.pi / 2,
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                LudoPawnIcon(
                  color: color,
                  size: size,
                  width: size * 0.52,
                  height: size,
                ),
                if (isPaired)
                  Positioned(
                    right: size * 0.08,
                    bottom: size * 0.08,
                    child: Container(
                      width: size * 0.34,
                      height: size * 0.34,
                      decoration: BoxDecoration(
                        color: AppColors.gold,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: size * 0.035,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.45),
                            blurRadius: size * 0.08,
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.link_rounded,
                        color: Colors.white,
                        size: size * 0.23,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Fire/Flame animation painter rendered at the captured pawn's tile.
class _CaptureFlamePainterWidget extends StatelessWidget {
  final Color color;
  final double progress;

  const _CaptureFlamePainterWidget({
    required this.color,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: const Size(64, 80),
        painter: _CaptureFlamePainter(color: color, progress: progress),
      );
}

class _CaptureFlamePainter extends CustomPainter {
  final Color color;
  final double progress;

  _CaptureFlamePainter({required this.color, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final baseY = size.height * 0.85;

    final scale = progress < 0.3
        ? (progress / 0.3)
        : 1.0 - ((progress - 0.3) / 0.7) * 0.3;
    final opacity = (1.0 - progress).clamp(0.0, 1.0);

    final flameHeight = size.height * 0.85 * scale;
    final flameWidth = size.width * 0.75 * scale;

    // 1. Fiery Shockwave Ring at tile base
    final shockwaveRadius = size.width * (0.2 + progress * 0.6);
    final shockwavePaint = Paint()
      ..color = const Color(0xFFFF3D00)
          .withValues(alpha: (0.8 * opacity).clamp(0.0, 1.0))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0 * (1.0 - progress)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(Offset(centerX, baseY), shockwaveRadius, shockwavePaint);

    // 2. Outer Fire Glow
    final glowPaint = Paint()
      ..color = color.withValues(alpha: (0.5 * opacity).clamp(0.0, 1.0))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(Offset(centerX, baseY - flameHeight * 0.4),
        flameWidth * 0.7, glowPaint);

    // 3. Main Outer Flame Path (Fiery Orange/Red)
    final outerFlame = Path()
      ..moveTo(centerX, baseY - flameHeight)
      ..cubicTo(
        centerX + flameWidth * 0.6,
        baseY - flameHeight * 0.6,
        centerX + flameWidth * 0.5,
        baseY,
        centerX,
        baseY,
      )
      ..cubicTo(
        centerX - flameWidth * 0.5,
        baseY,
        centerX - flameWidth * 0.6,
        baseY - flameHeight * 0.6,
        centerX,
        baseY - flameHeight,
      );

    final outerFlamePaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, 0.3),
        radius: 0.8,
        colors: [
          const Color(0xFFFFD600),
          const Color(0xFFFF6D00),
          const Color(0xFFDD2C00),
          Colors.transparent,
        ],
        stops: const [0.0, 0.4, 0.8, 1.0],
      ).createShader(Rect.fromLTWH(
        centerX - flameWidth,
        baseY - flameHeight,
        flameWidth * 2,
        flameHeight,
      ))
      ..style = PaintingStyle.fill;
    canvas.drawPath(outerFlame, outerFlamePaint);

    // 4. Inner Fiery Yellow Core Flame
    final innerFlameHeight = flameHeight * 0.65;
    final innerFlameWidth = flameWidth * 0.55;
    final innerFlame = Path()
      ..moveTo(centerX, baseY - innerFlameHeight)
      ..cubicTo(
        centerX + innerFlameWidth * 0.6,
        baseY - innerFlameHeight * 0.5,
        centerX + innerFlameWidth * 0.4,
        baseY,
        centerX,
        baseY,
      )
      ..cubicTo(
        centerX - innerFlameWidth * 0.4,
        baseY,
        centerX - innerFlameWidth * 0.6,
        baseY - innerFlameHeight * 0.5,
        centerX,
        baseY - innerFlameHeight,
      );

    final innerFlamePaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFFFFFFF), Color(0xFFFFEA00), Color(0xFFFF6D00)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(
        centerX - innerFlameWidth,
        baseY - innerFlameHeight,
        innerFlameWidth * 2,
        innerFlameHeight,
      ))
      ..style = PaintingStyle.fill;
    canvas.drawPath(innerFlame, innerFlamePaint);

    // 5. Flying Flame & Rising Black Smoke Clouds
    final smokePaint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < 6; i++) {
      final smokeT = ((progress - i * 0.1) / 0.8).clamp(0.0, 1.0);
      if (smokeT <= 0.0) continue;

      final smokeX = centerX +
          (math.sin(smokeT * math.pi * 3 + i * 1.5) * flameWidth * 0.5);
      final smokeY = baseY - flameHeight * 0.5 - (smokeT * flameHeight * 1.2);
      final smokeRadius = (size.width * 0.14) + (smokeT * size.width * 0.22);
      final smokeOpacity =
          (math.sin(smokeT * math.pi) * 0.7 * opacity).clamp(0.0, 1.0);

      smokePaint
        ..color = Color.lerp(
          const Color(0xFF2E2E2E),
          const Color(0xFF111111),
          smokeT,
        )!
            .withValues(alpha: smokeOpacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 5.0 + smokeT * 3.0);

      canvas.drawCircle(Offset(smokeX, smokeY), smokeRadius, smokePaint);
    }

    // 6. Rising Fiery Sparks & Embers
    final sparkPaint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < 8; i++) {
      final sparkT = (progress + i * 0.12) % 1.0;
      final sparkX =
          centerX + (math.sin(sparkT * math.pi * 5 + i) * flameWidth * 0.45);
      final sparkY = baseY - (sparkT * flameHeight * 1.5);
      final sparkSize = (1.0 - sparkT) * 3.5;

      sparkPaint.color = i % 2 == 0
          ? const Color(0xFFFFEA00)
              .withValues(alpha: ((1.0 - sparkT) * opacity).clamp(0.0, 1.0))
          : const Color(0xFFFF3D00)
              .withValues(alpha: ((1.0 - sparkT) * opacity).clamp(0.0, 1.0));

      canvas.drawCircle(Offset(sparkX, sparkY), sparkSize, sparkPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CaptureFlamePainter old) =>
      old.progress != progress || old.color != color;
}

/// Commercial Grade Custom Painter for Ludo World Free Board
class _LudoBoardPainter extends CustomPainter {
  final GameState gameState;

  _LudoBoardPainter({required this.gameState});

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

      // Draw Colored Visual Start Markers & Arrows on actual entry indices (1, 14, 27, 40)
      if (i == LudoColor.red.actualEntryTrackIndex) {
        canvas.drawRRect(rrect, redGradient);
        _drawStartArrow(canvas, rect, LudoColor.red, tileSize);
      } else if (i == LudoColor.green.actualEntryTrackIndex) {
        canvas.drawRRect(rrect, greenGradient);
        _drawStartArrow(canvas, rect, LudoColor.green, tileSize);
      } else if (i == LudoColor.yellow.actualEntryTrackIndex) {
        canvas.drawRRect(rrect, yellowGradient);
        _drawStartArrow(canvas, rect, LudoColor.yellow, tileSize);
      } else if (i == LudoColor.blue.actualEntryTrackIndex) {
        canvas.drawRRect(rrect, blueGradient);
        _drawStartArrow(canvas, rect, LudoColor.blue, tileSize);
      } else {
        canvas.drawRRect(rrect, whitePaint);
      }

      canvas.drawRRect(rrect, gridLinePaint);

      // Draw Outlined 5-Point Safe Stars ONLY on shared arm safe tiles (9, 22, 35, 48)
      if (GameEngine.sharedSafeTiles.contains(i)) {
        _drawSafeStar(canvas, rect.center, tileSize * 0.35);
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
    canvas.drawRRect(
      yardRect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.75, -0.85),
          radius: 1.35,
          colors: [
            Colors.white.withValues(alpha: 0.34),
            Colors.white.withValues(alpha: 0.04),
            Colors.black.withValues(alpha: 0.10),
          ],
          stops: const [0, 0.48, 1],
        ).createShader(yardRect.outerRect),
    );

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

    final whitePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFFFFF), Color(0xFFF5F8FF), Color(0xFFE8EDF6)],
      ).createShader(innerRect.outerRect);
    canvas.drawRRect(innerRect, whitePaint);
    canvas.drawRRect(
      innerRect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.72)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );

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

  void _drawStartArrow(
      Canvas canvas, Rect tileRect, LudoColor color, double tileSize) {
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
    return oldDelegate.gameState != gameState;
  }
}
