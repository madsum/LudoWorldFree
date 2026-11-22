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
  final bool rollArrowPointsUp;
  final bool showPlayerDot;
  final VoidCallback? onBuddyRequest;

  const PlayerInfoCard({
    super.key,
    required this.player,
    required this.gameState,
    required this.isCurrentTurn,
    required this.onRoll,
    this.twoPlayerLayout = false,
    this.compact = false,
    this.showRollArrow = false,
    this.rollArrowPointsUp = false,
    this.showPlayerDot = false,
    this.onBuddyRequest,
  });

  @override
  State<PlayerInfoCard> createState() => _PlayerInfoCardState();
}

class _PlayerInfoCardState extends State<PlayerInfoCard>
    with TickerProviderStateMixin {
  static const _turnHighlight = Color(0xFF00E5FF);

  late final AnimationController _turnPulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );
  late final AnimationController _turnCountdown = AnimationController(
    vsync: this,
    duration: _turnDuration,
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
        oldWidget.gameState.turnTimerDisabled !=
            widget.gameState.turnTimerDisabled ||
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
    final disabledChanged = oldWidget.gameState.turnTimerDisabled !=
        widget.gameState.turnTimerDisabled;
    if (opportunityChanged || playerChanged || disabledChanged) {
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
      widget.gameState.isLocalPlayerTurn &&
      !widget.player.isBot &&
      !widget.player.isEliminated &&
      (widget.gameState.turnPhase == GameTurnPhase.rollDice ||
          (widget.gameState.turnPhase == GameTurnPhase.selectPawn &&
              widget.gameState.legalMovablePawns.length > 1)) &&
      !widget.gameState.turnTimerDisabled &&
      !widget.gameState.isGameOver;

  Duration get _turnDuration => widget.gameState.localPlayerId == null
      ? GameNotifier.turnDuration
      : GameNotifier.onlineTurnDuration;

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
      final fullDuration = _turnDuration.inMilliseconds;
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

  String get _displayCountryName {
    final country = widget.player.country;
    if (country.isEmpty || country.contains('assets/images')) {
      return 'World';
    }
    return country;
  }

  Widget _buildFlagWidget(String flag, {double size = 12}) {
    if (flag == '🌐' ||
        flag == 'assets/images/world.png' ||
        flag.contains('world')) {
      return Image.asset(
        'assets/images/world.png',
        width: size * 1.2,
        height: size * 1.0,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) =>
            Text('🌐', style: TextStyle(fontSize: size)),
      );
    }
    return Text(flag, style: TextStyle(fontSize: size));
  }

  @override
  Widget build(BuildContext context) {
    final isRolling = widget.isCurrentTurn && widget.gameState.isDiceRolling;
    final canRoll = widget.isCurrentTurn &&
        widget.gameState.isLocalPlayerTurn &&
        !widget.player.isBot &&
        !widget.player.isEliminated &&
        widget.gameState.turnPhase == GameTurnPhase.rollDice &&
        !widget.gameState.isGameOver;
    final cardWidth = widget.twoPlayerLayout
        ? double.infinity
        : math.min(210.0, (MediaQuery.sizeOf(context).width - 32) / 2);

    return AnimatedBuilder(
      animation: _animations,
      builder: (context, _) {
        final pulse = _turnPulse.value;
        final profileAccent = widget.isCurrentTurn
            ? _turnHighlight
            : widget.player.isEliminated
                ? Color.lerp(
                    widget.player.color.color,
                    const Color(0xFF10182B),
                    0.58,
                  )!
                : widget.player.color.color;
        final cardBorderColor = widget.isCurrentTurn
            ? Color.lerp(
                const Color(0xFF820152),
                _turnHighlight,
                pulse,
              )!
            : profileAccent;
        final avatarBorderColor = widget.isCurrentTurn
            ? Colors.white.withValues(alpha: 0.38)
            : profileAccent.withValues(alpha: 0.9);
        final timerVisible = _timerOpportunityActive;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: canRoll ? widget.onRoll : null,
          child: Transform.scale(
            scale: widget.isCurrentTurn ? 1 + pulse * 0.012 : 1,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: cardWidth,
                  padding: widget.twoPlayerLayout
                      ? const EdgeInsets.symmetric(horizontal: 6, vertical: 5)
                      : widget.compact
                          ? const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 3,
                            )
                          : const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 5,
                            ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color.lerp(AppColors.bgNavy, cardBorderColor, 0.10)!,
                        AppColors.bgNavy,
                        const Color(0xFF10182D),
                      ],
                    ),
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
                            // Line 1: country and buddy action.
                            Row(
                              children: [
                                _buildFlagWidget(widget.player.countryFlag,
                                    size: widget.compact ? 10 : 12),
                                const SizedBox(width: 3),
                                Expanded(
                                  child: Text(
                                    _displayCountryName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.poppins(
                                      fontSize: widget.compact ? 8.5 : 10,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                if (widget.onBuddyRequest != null) ...[
                                  const SizedBox(width: 3),
                                  _buddySign(widget.compact ? 14 : 17),
                                ],
                              ],
                            ),
                            const SizedBox(height: 3),

                            // Line 2: player name and wallet balances.
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    widget.player.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.poppins(
                                      fontSize: widget.compact ? 8.5 : 10,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.diamond_rounded,
                                  color: AppColors.diamondBlue,
                                  size: widget.compact ? 10 : 12,
                                ),
                                const SizedBox(width: 1),
                                Text(
                                  _formatBalance(widget.player.diamonds),
                                  style: GoogleFonts.poppins(
                                    fontSize: widget.compact ? 7.5 : 8.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.monetization_on_rounded,
                                  color: AppColors.coinGold,
                                  size: widget.compact ? 10 : 12,
                                ),
                                const SizedBox(width: 1),
                                Text(
                                  _formatBalance(widget.player.coins),
                                  maxLines: 1,
                                  style: GoogleFonts.poppins(
                                    fontSize: widget.compact ? 7.5 : 8.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),

                            // Line 3: avatar, die, capture counts, and missed rolls.
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Profile Avatar Box
                                CustomPaint(
                                  foregroundPainter: timerVisible
                                      ? _TurnTimerBorderPainter(
                                          1 - _turnCountdown.value,
                                        )
                                      : null,
                                  child: Container(
                                    width: widget.compact ? 38 : 42,
                                    height: widget.compact ? 34 : 38,
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
                                const SizedBox(width: 4),

                                // Player Die
                                _PlayerDie(
                                  value: widget.isCurrentTurn
                                      ? widget.gameState.lastRolledDiceValue ??
                                          widget.gameState.diceValue ??
                                          widget.gameState.playerDiceValues[
                                              widget.player.id]
                                      : widget.gameState
                                          .playerDiceValues[widget.player.id],
                                  isRolling: isRolling,
                                  isActive: widget.isCurrentTurn &&
                                      widget.gameState.turnPhase ==
                                          GameTurnPhase.rollDice &&
                                      !widget.player.isEliminated &&
                                      !widget.gameState.isGameOver,
                                  canRoll: canRoll,
                                  playerColor: widget.player.color,
                                  size: widget.compact ? 24 : 28,
                                  onTap: widget.onRoll,
                                ),

                                // Opponent Killed Pawns Stats in the Same Line
                                if (_opponentColors.isNotEmpty) ...[
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      physics: const BouncingScrollPhysics(),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          for (var index = 0;
                                              index < _opponentColors.length;
                                              index++) ...[
                                            if (index > 0)
                                              const SizedBox(width: 3),
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
                                    ),
                                  ),
                                ],
                                const SizedBox(width: 4),
                                _MissedTurnDots(player: widget.player),
                              ],
                            ),
                          ],
                        ),
                ),
                if (widget.showRollArrow)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: widget.rollArrowPointsUp ? null : -42,
                    bottom: widget.rollArrowPointsUp ? -42 : null,
                    height: 42,
                    child: Center(
                      child: Transform.translate(
                        offset: Offset(
                          0,
                          (widget.rollArrowPointsUp ? -1 : 1) * pulse * 4,
                        ),
                        child: Opacity(
                          opacity: 0.15 + pulse * 0.85,
                          child: Icon(
                            widget.rollArrowPointsUp
                                ? Icons.arrow_upward_rounded
                                : Icons.arrow_downward_rounded,
                            color: Colors.white,
                            size: 38,
                            shadows: const [
                              Shadow(color: Colors.white, blurRadius: 12),
                              Shadow(color: Colors.white70, blurRadius: 5),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 2-Player Profile Card Layout
  /// First Line: Flag & Full Country Name
  /// Second line: player name and balances. Third line: avatar and captures.
  Widget _buildTwoPlayerProfile({
    required Color avatarBorderColor,
    required bool timerVisible,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // First Line: Flag and Country Name
        Row(
          children: [
            _buildFlagWidget(widget.player.countryFlag, size: 11),
            const SizedBox(width: 3),
            Expanded(
              child: Text(
                _displayCountryName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            if (widget.onBuddyRequest != null) ...[
              const SizedBox(width: 3),
              _buddySign(16),
            ],
          ],
        ),
        const SizedBox(height: 3),

        // Second Line: name, diamonds, and gold.
        Row(
          children: [
            Expanded(
              child: Text(
                widget.player.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            if (widget.showPlayerDot) ...[
              const SizedBox(width: 4),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: const Color(0xFF36D17B),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.75),
                    width: 0.8,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x8836D17B),
                      blurRadius: 5,
                      spreadRadius: 0.5,
                    ),
                  ],
                ),
              ),
            ],
            const Icon(
              Icons.diamond_rounded,
              color: AppColors.diamondBlue,
              size: 10,
            ),
            const SizedBox(width: 1),
            Text(
              _formatBalance(widget.player.diamonds),
              style: GoogleFonts.poppins(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 5),
            const Icon(
              Icons.monetization_on_rounded,
              color: AppColors.coinGold,
              size: 10,
            ),
            const SizedBox(width: 1),
            Text(
              _formatBalance(widget.player.coins),
              style: GoogleFonts.poppins(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),

        // Third Line: profile image, captured-token counts, and missed rolls.
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CustomPaint(
              foregroundPainter: timerVisible
                  ? _TurnTimerBorderPainter(1 - _turnCountdown.value)
                  : null,
              child: Container(
                width: 42,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: avatarBorderColor, width: 1.5),
                ),
                clipBehavior: Clip.antiAlias,
                child: _buildAvatar(),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var index = 0;
                        index < _opponentColors.length;
                        index++) ...[
                      if (index > 0) const SizedBox(width: 4),
                      _OpponentKillStat(
                        color: _opponentColors[index],
                        count:
                            widget.player.killCounts[_opponentColors[index]] ??
                                0,
                        compact: true,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            _MissedTurnDots(player: widget.player),
          ],
        ),
      ],
    );
  }

  Widget _buddySign(double size) => Tooltip(
        message: 'Tap this player card to send a buddy request',
        child: IgnorePointer(
          child: Icon(
            Icons.person_add_alt_1_rounded,
            size: size,
            color: const Color(0xFF55FF9B),
            shadows: const [
              Shadow(color: Color(0xAA24EA59), blurRadius: 7),
            ],
          ),
        ),
      );

  String _formatBalance(int value) {
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K'.replaceAll('.0K', 'K');
    }
    return '$value';
  }

  Widget _buildAvatar() {
    final avatarUrl = widget.player.avatarUrl;
    if (avatarUrl == null || avatarUrl.isEmpty) {
      return Icon(
        widget.player.isBot ? Icons.smart_toy_rounded : Icons.person_rounded,
        color: Colors.white70,
        size: 22,
      );
    }
    if (avatarUrl.startsWith('http')) {
      return Image.network(
        avatarUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.person_rounded, color: Colors.white70, size: 22),
      );
    }
    if (avatarUrl.startsWith('assets/') || avatarUrl.endsWith('.webp')) {
      return Image.asset(
        avatarUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.person_rounded, color: Colors.white70, size: 22),
      );
    }
    return Icon(
      widget.player.isBot ? Icons.smart_toy_rounded : Icons.person_rounded,
      color: Colors.white70,
      size: 22,
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
    final canRoll = gameState.isLocalPlayerTurn &&
        !gameState.isCurrentPlayerBot &&
        !gameState.currentPlayer.isEliminated &&
        gameState.turnPhase == GameTurnPhase.rollDice &&
        !gameState.isGameOver;
    final isActive = gameState.turnPhase == GameTurnPhase.rollDice &&
        !gameState.currentPlayer.isEliminated &&
        !gameState.isGameOver;
    return _PlayerDie(
      value: gameState.lastRolledDiceValue ?? gameState.diceValue,
      isRolling: gameState.isDiceRolling,
      isActive: isActive,
      canRoll: canRoll,
      playerColor: gameState.currentPlayer.color,
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
            LudoPawnIcon(color: color, size: compact ? 10 : 12),
            SizedBox(width: compact ? 0.5 : 1),
            Icon(
              Icons.close_rounded,
              color: const Color(0xFFFF655F),
              size: compact ? 8 : 10,
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
                  fontSize: compact ? 7.5 : 9,
                  height: 1.1,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
}

class _MissedTurnDots extends StatelessWidget {
  const _MissedTurnDots({required this.player});

  final PlayerModel player;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '${player.name}: ${player.missedTurns} missed turns',
      child: Semantics(
        label: '${player.name}, ${player.missedTurns} missed turns',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xEE05070C),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: player.color.color.withValues(alpha: 0.85),
              width: 1,
            ),
            boxShadow: const [
              BoxShadow(color: Color(0x77000000), blurRadius: 5),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0;
                  index < GameNotifier.maxMissedTurns;
                  index++) ...[
                if (index > 0) const SizedBox(width: 2),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: index < player.missedTurns
                        ? const Color(0xFFFF3B30)
                        : const Color(0xFF20E878),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: index < player.missedTurns
                          ? const Color(0xFFFFB3AE)
                          : const Color(0xFFB9FFD3),
                      width: 0.7,
                    ),
                    boxShadow: const [
                      BoxShadow(color: Color(0x8820E878), blurRadius: 3),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerDie extends StatefulWidget {
  final int? value;
  final bool isRolling;
  final bool isActive;
  final bool canRoll;
  final LudoColor playerColor;
  final double size;
  final VoidCallback onTap;

  const _PlayerDie({
    required this.value,
    required this.isRolling,
    required this.isActive,
    required this.canRoll,
    required this.playerColor,
    this.size = 34,
    required this.onTap,
  });

  @override
  State<_PlayerDie> createState() => _PlayerDieState();
}

class _PlayerDieState extends State<_PlayerDie> with TickerProviderStateMixin {
  final math.Random _visualRandom = math.Random.secure();
  List<int> _rollFaces = const [];

  late final AnimationController _rollController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  late final AnimationController _flashController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 225),
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    _precacheDiceFaces();
  }

  @override
  void didUpdateWidget(covariant _PlayerDie oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playerColor != widget.playerColor) _precacheDiceFaces();
    if (oldWidget.isRolling != widget.isRolling) _syncRolling();
    if (oldWidget.canRoll != widget.canRoll ||
        oldWidget.isRolling != widget.isRolling) {
      _syncFlashing();
    }
  }

  void _syncRolling() {
    if (widget.isRolling) {
      final startingFace = widget.value ?? 1;
      _rollFaces = [
        startingFace,
        for (var i = 0; i < 17; i++) _visualRandom.nextInt(6) + 1,
      ];
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

  String get _assetColor => switch (widget.playerColor) {
        LudoColor.red => 'red',
        LudoColor.green => 'green',
        LudoColor.yellow => 'orange',
        LudoColor.blue => 'blue',
      };

  String _assetPath(int value) => 'assets/images/dice-$_assetColor-$value.webp';

  void _precacheDiceFaces() {
    for (var value = 1; value <= 6; value++) {
      precacheImage(AssetImage(_assetPath(value)), context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.canRoll ? widget.onTap : null,
      child: AnimatedBuilder(
        animation: _animations,
        builder: (context, _) {
          final flashPhase = _flashController.value;
          final rollPhase = _rollController.value;
          final previousValue = widget.value ?? 1;
          final rollingValue = _rollFaces.isEmpty
              ? previousValue
              : _rollFaces[(rollPhase * (_rollFaces.length - 1))
                  .floor()
                  .clamp(0, _rollFaces.length - 1)
                  .toInt()];
          final value = widget.isRolling
              ? (rollPhase < 0.98 ? rollingValue : previousValue)
              : widget.value;
          final easedRoll = Curves.easeInOutCubic.transform(rollPhase);
          final hopHeight = widget.isRolling
              ? math.sin(rollPhase * math.pi * 2).abs() * widget.size * 0.15
              : 0.0;
          final rollOffsetX = widget.isRolling
              ? math.sin(rollPhase * math.pi * 3) * widget.size * 0.12
              : 0.0;
          final rotationX = widget.isRolling ? easedRoll * math.pi * 4 : 0.0;
          final rotationY = widget.isRolling ? easedRoll * math.pi * 6 : 0.0;
          final rotationZ = widget.isRolling
              ? easedRoll * math.pi * 8 +
                  math.sin(rollPhase * math.pi * 4) * 0.10 * (1 - rollPhase)
              : -0.025;
          final landingSquash = widget.isRolling && rollPhase > 0.82
              ? 1 - math.sin((rollPhase - 0.82) / 0.18 * math.pi) * 0.08
              : 1.0;

          return Transform.translate(
            offset: Offset(rollOffsetX, -hopHeight),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.012)
                ..rotateX(rotationX)
                ..rotateY(rotationY)
                ..rotateZ(rotationZ),
              child: Transform.scale(
                scale: (1 + hopHeight / 180) *
                    landingSquash *
                    (widget.canRoll ? 1 + flashPhase * 0.07 : 1),
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    boxShadow: widget.isActive || widget.isRolling
                        ? [
                            BoxShadow(
                              color: widget.playerColor.color.withValues(
                                alpha: widget.isRolling
                                    ? 0.6
                                    : widget.canRoll
                                        ? 0.2 + flashPhase * 0.5
                                        : 0.28,
                              ),
                              blurRadius: widget.isRolling
                                  ? 17
                                  : widget.canRoll
                                      ? 7 + flashPhase * 12
                                      : 9,
                              spreadRadius: widget.isRolling
                                  ? 2
                                  : widget.canRoll
                                      ? flashPhase * 2
                                      : 1,
                            ),
                          ]
                        : const [],
                  ),
                  child: Image.asset(
                    _assetPath(value ?? 1),
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                    gaplessPlayback: true,
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
