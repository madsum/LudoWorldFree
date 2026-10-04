import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../domain/models/game_state.dart';
import '../../domain/models/player_model.dart';

class PlayerInfoCard extends StatefulWidget {
  final PlayerModel player;
  final GameState gameState;
  final bool isCurrentTurn;
  final VoidCallback onRoll;
  final bool showName;

  const PlayerInfoCard({
    super.key,
    required this.player,
    required this.gameState,
    required this.isCurrentTurn,
    required this.onRoll,
    this.showName = true,
  });

  @override
  State<PlayerInfoCard> createState() => _PlayerInfoCardState();
}

class _PlayerInfoCardState extends State<PlayerInfoCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turnPulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant PlayerInfoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isCurrentTurn != widget.isCurrentTurn ||
        oldWidget.gameState.isGameOver != widget.gameState.isGameOver) {
      _syncPulse();
    }
  }

  void _syncPulse() {
    if (widget.isCurrentTurn && !widget.gameState.isGameOver) {
      _turnPulse.repeat(reverse: true);
    } else {
      _turnPulse.stop();
      _turnPulse.value = 0;
    }
  }

  @override
  void dispose() {
    _turnPulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRolling = widget.isCurrentTurn && widget.gameState.isDiceRolling;
    final canRoll = widget.isCurrentTurn &&
        !widget.player.isBot &&
        widget.gameState.turnPhase == GameTurnPhase.rollDice &&
        !widget.gameState.isGameOver;

    return AnimatedBuilder(
      animation: _turnPulse,
      builder: (context, _) {
        final pulse = _turnPulse.value;
        return Transform.scale(
          scale: widget.isCurrentTurn ? 1 + pulse * 0.012 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.bgNavy,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: widget.isCurrentTurn
                    ? AppColors.gold
                    : widget.player.color.color,
                width: widget.isCurrentTurn ? 2.5 : 1.5,
              ),
              boxShadow: [
                if (widget.isCurrentTurn)
                  BoxShadow(
                    color:
                        AppColors.gold.withValues(alpha: 0.30 + pulse * 0.16),
                    blurRadius: 8 + pulse * 4,
                    spreadRadius: 0.5 + pulse * 0.8,
                  ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    color: widget.player.color.color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.showName)
                        Text(
                          widget.player.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      Text(
                        'Home: ${widget.player.finishedPawnsCount}/4',
                        style: GoogleFonts.poppins(
                          fontSize: 9,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 7),
                _PlayerDie(
                  value: widget.gameState.playerDiceValues[widget.player.id],
                  isRolling: isRolling,
                  isActive: widget.isCurrentTurn &&
                      widget.gameState.turnPhase == GameTurnPhase.rollDice &&
                      !widget.gameState.isGameOver,
                  canRoll: canRoll,
                  color: widget.player.color.color,
                  onTap: widget.onRoll,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PlayerDie extends StatefulWidget {
  final int? value;
  final bool isRolling;
  final bool isActive;
  final bool canRoll;
  final Color color;
  final VoidCallback onTap;

  const _PlayerDie({
    required this.value,
    required this.isRolling,
    required this.isActive,
    required this.canRoll,
    required this.color,
    required this.onTap,
  });

  @override
  State<_PlayerDie> createState() => _PlayerDieState();
}

class _PlayerDieState extends State<_PlayerDie>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rollController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  @override
  void initState() {
    super.initState();
    _syncRolling();
  }

  @override
  void didUpdateWidget(covariant _PlayerDie oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isRolling != widget.isRolling) _syncRolling();
  }

  void _syncRolling() {
    if (widget.isRolling) {
      _rollController.forward(from: 0);
    } else {
      _rollController.stop();
      _rollController.value = 0;
    }
  }

  @override
  void dispose() {
    _rollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.canRoll ? widget.onTap : null,
      child: AnimatedBuilder(
        animation: _rollController,
        builder: (context, _) {
          final value = widget.isRolling
              ? (_rollController.value * 6).floor().clamp(0, 5).toInt() + 1
              : widget.value;
          final rollPhase = _rollController.value;
          final hopHeight =
              widget.isRolling ? math.sin(rollPhase * math.pi) * 18 : 0.0;
          final rotationX = widget.isRolling
              ? rollPhase * math.pi * 4 +
                  math.sin(rollPhase * math.pi * 4) * 0.22
              : 0.0;
          final rotationY = widget.isRolling
              ? rollPhase * math.pi * 5 +
                  math.sin(rollPhase * math.pi * 3) * 0.18
              : 0.0;
          final rotationZ = widget.isRolling ? rollPhase * math.pi * 4 : 0.0;
          final landingSquash = widget.isRolling && rollPhase > 0.82
              ? 1 - math.sin((rollPhase - 0.82) / 0.18 * math.pi) * 0.08
              : 1.0;

          return Transform.translate(
            offset: Offset(0, -hopHeight),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.004)
                ..rotateX(rotationX)
                ..rotateY(rotationY)
                ..rotateZ(rotationZ),
              child: Transform.scale(
                scale: (1 + hopHeight / 180) * landingSquash,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 38,
                  height: 38,
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white,
                        Color(0xFFF4F6FA),
                        Color(0xFFD5DBE5)
                      ],
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: widget.isActive || widget.isRolling
                          ? const Color(0xFFFFE28A)
                          : Colors.white,
                      width: widget.isActive || widget.isRolling ? 1.7 : 1.2,
                    ),
                    boxShadow: [
                      const BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 4,
                        offset: Offset(1.5, 2.5),
                      ),
                      if (widget.isRolling || widget.isActive)
                        BoxShadow(
                          color: AppColors.gold.withValues(
                            alpha: widget.isRolling ? 0.65 : 0.32,
                          ),
                          blurRadius: widget.isRolling ? 11 : 7,
                          spreadRadius: widget.isRolling ? 1.5 : 0.5,
                        ),
                    ],
                  ),
                  child: value == null
                      ? Icon(Icons.casino_rounded,
                          color: widget.color, size: 24)
                      : _DicePips(value: value),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DicePips extends StatelessWidget {
  final int value;

  const _DicePips({required this.value});

  static const _pipPositions = <Alignment>[
    Alignment(-0.72, -0.72),
    Alignment(0.72, -0.72),
    Alignment(-0.72, 0),
    Alignment(0.72, 0),
    Alignment(-0.72, 0.72),
    Alignment(0.72, 0.72),
    Alignment(0, 0),
  ];

  static const _visiblePips = <int, List<int>>{
    1: [6],
    2: [0, 5],
    3: [0, 6, 5],
    4: [0, 1, 4, 5],
    5: [0, 1, 4, 5, 6],
    6: [0, 1, 2, 3, 4, 5],
  };

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (final index in _visiblePips[value]!)
          Align(
            alignment: _pipPositions[index],
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                gradient: const RadialGradient(
                  center: Alignment(-0.3, -0.35),
                  colors: [Color(0xFF536174), Color(0xFF101827)],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 1,
                    offset: const Offset(0.5, 0.7),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
