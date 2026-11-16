import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../domain/models/game_state.dart';

class DiceRollerWidget extends StatelessWidget {
  static const _turnHighlight = Color(0xFFFA02A3);

  final GameState gameState;
  final VoidCallback onRoll;

  const DiceRollerWidget({
    super.key,
    required this.gameState,
    required this.onRoll,
  });

  @override
  Widget build(BuildContext context) {
    final isMyTurn = gameState.isLocalPlayerTurn &&
        !gameState.isCurrentPlayerBot &&
        gameState.turnPhase == GameTurnPhase.rollDice &&
        !gameState.isGameOver;

    final diceVal = gameState.diceValue;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Current Player Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: gameState.currentPlayer.color.color,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _turnHighlight, width: 2),
            ),
            child: Row(
              children: [
                const Icon(Icons.person_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 6),
                Text(
                  gameState.currentPlayer.name,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          // 3D Dice Button
          GestureDetector(
            onTap: isMyTurn ? onRoll : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isMyTurn ? _turnHighlight : Colors.grey.shade400,
                  width: isMyTurn ? 3 : 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isMyTurn
                        ? _turnHighlight.withValues(alpha: 0.7)
                        : Colors.black26,
                    blurRadius: isMyTurn ? 12 : 4,
                    spreadRadius: isMyTurn ? 2 : 0,
                  ),
                ],
              ),
              child: Center(
                child: diceVal == null
                    ? Icon(
                        Icons.casino_rounded,
                        size: 38,
                        color: isMyTurn ? _turnHighlight : Colors.grey,
                      )
                    : _DiceFaceWidget(value: diceVal),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiceFaceWidget extends StatelessWidget {
  final int value;

  const _DiceFaceWidget({required this.value});

  @override
  Widget build(BuildContext context) {
    return Text(
      '$value',
      style: GoogleFonts.poppins(
        fontSize: 32,
        fontWeight: FontWeight.w900,
        color: Colors.black87,
      ),
    );
  }
}
