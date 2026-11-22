import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/top_notice.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';

class DailyGoalsPanel extends ConsumerStatefulWidget {
  const DailyGoalsPanel({super.key});

  @override
  ConsumerState<DailyGoalsPanel> createState() => _DailyGoalsPanelState();
}

class _DailyGoalsPanelState extends ConsumerState<DailyGoalsPanel> {
  late Future<Map<String, dynamic>> _goalsFuture;
  bool _claiming = false;

  @override
  void initState() {
    super.initState();
    _goalsFuture = _loadGoals();
  }

  String? get _playerId => ref.read(authControllerProvider).user?.id;

  Options get _playerOptions => Options(headers: {'X-Player-ID': _playerId});

  Future<Map<String, dynamic>> _loadGoals() async {
    final response = await ref.read(apiClientProvider).get(
          '/daily-goals',
          options: _playerOptions,
        );
    if (response.data is! Map) {
      throw const FormatException('The daily goals response was invalid.');
    }
    return Map<String, dynamic>.from(response.data as Map);
  }

  void _retry() => setState(() => _goalsFuture = _loadGoals());

  Future<void> _claim(String goalType) async {
    if (_claiming) return;
    setState(() => _claiming = true);
    try {
      final response = await ref.read(apiClientProvider).post(
            '/daily-goals/$goalType/claim',
            options: _playerOptions,
          );
      final body = response.data;
      if (body is Map && body['balance'] is num) {
        final currentUser = ref.read(authControllerProvider).user;
        if (currentUser != null) {
          ref.read(authControllerProvider.notifier).applyUserUpdate(
                currentUser.copyWith(coins: (body['balance'] as num).toInt()),
              );
        }
      }
      if (mounted) {
        setState(() => _goalsFuture = _loadGoals());
        TopNotice.show(context, 'Daily goal reward added to your wallet.');
      }
    } on DioException catch (error) {
      if (!mounted) return;
      final message = error.response?.data is Map
          ? error.response?.data['message']?.toString()
          : null;
      TopNotice.show(context, message ?? 'Could not claim this reward.');
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _goalsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.gold),
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Could not load daily goals.',
                    style: GoogleFonts.poppins(color: Colors.white70)),
                TextButton(onPressed: _retry, child: const Text('RETRY')),
              ],
            ),
          );
        }

        final response = snapshot.data ?? const {};
        final entries = (response['entries'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList(growable: false);
        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
          children: [
            Text(
              'Complete goals and claim gold before the day resets.',
              style: GoogleFonts.poppins(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 10),
            for (final goal in entries) _goalCard(goal),
          ],
        );
      },
    );
  }

  Widget _goalCard(Map<String, dynamic> goal) {
    final progress = (goal['progress'] as num?)?.toInt() ?? 0;
    final target = (goal['target'] as num?)?.toInt() ?? 1;
    final reward = (goal['rewardAmount'] as num?)?.toInt() ?? 0;
    final complete = goal['claimable'] == true;
    final claimed = goal['claimed'] == true;
    final ratio = (progress / target).clamp(0.0, 1.0).toDouble();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFF122344),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: complete && !claimed ? AppColors.gold : Colors.white12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_rounded, color: AppColors.gold, size: 21),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  goal['title']?.toString() ?? 'Daily goal',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Icon(Icons.monetization_on_rounded,
                  color: AppColors.gold, size: 17),
              const SizedBox(width: 4),
              Text('$reward',
                  style: GoogleFonts.poppins(
                      color: AppColors.gold, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            goal['description']?.toString() ?? '',
            style: GoogleFonts.poppins(color: Colors.white60, fontSize: 11),
          ),
          const SizedBox(height: 9),
          LinearProgressIndicator(
            value: ratio,
            minHeight: 7,
            borderRadius: BorderRadius.circular(5),
            backgroundColor: Colors.white12,
            color: AppColors.gold,
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Text('$progress / $target',
                  style: GoogleFonts.poppins(color: Colors.white70, fontSize: 11)),
              const Spacer(),
              if (claimed)
                Text('CLAIMED',
                    style: GoogleFonts.poppins(
                        color: Colors.greenAccent, fontWeight: FontWeight.w800, fontSize: 11))
              else if (complete)
                TextButton(
                  onPressed: _claiming ? null : () => _claim(goal['type'].toString()),
                  child: _claiming
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('CLAIM'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
