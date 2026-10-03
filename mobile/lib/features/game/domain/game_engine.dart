import 'models/ludo_color.dart';
import 'models/pawn_model.dart';
import 'models/player_model.dart';

class GameEngine {
  GameEngine._();

  /// 8 Safe / Star Tiles: four colored entry stars and four shared safe stars.
  static const Set<int> safeGlobalTiles = {1, 8, 14, 21, 27, 34, 40, 47};

  /// Calculates movable pawns for a player given current dice roll
  static List<PawnModel> getMovablePawns(PlayerModel player, int diceValue) {
    final movable = <PawnModel>[];

    for (final pawn in player.pawns) {
      if (pawn.isFinished) continue;

      if (pawn.isYard) {
        // Must roll a 6 to leave Yard
        if (diceValue == 6) {
          movable.add(pawn);
        }
      } else {
        // On board or in home stretch
        final targetStep = pawn.stepCount + diceValue;
        if (targetStep <= 57) {
          movable.add(pawn);
        }
      }
    }

    return movable;
  }

  /// Checks if landing on this tile results in capturing an opponent pawn
  static PawnModel? findCapturableOpponentPawn({
    required List<PlayerModel> players,
    required LudoColor currentPlayerColor,
    required int targetStep,
  }) {
    if (targetStep < 0 || targetStep > 50) return null; // Only main track allows capture

    final targetGlobalIndex =
        (currentPlayerColor.actualEntryTrackIndex + targetStep) % 52;

    // Safe / Star tiles do NOT allow captures
    if (safeGlobalTiles.contains(targetGlobalIndex)) return null;

    for (final player in players) {
      if (player.color == currentPlayerColor) continue;

      final opponentPawnsOnTile = player.pawns.where((p) {
        return !p.isYard && !p.isFinished && p.globalTileIndex == targetGlobalIndex;
      }).toList();

      // Can capture if there's exactly 1 opponent pawn on non-safe tile
      if (opponentPawnsOnTile.length == 1) {
        return opponentPawnsOnTile.first;
      }
    }

    return null;
  }

  /// Selects the best move for AI Bot using a heuristic scoring algorithm
  static PawnModel? selectBestBotMove({
    required List<PlayerModel> players,
    required PlayerModel botPlayer,
    required List<PawnModel> movablePawns,
    required int diceValue,
  }) {
    if (movablePawns.isEmpty) return null;
    if (movablePawns.length == 1) return movablePawns.first;

    PawnModel? bestPawn;
    int highestScore = -9999;

    for (final pawn in movablePawns) {
      int score = 0;
      final targetStep = pawn.isYard ? 0 : pawn.stepCount + diceValue;

      // 1. CAPTURE OPPONENT PAWN (Highest Priority +1000)
      final capturable = findCapturableOpponentPawn(
        players: players,
        currentPlayerColor: botPlayer.color,
        targetStep: targetStep,
      );
      if (capturable != null) score += 1000;

      // 2. ENTER HOME FINISH (+800)
      if (targetStep == 57) score += 800;

      // 3. RELEASE FROM YARD ON 6 (+500)
      if (pawn.isYard && diceValue == 6) score += 500;

      // 4. ENTER HOME STRETCH SAFETY (+300)
      if (targetStep >= 51 && targetStep <= 56) score += 300;

      // 5. LAND ON SAFE / STAR TILE (+200)
      if (targetStep <= 50) {
        final globalIdx =
            (botPlayer.color.actualEntryTrackIndex + targetStep) % 52;
        if (safeGlobalTiles.contains(globalIdx)) score += 200;
      }

      // 6. ADVANCE LEADING PAWN (+stepCount)
      score += targetStep;

      if (score > highestScore) {
        highestScore = score;
        bestPawn = pawn;
      }
    }

    return bestPawn ?? movablePawns.first;
  }
}
