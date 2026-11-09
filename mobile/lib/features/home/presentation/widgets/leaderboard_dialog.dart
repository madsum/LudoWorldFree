import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';

class LeaderboardDialog extends ConsumerStatefulWidget {
  const LeaderboardDialog({super.key});

  @override
  ConsumerState<LeaderboardDialog> createState() => _LeaderboardDialogState();
}

class _LeaderboardDialogState extends ConsumerState<LeaderboardDialog> {
  late Future<List<Map<String, dynamic>>> _entriesFuture;

  @override
  void initState() {
    super.initState();
    _entriesFuture = _loadEntries();
  }

  Future<List<Map<String, dynamic>>> _loadEntries() async {
    final response = await ref.read(apiClientProvider).get(
      '/leaderboard',
      queryParameters: const {'limit': 50},
    );
    final data = response.data;
    if (data is! Map || data['entries'] is! List) {
      throw const FormatException('The leaderboard response was invalid.');
    }
    return (data['entries'] as List)
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList(growable: false);
  }

  void _retry() {
    setState(() => _entriesFuture = _loadEntries());
  }

  @override
  Widget build(BuildContext context) {
    final currentPlayerId = ref.watch(authControllerProvider).user?.id;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
      child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
              child: Row(
                children: [
                  const Icon(Icons.emoji_events_rounded,
                      color: AppColors.gold, size: 30),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'GOLD LEADERBOARD',
                      style: GoogleFonts.poppins(
                        color: AppColors.gold,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white24),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _entriesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(
                      child: CircularProgressIndicator(color: AppColors.gold),
                    );
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.cloud_off_rounded,
                                color: Colors.white54, size: 38),
                            const SizedBox(height: 12),
                            Text(
                              'Could not load the leaderboard.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(color: Colors.white70),
                            ),
                            TextButton(
                              onPressed: _retry,
                              child: const Text('RETRY'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final entries = snapshot.data ?? const [];
                  if (entries.isEmpty) {
                    return Center(
                      child: Text(
                        'No players on the leaderboard yet.',
                        style: GoogleFonts.poppins(color: Colors.white70),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: entries.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: Colors.white10),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final playerId = entry['playerId']?.toString();
                      final isCurrentPlayer = playerId == currentPlayerId;
                      final rank = (entry['rank'] as num?)?.toInt() ?? index + 1;
                      final gold = (entry['goldCoins'] as num?)?.toInt() ?? 0;
                      final games = (entry['gamesPlayed'] as num?)?.toInt() ?? 0;
                      final flag = entry['countryFlag']?.toString();
                      return Container(
                        color: isCurrentPlayer
                            ? AppColors.gold.withValues(alpha: 0.12)
                            : Colors.transparent,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 34,
                              child: Text(
                                '$rank',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.poppins(
                                  color: rank <= 3 ? AppColors.gold : Colors.white70,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: const Color(0xFF19345F),
                              backgroundImage: _avatarProvider(entry['avatarUrl']),
                              child: _avatarProvider(entry['avatarUrl']) == null
                                  ? const Icon(Icons.person_rounded,
                                      color: Colors.white70)
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${entry['displayName'] ?? 'Player'}${isCurrentPlayer ? ' (You)' : ''}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    '${flag == null || flag.isEmpty ? '🌐' : flag}  $games games played',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white54,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.monetization_on_rounded,
                                color: AppColors.gold, size: 17),
                            const SizedBox(width: 4),
                            Text(
                              _formatGold(gold),
                              style: GoogleFonts.poppins(
                                color: AppColors.gold,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                'Ranked by gold balance. Game count breaks ties.',
                style: GoogleFonts.poppins(color: Colors.white38, fontSize: 10),
              ),
            ),
          ],
      ),
    );
  }

  ImageProvider<Object>? _avatarProvider(Object? value) {
    if (value is! String || value.isEmpty || value.startsWith('assets/')) {
      return null;
    }
    return NetworkImage(value);
  }

  String _formatGold(int value) {
    if (value < 1000) return '$value';
    if (value < 1000000) return '${(value / 1000).toStringAsFixed(1)}K';
    return '${(value / 1000000).toStringAsFixed(1)}M';
  }
}
