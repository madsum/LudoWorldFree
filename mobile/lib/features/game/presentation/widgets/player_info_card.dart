import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../domain/models/game_state.dart';
import '../../domain/models/ludo_color.dart';
import '../../domain/models/player_model.dart';
import '../controllers/game_controller.dart';
import 'ludo_pawn_icon.dart';

class PlayerInfoCard extends StatefulWidget {
  final PlayerModel player;
  final GameState gameState;
  final bool isCurrentTurn;
  final VoidCallback onRoll;
  final bool twoPlayerLayout;
  final bool compact;
  final bool showRollArrow;
  final bool rollArrowPointsLeft;

  const PlayerInfoCard({
    super.key,
    required this.player,
    required this.gameState,
    required this.isCurrentTurn,
    required this.onRoll,
    this.twoPlayerLayout = false,
    this.compact = false,
    this.showRollArrow = false,
    this.rollArrowPointsLeft = false,
  });

  @override
  State<PlayerInfoCard> createState() => _PlayerInfoCardState();
}

class _PlayerInfoCardState extends State<PlayerInfoCard>
    with TickerProviderStateMixin {
  late final AnimationController _turnPulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );
  late final AnimationController _turnCountdown = AnimationController(
    vsync: this,
    duration: GameNotifier.turnDuration,
  );
  late final Listenable _animations =
      Listenable.merge([_turnPulse, _turnCountdown]);

  @override
  void initState() {
    super.initState();
    _syncPulse();
    _syncCountdown(reset: true);
  }

  @override
  void didUpdateWidget(covariant PlayerInfoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isCurrentTurn != widget.isCurrentTurn ||
        oldWidget.gameState.isGameOver != widget.gameState.isGameOver ||
        oldWidget.gameState.turnPhase != widget.gameState.turnPhase ||
        oldWidget.player.id != widget.player.id ||
        oldWidget.player.isEliminated != widget.player.isEliminated) {
      _syncPulse();
    }

    final opportunityChanged = oldWidget.gameState.rollOpportunityId !=
        widget.gameState.rollOpportunityId;
    final playerChanged = oldWidget.player.id != widget.player.id;
    final phaseChanged =
        oldWidget.gameState.turnPhase != widget.gameState.turnPhase;
    final pauseChanged =
        oldWidget.gameState.turnTimerPaused != widget.gameState.turnTimerPaused;
    if (opportunityChanged || playerChanged) {
      _syncCountdown(reset: true);
    } else if (pauseChanged) {
      _syncCountdown(reset: widget.gameState.turnTimerPaused);
    } else if (phaseChanged) {
      _syncCountdown(reset: _timerOpportunityActive);
    }
  }

  void _syncPulse() {
    if (widget.isCurrentTurn &&
        !widget.player.isEliminated &&
        !widget.gameState.isGameOver &&
        widget.gameState.turnPhase == GameTurnPhase.rollDice) {
      _turnPulse.repeat(reverse: true);
    } else {
      _turnPulse.stop();
      _turnPulse.value = 0;
    }
  }

  bool get _timerOpportunityActive =>
      widget.isCurrentTurn &&
      !widget.player.isBot &&
      !widget.player.isEliminated &&
      (widget.gameState.turnPhase == GameTurnPhase.rollDice ||
          (widget.gameState.turnPhase == GameTurnPhase.selectPawn &&
              widget.gameState.movablePawns.length > 1)) &&
      !widget.gameState.isGameOver;

  void _syncCountdown({bool reset = false}) {
    if (!_timerOpportunityActive) {
      _turnCountdown.stop(canceled: false);
      return;
    }
    if (widget.gameState.turnTimerPaused) {
      _turnCountdown.stop(canceled: false);
      return;
    }
    if (reset) {
      final fullDuration = GameNotifier.turnDuration.inMilliseconds;
      final remaining = widget.gameState.turnTimerRemainingMilliseconds;
      _turnCountdown.value = (1 - remaining / fullDuration).clamp(0.0, 1.0);
    }
    if (reset || _turnCountdown.status == AnimationStatus.dismissed) {
      _turnCountdown.forward();
    } else if (!_turnCountdown.isAnimating) {
      _turnCountdown.forward();
    }
  }

  @override
  void dispose() {
    _turnPulse.dispose();
    _turnCountdown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRolling = widget.isCurrentTurn && widget.gameState.isDiceRolling;
    final canRoll = widget.isCurrentTurn &&
        !widget.player.isBot &&
        !widget.player.isEliminated &&
        widget.gameState.turnPhase == GameTurnPhase.rollDice &&
        !widget.gameState.isGameOver;
    final cardWidth = widget.twoPlayerLayout
        ? double.infinity
        : math.min(184.0, (MediaQuery.sizeOf(context).width - 44) / 2);

    return AnimatedBuilder(
      animation: _animations,
      builder: (context, _) {
        final pulse = _turnPulse.value;
        final profileAccent = widget.isCurrentTurn
            ? const Color(0xFFFFF066)
            : widget.player.isEliminated
                ? Color.lerp(
                    widget.player.color.color,
                    const Color(0xFF10182B),
                    0.58,
                  )!
                : widget.player.color.color;
        final cardBorderColor = widget.isCurrentTurn
            ? Color.lerp(
                const Color(0xFF8A7A00),
                const Color(0xFFFFF066),
                pulse,
              )!
            : profileAccent;
        final avatarBorderColor = widget.isCurrentTurn
            ? Colors.white.withValues(alpha: 0.38)
            : profileAccent.withValues(alpha: 0.9);
        final timerVisible = _timerOpportunityActive;
        return Transform.scale(
          scale: widget.isCurrentTurn ? 1 + pulse * 0.012 : 1,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: cardWidth,
                padding: widget.twoPlayerLayout
                    ? const EdgeInsets.symmetric(horizontal: 6, vertical: 7)
                    : widget.compact
                        ? const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          )
                        : const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 4,
                          ),
                decoration: BoxDecoration(
                  color: AppColors.bgNavy.withValues(alpha: 0.97),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: cardBorderColor,
                    width: widget.isCurrentTurn ? 2.5 + pulse * 1.2 : 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: profileAccent.withValues(
                        alpha: widget.isCurrentTurn
                            ? 0.32 + pulse * 0.12
                            : widget.player.isEliminated
                                ? 0.07
                                : 0.16,
                      ),
                      blurRadius: widget.isCurrentTurn ? 9 + pulse * 3 : 5,
                      spreadRadius: widget.isCurrentTurn ? 0.6 : 0,
                    ),
                  ],
                ),
                child: widget.twoPlayerLayout
                    ? _buildTwoPlayerProfile(
                        avatarBorderColor: avatarBorderColor,
                        timerVisible: timerVisible,
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Text(
                                widget.player.countryFlag,
                                style: TextStyle(
                                  fontSize: widget.compact ? 9 : 11,
                                ),
                              ),
                              const SizedBox(width: 2),
                              Expanded(
                                child: Text(
                                  widget.player.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.poppins(
                                    fontSize: widget.compact ? 7 : 8,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.diamond_rounded,
                                color: AppColors.diamondBlue,
                                size: widget.compact ? 9 : 10,
                              ),
                              const SizedBox(width: 1),
                              Text(
                                _formatBalance(widget.player.diamonds),
                                style: GoogleFonts.poppins(
                                  fontSize: widget.compact ? 6 : 7,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.monetization_on_rounded,
                                color: AppColors.coinGold,
                                size: widget.compact ? 9 : 11,
                              ),
                              const SizedBox(width: 1),
                              Text(
                                _formatBalance(widget.player.coins),
                                maxLines: 1,
                                style: GoogleFonts.poppins(
                                  fontSize: widget.compact ? 6 : 7,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: widget.compact ? 1 : 2),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CustomPaint(
                                      foregroundPainter: timerVisible
                                          ? _TurnTimerBorderPainter(
                                              1 - _turnCountdown.value,
                                            )
                                          : null,
                                      child: Container(
                                        width: widget.compact ? 32 : 40,
                                        height: widget.compact ? 28 : 35,
                                        decoration: BoxDecoration(
                                          color: AppColors.bgCard,
                                          borderRadius:
                                              BorderRadius.circular(7),
                                          border: Border.all(
                                            color: avatarBorderColor,
                                            width: 1.5,
                                          ),
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: _buildAvatar(),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 3),
                              const SizedBox(width: 3),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _PlayerDie(
                                    value: widget.gameState
                                        .playerDiceValues[widget.player.id],
                                    isRolling: isRolling,
                                    isActive: widget.isCurrentTurn &&
                                        widget.gameState.turnPhase ==
                                            GameTurnPhase.rollDice &&
                                        !widget.gameState.isGameOver,
                                    canRoll: canRoll,
                                    color: widget.player.color.color,
                                    size: widget.compact ? 28 : 34,
                                    onTap: widget.onRoll,
                                  ),
                                ],
                              ),
                              if (_opponentColors.isNotEmpty) ...[
                                const SizedBox(width: 4),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    for (var index = 0;
                                        index < _opponentColors.length;
                                        index++) ...[
                                      if (index > 0) const SizedBox(width: 2),
                                      _OpponentKillStat(
                                        color: _opponentColors[index],
                                        count: widget.player.killCounts[
                                                _opponentColors[index]] ??
                                            0,
                                        compact: widget.compact,
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
              ),
              if (widget.showRollArrow && timerVisible)
                Positioned(
                  left: widget.rollArrowPointsLeft ? null : -30,
                  right: widget.rollArrowPointsLeft ? -30 : null,
                  top: 0,
                  bottom: 0,
                  width: 36,
                  child: Center(
                    child: Opacity(
                      opacity: 0.35 + pulse * 0.65,
                      child: Transform.translate(
                        offset: Offset(
                          widget.rollArrowPointsLeft ? -pulse * 4 : pulse * 4,
                          0,
                        ),
                        child: Icon(
                          widget.rollArrowPointsLeft
                              ? Icons.arrow_back_rounded
                              : Icons.arrow_forward_rounded,
                          color: widget.player.color.color,
                          size: 34,
                          shadows: [
                            Shadow(
                              color: widget.player.color.color,
                              blurRadius: 12,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTwoPlayerProfile({
    required Color avatarBorderColor,
    required bool timerVisible,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(widget.player.countryFlag,
                style: const TextStyle(fontSize: 11)),
            const SizedBox(width: 2),
            Expanded(
              child: Text(
                widget.player.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            const Icon(Icons.diamond_rounded,
                color: AppColors.diamondBlue, size: 10),
            const SizedBox(width: 1),
            Text(
              _formatBalance(widget.player.diamonds),
              maxLines: 1,
              style: GoogleFonts.poppins(
                fontSize: 7,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.monetization_on_rounded,
                color: AppColors.coinGold, size: 11),
            const SizedBox(width: 1),
            Text(
              _formatBalance(widget.player.coins),
              maxLines: 1,
              style: GoogleFonts.poppins(
                fontSize: 7,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CustomPaint(
              foregroundPainter: timerVisible
                  ? _TurnTimerBorderPainter(1 - _turnCountdown.value)
                  : null,
              child: Container(
                width: 40,
                height: 35,
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: avatarBorderColor,
                    width: 1.5,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: _buildAvatar(),
              ),
            ),
            const SizedBox(width: 3),
            if (_opponentColors.isNotEmpty) ...[
              const SizedBox(width: 4),
              for (var index = 0; index < _opponentColors.length; index++) ...[
                if (index > 0) const SizedBox(width: 3),
                _OpponentKillStat(
                  color: _opponentColors[index],
                  count: widget.player.killCounts[_opponentColors[index]] ?? 0,
                  compact: widget.compact,
                ),
              ],
            ],
          ],
        ),
      ],
    );
  }

  String _formatBalance(int value) {
    final digits = value.toString();
    final grouped = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
      grouped.write(digits[i]);
    }
    return grouped.toString();
  }

  Widget _buildAvatar() {
    final avatarUrl = widget.player.avatarUrl;
    if (avatarUrl == null || avatarUrl.isEmpty) {
      return Icon(
        widget.player.isBot ? Icons.smart_toy_rounded : Icons.person_rounded,
        color: Colors.white70,
        size: 23,
      );
    }
    if (avatarUrl.startsWith('http')) {
      return Image.network(
        avatarUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.person_rounded, color: Colors.white70, size: 23),
      );
    }
    if (avatarUrl.startsWith('assets/') || avatarUrl.endsWith('.webp')) {
      return Image.asset(
        avatarUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.person_rounded, color: Colors.white70, size: 23),
      );
    }
    return Icon(
      widget.player.isBot ? Icons.smart_toy_rounded : Icons.person_rounded,
      color: Colors.white70,
      size: 23,
    );
  }

  List<LudoColor> get _opponentColors => widget.gameState.players
      .map((player) => player.color)
      .where((color) => color != widget.player.color)
      .toSet()
      .toList(growable: false);
}

class SharedDiceButton extends StatelessWidget {
  final GameState gameState;
  final VoidCallback onRoll;

  const SharedDiceButton({
    super.key,
    required this.gameState,
    required this.onRoll,
  });

  @override
  Widget build(BuildContext context) {
    final canRoll = !gameState.isCurrentPlayerBot &&
        !gameState.currentPlayer.isEliminated &&
        gameState.turnPhase == GameTurnPhase.rollDice &&
        !gameState.isGameOver;
    final isActive = gameState.turnPhase == GameTurnPhase.rollDice &&
        !gameState.currentPlayer.isEliminated &&
        !gameState.isGameOver;

    return _PlayerDie(
      value: gameState.diceValue,
      isRolling: gameState.isDiceRolling,
      isActive: isActive,
      canRoll: canRoll,
      color: gameState.currentPlayer.color.color,
      size: 56,
      onTap: onRoll,
    );
  }
}

class _OpponentKillStat extends StatelessWidget {
  final LudoColor color;
  final int count;
  final bool compact;

  const _OpponentKillStat({
    required this.color,
    required this.count,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) => Semantics(
        label: '${color.displayName} tokens killed: $count',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LudoPawnIcon(color: color, size: compact ? 9 : 12),
            SizedBox(width: compact ? 0.5 : 1),
            Icon(
              Icons.close_rounded,
              color: const Color(0xFFFF655F),
              size: compact ? 7 : 9,
            ),
            SizedBox(width: compact ? 0.5 : 1),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: animation, child: child),
              ),
              child: Text(
                '$count',
                key: ValueKey(count),
                style: GoogleFonts.poppins(
                  fontSize: compact ? 6 : 8,
                  height: 1.1,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
}

class _PlayerDie extends StatefulWidget {
  final int? value;
  final bool isRolling;
  final bool isActive;
  final bool canRoll;
  final Color color;
  final double size;
  final VoidCallback onTap;

  const _PlayerDie({
    required this.value,
    required this.isRolling,
    required this.isActive,
    required this.canRoll,
    required this.color,
    this.size = 34,
    required this.onTap,
  });

  @override
  State<_PlayerDie> createState() => _PlayerDieState();
}

class _PlayerDieState extends State<_PlayerDie> with TickerProviderStateMixin {
  late final AnimationController _rollController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  late final AnimationController _flashController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );
  late final Listenable _animations =
      Listenable.merge([_rollController, _flashController]);

  @override
  void initState() {
    super.initState();
    _syncRolling();
    _syncFlashing();
  }

  @override
  void didUpdateWidget(covariant _PlayerDie oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isRolling != widget.isRolling) _syncRolling();
    if (oldWidget.canRoll != widget.canRoll ||
        oldWidget.isRolling != widget.isRolling) {
      _syncFlashing();
    }
  }

  void _syncRolling() {
    if (widget.isRolling) {
      _rollController.forward(from: 0);
    } else {
      _rollController.stop();
      _rollController.value = 0;
    }
  }

  void _syncFlashing() {
    if (widget.canRoll && !widget.isRolling) {
      _flashController.repeat(reverse: true);
    } else {
      _flashController.stop();
      _flashController.value = 0;
    }
  }

  @override
  void dispose() {
    _rollController.dispose();
    _flashController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.canRoll ? widget.onTap : null,
      child: AnimatedBuilder(
        animation: _animations,
        builder: (context, _) {
          final flashPhase = _flashController.value;
          final value = widget.isRolling
              ? (_rollController.value * 6).floor().clamp(0, 5).toInt() + 1
              : widget.value;
          final rollPhase = _rollController.value;
          final hopHeight = widget.isRolling
              ? math.sin(rollPhase * math.pi) * widget.size * 0.32
              : 0.0;
          final rotationX = widget.isRolling
              ? rollPhase * math.pi * 4 +
                  math.sin(rollPhase * math.pi * 4) * 0.22
              : -0.08;
          final rotationY = widget.isRolling
              ? rollPhase * math.pi * 5 +
                  math.sin(rollPhase * math.pi * 3) * 0.18
              : 0.08;
          final rotationZ = widget.isRolling ? rollPhase * math.pi * 4 : -0.035;
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
                scale: (1 + hopHeight / 180) *
                    landingSquash *
                    (widget.canRoll ? 1 + flashPhase * 0.07 : 1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: widget.size,
                  height: widget.size,
                  padding: EdgeInsets.all(widget.size * 0.12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white,
                        Color(0xFFF9FBFF),
                        Color(0xFFE5EBF3),
                        Color(0xFFB8C3D2),
                      ],
                      stops: [0, 0.32, 0.76, 1],
                    ),
                    borderRadius: BorderRadius.circular(widget.size * 0.26),
                    border: Border.all(
                      color: widget.isActive || widget.isRolling
                          ? Color.lerp(
                              const Color(0xFFFFE28A),
                              Colors.white,
                              widget.canRoll ? flashPhase : 0,
                            )!
                          : Colors.white,
                      width: widget.isActive || widget.isRolling
                          ? (widget.canRoll ? 1.5 + flashPhase * 1.7 : 1.7)
                          : 1.2,
                    ),
                    boxShadow: [
                      const BoxShadow(
                        color: Color(0x77000000),
                        blurRadius: 7,
                        offset: Offset(1.5, 3),
                      ),
                      const BoxShadow(
                        color: Color(0xCCFFFFFF),
                        blurRadius: 2,
                        offset: Offset(-1, -1),
                      ),
                      if (widget.isRolling || widget.isActive)
                        BoxShadow(
                          color: AppColors.gold.withValues(
                            alpha: widget.isRolling
                                ? 0.65
                                : widget.canRoll
                                    ? 0.25 + flashPhase * 0.60
                                    : 0.32,
                          ),
                          blurRadius: widget.isRolling
                              ? 11
                              : widget.canRoll
                                  ? 5 + flashPhase * 12
                                  : 7,
                          spreadRadius: widget.isRolling
                              ? 1.5
                              : widget.canRoll
                                  ? 0.5 + flashPhase * 2.5
                                  : 0.5,
                        ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        left: widget.size * 0.09,
                        top: widget.size * 0.06,
                        width: widget.size * 0.62,
                        height: widget.size * 0.24,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.white.withValues(alpha: 0.88),
                                  Colors.white.withValues(alpha: 0.12),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Center(
                        child: value == null
                            ? Icon(Icons.casino_rounded,
                                color: widget.color, size: widget.size * 0.70)
                            : _DicePips(value: value, size: widget.size),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TurnTimerBorderPainter extends CustomPainter {
  final double progress;

  const _TurnTimerBorderPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final remaining = progress.clamp(0.0, 1.0);
    final warning = ((0.5 - remaining) / 0.5).clamp(0.0, 1.0);
    final color = Color.lerp(
      const Color(0xFF20C866),
      const Color(0xFFE53935),
      warning,
    )!;
    const strokeWidth = 5.0;
    final inset = strokeWidth / 2;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final border = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)));
    final metric = border.computeMetrics().first;
    final visibleBorder = metric.extractPath(0, metric.length * remaining);
    canvas.drawPath(
      visibleBorder,
      Paint()
        ..color = color.withValues(alpha: 0.48)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawPath(
      visibleBorder,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _TurnTimerBorderPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _DicePips extends StatelessWidget {
  final int value;
  final double size;

  const _DicePips({required this.value, required this.size});

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
              width: size * 0.16,
              height: size * 0.16,
              decoration: BoxDecoration(
                gradient: const RadialGradient(
                  center: Alignment(-0.42, -0.5),
                  colors: [
                    Color(0xFF8996A8),
                    Color(0xFF344154),
                    Color(0xFF0B111B),
                  ],
                  stops: [0, 0.42, 1],
                ),
                shape: BoxShape.circle,
                border: Border.fromBorderSide(
                  BorderSide(color: Colors.white54, width: 0.45),
                ),
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
