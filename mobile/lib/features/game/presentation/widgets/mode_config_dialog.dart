import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/constants/app_colors.dart';
import '../../domain/models/ludo_color.dart';
import '../../domain/models/player_model.dart';

class ModeConfigDialog extends StatefulWidget {
  final String title;
  final bool isVsComputer;
  final String playerName;
  final String? avatarUrl;
  final void Function(List<PlayerModel> players) onStartGame;

  const ModeConfigDialog({
    super.key,
    required this.title,
    required this.isVsComputer,
    required this.playerName,
    this.avatarUrl,
    required this.onStartGame,
  });

  static void show(
    BuildContext context, {
    required String title,
    required bool isVsComputer,
    required String playerName,
    String? avatarUrl,
    required void Function(List<PlayerModel> players) onStartGame,
  }) {
    showDialog(
      context: context,
      builder: (context) => ModeConfigDialog(
        title: title,
        isVsComputer: isVsComputer,
        playerName: playerName,
        avatarUrl: avatarUrl,
        onStartGame: onStartGame,
      ),
    );
  }

  @override
  State<ModeConfigDialog> createState() => _ModeConfigDialogState();
}

class _ModeConfigDialogState extends State<ModeConfigDialog> {
  int _playerCount = 4; // 2 or 4 players
  LudoColor _selectedColor = LudoColor.red;

  List<PlayerModel> _buildPlayers() {
    final players = <PlayerModel>[];

    if (widget.isVsComputer) {
      // Two-player games use the intended bottom-left/top-right seating:
      // human Blue and bot Green. Four-player games keep the color selection.
      final userColor = _playerCount == 2 ? LudoColor.blue : _selectedColor;

      players.add(PlayerModel.initial(
        id: 'user_1',
        name: widget.playerName,
        avatarUrl: widget.avatarUrl,
        color: userColor,
        isBot: false,
      ));

      // AI Bots
      final remainingColors = _playerCount == 2
          ? [LudoColor.green]
          : LudoColor.values.where((c) => c != userColor).toList();
      final botNames = ['Smart Bot Alpha', 'Smart Bot Beta', 'Smart Bot Gamma'];

      int count = _playerCount - 1;
      for (int i = 0; i < count; i++) {
        players.add(PlayerModel.initial(
          id: 'bot_${i + 1}',
          name: botNames[i],
          color: remainingColors[i],
          isBot: true,
        ));
      }
    } else {
      // Local Pass & Play Mode (2 or 4 Human Players)
      final colors = _playerCount == 2
          ? [LudoColor.red, LudoColor.yellow]
          : LudoColor.values;

      for (int i = 0; i < colors.length; i++) {
        players.add(PlayerModel.initial(
          id: 'player_${i + 1}',
          name: i == 0 ? widget.playerName : 'Player ${i + 1}',
          color: colors[i],
          isBot: false,
        ));
      }
    }

    return players;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.bgNavy,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.gold, width: 2),
      ),
      title: Row(
        children: [
          Icon(
            widget.isVsComputer ? Icons.smart_toy_rounded : Icons.phone_android_rounded,
            color: AppColors.gold,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.title.toUpperCase(),
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Player Count Selection (2 Players or 4 Players)
          Text(
            'SELECT PLAYERS',
            style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: Center(child: Text('2 PLAYERS', style: GoogleFonts.poppins(fontWeight: FontWeight.bold))),
                  selected: _playerCount == 2,
                  selectedColor: AppColors.gold,
                  backgroundColor: AppColors.bgCard,
                  labelStyle: TextStyle(color: _playerCount == 2 ? Colors.black87 : Colors.white),
                  onSelected: (selected) => setState(() => _playerCount = 2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  label: Center(child: Text('4 PLAYERS', style: GoogleFonts.poppins(fontWeight: FontWeight.bold))),
                  selected: _playerCount == 4,
                  selectedColor: AppColors.gold,
                  backgroundColor: AppColors.bgCard,
                  labelStyle: TextStyle(color: _playerCount == 4 ? Colors.black87 : Colors.white),
                  onSelected: (selected) => setState(() => _playerCount = 4),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Color Choice (For Vs Computer Mode)
          if (widget.isVsComputer && _playerCount == 2) ...[
            Text(
              'You play Blue (bottom-left). The bot plays Green (top-right).',
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.white70),
            ),
          ],

          if (widget.isVsComputer && _playerCount == 4) ...[
            Text(
              'SELECT YOUR COLOR',
              style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: LudoColor.values.map((color) {
                final isSelected = _selectedColor == color;
                return GestureDetector(
                  onTap: () => setState(() => _selectedColor = color),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.white : Colors.transparent,
                        width: 3,
                      ),
                      boxShadow: [
                        if (isSelected)
                          BoxShadow(
                            color: color.color.withValues(alpha: 0.8),
                            blurRadius: 10,
                          ),
                      ],
                    ),
                    child: isSelected ? const Icon(Icons.check, color: Colors.white) : null,
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.white54)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.gold,
            foregroundColor: Colors.black87,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: () {
            Navigator.of(context).pop();
            widget.onStartGame(_buildPlayers());
          },
          child: Text(
            'START GAME',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
