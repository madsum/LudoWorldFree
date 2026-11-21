import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';

class IncomingBuddyRequestDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> request;

  const IncomingBuddyRequestDialog({
    super.key,
    required this.request,
  });

  @override
  ConsumerState<IncomingBuddyRequestDialog> createState() =>
      _IncomingBuddyRequestDialogState();
}

class _IncomingBuddyRequestDialogState
    extends ConsumerState<IncomingBuddyRequestDialog> {
  bool _working = false;
  String? _error;

  Future<void> _respond({required bool accept}) async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    final playerId = ref.read(authControllerProvider).user?.id;
    final friendshipId = widget.request['id']?.toString();
    if (playerId == null || friendshipId == null) {
      setState(() {
        _working = false;
        _error = 'Please sign in again and try once more.';
      });
      return;
    }
    try {
      final dio = ref.read(apiClientProvider);
      final options = Options(headers: {'X-Player-ID': playerId});
      if (accept) {
        await dio.post('/friends/$friendshipId/accept', options: options);
      } else {
        await dio.post('/friends/$friendshipId/decline', options: options);
      }
      if (mounted) Navigator.of(context).pop(accept);
    } on DioException catch (error) {
      final message = error.response?.data is Map
          ? error.response?.data['message']?.toString()
          : null;
      if (!mounted) return;
      setState(() {
        _working = false;
        _error = message ?? 'Could not update the request. Please try again.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _error = 'Could not update the request. Please try again.';
      });
    }
  }

  Widget _avatar(String? avatarUrl, String flag) {
    final fallback = Text(flag, style: const TextStyle(fontSize: 30));
    if (avatarUrl == null || avatarUrl.isEmpty) return fallback;
    if (avatarUrl.startsWith('http')) {
      return Image.network(
        avatarUrl,
        width: 72,
        height: 72,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      );
    }
    if (avatarUrl.startsWith('assets/') || avatarUrl.endsWith('.webp')) {
      return Image.asset(
        avatarUrl,
        width: 72,
        height: 72,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      );
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.request['displayName']?.toString() ?? 'A player';
    final avatarUrl = widget.request['avatarUrl']?.toString();
    final flag = widget.request['countryFlag']?.toString() ?? '🌐';

    return Dialog(
      backgroundColor: const Color(0xFF102447),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 38,
              backgroundColor: AppColors.gold.withValues(alpha: 0.2),
              child: ClipOval(child: _avatar(avatarUrl, flag)),
            ),
            const SizedBox(height: 14),
            Text(
              'BUDDY REQUEST',
              style: GoogleFonts.poppins(
                color: AppColors.gold,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'wants to add you as a buddy. Accept to keep them in your Friends list and chat later.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    color: Colors.orangeAccent, fontSize: 11),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _working ? null : () => _respond(accept: false),
                    child: const Text('DECLINE'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _working ? null : () => _respond(accept: true),
                    icon: _working
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.person_add_alt_1_rounded, size: 18),
                    label: const Text('ACCEPT'),
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed:
                  _working ? null : () => Navigator.of(context).pop(false),
              child: const Text('DECIDE LATER'),
            ),
          ],
        ),
      ),
    );
  }
}
