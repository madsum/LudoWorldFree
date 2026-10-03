import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class LobbyBottomNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const LobbyBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: const BoxDecoration(
        color: Color(0xFF08122C),
        border: Border(
          top: BorderSide(color: Color(0xFF00E5FF), width: 2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black87,
            blurRadius: 12,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // HOME Tab
            Expanded(
              child: _BottomNavItem(
                icon: Icons.home_rounded,
                label: 'HOME',
                isSelected: selectedIndex == 0,
                onTap: () => onTap(0),
              ),
            ),

            // LIVE CHAT Tab
            Expanded(
              child: _BottomNavItem(
                icon: Icons.forum_rounded,
                label: 'LIVE CHAT',
                isSelected: selectedIndex == 1,
                onTap: () => onTap(1),
              ),
            ),

            // SOCIAL Tab
            Expanded(
              child: _BottomNavItem(
                icon: Icons.groups_rounded,
                label: 'SOCIAL',
                isSelected: selectedIndex == 2,
                onTap: () => onTap(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: isSelected
            ? BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00E5FF), Color(0xFF0288D1), Color(0xFF01579B)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: const [
                  BoxShadow(color: Color(0xFF00E5FF), blurRadius: 8, offset: Offset(0, 2)),
                ],
              )
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? const Color(0xFFFFD700) : Colors.white70,
              size: 24,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
