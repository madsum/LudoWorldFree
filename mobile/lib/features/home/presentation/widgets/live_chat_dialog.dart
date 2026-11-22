import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import 'friends_panel.dart';

class LiveChatDialog extends StatelessWidget {
  const LiveChatDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF08122C),
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: AppColors.gold, width: 1.5),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 700),
        child: DefaultTabController(
          length: 3,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
                child: Row(
                  children: [
                    const Icon(Icons.groups_rounded,
                        color: AppColors.gold, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'LIVE CHAT',
                        style: GoogleFonts.poppins(
                          color: AppColors.gold,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const TabBar(
                indicatorColor: AppColors.gold,
                labelColor: AppColors.gold,
                unselectedLabelColor: Colors.white60,
                labelPadding: EdgeInsets.symmetric(horizontal: 2),
                labelStyle: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.1,
                ),
                unselectedLabelStyle: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                ),
                tabs: [
                  Tab(
                      icon: Icon(Icons.people_alt_rounded, size: 21),
                      text: 'FRIENDS'),
                  Tab(
                      icon: Icon(Icons.emoji_events_rounded, size: 21),
                      text: 'LEADERBOARD'),
                  Tab(
                      icon: Icon(Icons.flag_rounded, size: 21),
                      text: 'DAILY GOALS'),
                ],
              ),
              const Expanded(
                child: TabBarView(
                  children: [
                    FriendsPanel(),
                    _ComingSoonPanel(),
                    _ComingSoonPanel(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComingSoonPanel extends StatelessWidget {
  const _ComingSoonPanel();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Coming in the next version!',
        textAlign: TextAlign.center,
        style: GoogleFonts.poppins(
          color: Colors.white70,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
