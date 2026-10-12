import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../game/domain/models/ludo_color.dart';
import '../../../game/domain/models/player_model.dart';

class OnlineMatchmakingDialog extends ConsumerStatefulWidget {
  final ValueChanged<List<PlayerModel>> onMatchFound;

  const OnlineMatchmakingDialog({
    super.key,
    required this.onMatchFound,
  });

  static void show(BuildContext context, {required ValueChanged<List<PlayerModel>> onMatchFound}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => OnlineMatchmakingDialog(onMatchFound: onMatchFound),
    );
  }

  @override
  ConsumerState<OnlineMatchmakingDialog> createState() => _OnlineMatchmakingDialogState();
}

class _OnlineMatchmakingDialogState extends ConsumerState<OnlineMatchmakingDialog>
    with TickerProviderStateMixin {
  late final AnimationController _vsGlowController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  Timer? _countdownTimer;
  Timer? _pollingTimer;
  int _secondsRemaining = 45;

  bool _isMatchFound = false;
  String? _opponentName;
  String? _opponentAvatar;
  String? _opponentCountry;
  String? _opponentFlag;

  @override
  void initState() {
    super.initState();
    _startCountdown();
    _startMatchmakingQueue();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        _timerExpiredFallbackMatch();
      }
    });
  }

  void _startMatchmakingQueue() async {
    final user = ref.read(authControllerProvider).user;
    final dio = ref.read(apiClientProvider);

    try {
      final response = await dio.post(
        '/matchmaking/join',
        data: {
          'displayName': user?.name ?? 'Player 1',
          'avatarUrl': user?.avatarUrl ?? 'assets/images/black-mask.webp',
          'country': user?.country ?? 'World',
          'countryFlag': user?.countryFlag ?? '🌐',
          'entryFee': 500,
        },
        options: Options(
          headers: {'X-Player-ID': user?.id},
        ),
      );

      if (response.data != null && response.data['matchFound'] == true) {
        _handleMatchFoundResponse(response.data);
        return;
      }
    } catch (_) {}

    // Poll status every 2 seconds
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted || _isMatchFound) return;
      try {
        final statusResponse = await dio.get(
          '/matchmaking/status',
          options: Options(
            headers: {'X-Player-ID': user?.id},
          ),
        );
        if (statusResponse.data != null && statusResponse.data['matchFound'] == true) {
          _handleMatchFoundResponse(statusResponse.data);
        }
      } catch (_) {}
    });
  }

  void _handleMatchFoundResponse(dynamic data) {
    if (_isMatchFound) return;
    _pollingTimer?.cancel();
    _countdownTimer?.cancel();

    setState(() {
      _isMatchFound = true;
      _opponentName = data['opponentName'] ?? 'Smart AI Alpha';
      _opponentAvatar = data['opponentAvatarUrl'] ?? 'assets/images/blue-mask.webp';
      _opponentCountry = data['opponentCountry'] ?? 'World';
      _opponentFlag = data['opponentCountryFlag'] ?? '🌐';
    });

    _launchGameWithOpponent();
  }

  void _timerExpiredFallbackMatch() {
    if (_isMatchFound) return;
    _pollingTimer?.cancel();
    _countdownTimer?.cancel();

    setState(() {
      _isMatchFound = true;
      _opponentName = 'Smart AI Alpha';
      _opponentAvatar = 'assets/images/blue-mask7.webp';
      _opponentCountry = 'World';
      _opponentFlag = '🌐';
    });

    _launchGameWithOpponent();
  }

  void _launchGameWithOpponent() {
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      final user = ref.read(authControllerProvider).user;

      final humanPlayer = PlayerModel.initial(
        id: user?.id ?? 'p1',
        name: user?.name ?? 'Player 1',
        color: LudoColor.red,
        avatarUrl: user?.avatarUrl ?? 'assets/images/black-mask.webp',
        country: user?.country ?? 'World',
        countryFlag: user?.countryFlag ?? '🌐',
        isBot: false,
      );

      final opponentPlayer = PlayerModel.initial(
        id: 'p2_online',
        name: _opponentName ?? 'Smart AI Alpha',
        color: LudoColor.yellow,
        avatarUrl: _opponentAvatar ?? 'assets/images/blue-mask7.webp',
        country: _opponentCountry ?? 'World',
        countryFlag: _opponentFlag ?? '🌐',
        isBot: _opponentName == 'Smart AI Alpha',
      );

      Navigator.of(context).pop();
      widget.onMatchFound([humanPlayer, opponentPlayer]);
    });
  }

  void _cancelMatchmaking() async {
    _pollingTimer?.cancel();
    _countdownTimer?.cancel();
    try {
      final dio = ref.read(apiClientProvider);
      final user = ref.read(authControllerProvider).user;
      await dio.post(
        '/matchmaking/cancel',
        options: Options(headers: {'X-Player-ID': user?.id}),
      );
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _vsGlowController.dispose();
    _pulseController.dispose();
    _countdownTimer?.cancel();
    _pollingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final myName = user?.name ?? 'madsum1984';
    final myAvatar = user?.avatarUrl ?? 'assets/images/black-mask.webp';

    final minutes = (_secondsRemaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (_secondsRemaining % 60).toString().padLeft(2, '0');

    return Scaffold(
      backgroundColor: const Color(0xEB8B0000), // Dark Red Ludo King Background
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Ludo World Free 3D Logo Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.workspace_premium_rounded,
                            color: AppColors.gold,
                            size: 32,
                            shadows: const [
                              Shadow(color: Colors.black, blurRadius: 8),
                            ],
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'LUDO WORLD FREE',
                            style: GoogleFonts.cinzel(
                              color: AppColors.gold,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                              shadows: const [
                                Shadow(color: Colors.black, blurRadius: 8, offset: Offset(0, 3)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // ONLINE MULTIPLAYER Title Banner
                      Text(
                        'ONLINE MULTIPLAYER',
                        style: GoogleFonts.poppins(
                          color: const Color(0xFFFFEA00),
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                          shadows: const [
                            Shadow(color: Colors.black, blurRadius: 6, offset: Offset(0, 2)),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Mode & Entry Fee Banner Box
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7A0000),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white24, width: 1.5),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              children: [
                                Text(
                                  'Game Mode',
                                  style: GoogleFonts.poppins(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    const Icon(Icons.emoji_events_rounded, color: AppColors.gold, size: 16),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Classic',
                                      style: GoogleFonts.poppins(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Container(width: 1, height: 28, color: Colors.white24),
                            Column(
                              children: [
                                Text(
                                  'Entry Amount',
                                  style: GoogleFonts.poppins(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    const Icon(Icons.monetization_on_rounded, color: AppColors.coinGold, size: 16),
                                    const SizedBox(width: 4),
                                    Text(
                                      '500',
                                      style: GoogleFonts.poppins(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // VS Player Cards Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Left Player Box (My Avatar)
                          _PlayerCardBox(
                            name: myName,
                            avatarUrl: myAvatar,
                            borderColor: const Color(0xFFE53935),
                          ),

                          const SizedBox(width: 12),

                          // Center 3D VS Badge
                          AnimatedBuilder(
                            animation: _vsGlowController,
                            builder: (context, child) {
                              final glow = _vsGlowController.value;
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFFFFEA00), Color(0xFFFF8F00), Color(0xFFB76E00)],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFFFD700).withValues(alpha: 0.6 + glow * 0.4),
                                      blurRadius: 12 + glow * 8,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: Text(
                                  'VS',
                                  style: GoogleFonts.poppins(
                                    color: Colors.black87,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              );
                            },
                          ),

                          const SizedBox(width: 12),

                          // Right Player Box (Opponent Avatar or Searching Shimmer)
                          _PlayerCardBox(
                            name: _isMatchFound ? (_opponentName ?? 'Opponent') : '???',
                            avatarUrl: _isMatchFound ? _opponentAvatar : null,
                            borderColor: const Color(0xFF1E88E5),
                            isSearching: !_isMatchFound,
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Stopwatch Timer Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF00E676), width: 2),
                          boxShadow: const [
                            BoxShadow(color: Color(0x8800E676), blurRadius: 10),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.timer_rounded, color: Color(0xFF00E676), size: 22),
                            const SizedBox(width: 8),
                            Text(
                              '$minutes:$seconds',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Searching Text with Pulse Animation
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          final opacity = 0.5 + _pulseController.value * 0.5;
                          return Opacity(
                            opacity: opacity,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.search_rounded, color: AppColors.gold, size: 22),
                                const SizedBox(width: 6),
                                Text(
                                  _isMatchFound ? 'MATCH FOUND! LAUNCHING...' : 'SEARCHING FOR PLAYERS...',
                                  style: GoogleFonts.poppins(
                                    color: _isMatchFound ? const Color(0xFF00E676) : AppColors.gold,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Back/Cancel Button at Bottom Left
            Positioned(
              left: 16,
              bottom: 16,
              child: GestureDetector(
                onTap: _cancelMatchmaking,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFC107),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 3)),
                    ],
                  ),
                  child: const Icon(Icons.undo_rounded, color: Colors.black87, size: 24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerCardBox extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final Color borderColor;
  final bool isSearching;

  const _PlayerCardBox({
    required this.name,
    this.avatarUrl,
    required this.borderColor,
    this.isSearching = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: const Color(0xFF132B5C),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 3),
            boxShadow: [
              BoxShadow(color: borderColor.withValues(alpha: 0.5), blurRadius: 10),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: isSearching
              ? _SearchingShimmerAvatar()
              : _buildAvatarImage(avatarUrl),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 105,
          child: Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAvatarImage(String? url) {
    if (url == null || url.isEmpty) {
      return const Icon(Icons.person_rounded, color: Colors.white70, size: 48);
    }
    if (url.startsWith('http')) {
      return Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, color: Colors.white70, size: 48));
    }
    return Image.asset(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, color: Colors.white70, size: 48));
  }
}

class _SearchingShimmerAvatar extends StatefulWidget {
  @override
  State<_SearchingShimmerAvatar> createState() => _SearchingShimmerAvatarState();
}

class _SearchingShimmerAvatarState extends State<_SearchingShimmerAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final opacity = 0.3 + _controller.value * 0.5;
        return Container(
          color: Colors.black26,
          child: Center(
            child: Opacity(
              opacity: opacity,
              child: const Icon(Icons.person_search_rounded, color: AppColors.gold, size: 44),
            ),
          ),
        );
      },
    );
  }
}
