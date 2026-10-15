import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/ads/ad_mob_consent_service.dart';
import '../../../../shared/widgets/banner_ad_widget.dart';

class ExitGameDialog extends ConsumerWidget {
  final VoidCallback onYes;
  final VoidCallback onNo;

  const ExitGameDialog({
    super.key,
    required this.onYes,
    required this.onNo,
  });

  static void show(
    BuildContext context, {
    required VoidCallback onYes,
    required VoidCallback onNo,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ExitGameDialog(onYes: onYes, onNo: onNo),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1457B8), Color(0xFF092653), Color(0xFF05112B)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.gold, width: 2.5),
          boxShadow: const [
            BoxShadow(color: Colors.black87, blurRadius: 20, offset: Offset(0, 8)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header Text: EXIT?
            Text(
              'EXIT?',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: AppColors.gold,
                letterSpacing: 1.5,
                shadows: const [
                  Shadow(color: Colors.black, blurRadius: 6, offset: Offset(0, 2)),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Middle Ad Box Container (Black ad frame as shown in screenshot)
            Container(
              width: double.infinity,
              height: 220,
              decoration: BoxDecoration(
                color: const Color(0xFF121212),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24, width: 1.2),
              ),
              clipBehavior: Clip.antiAlias,
              child: Center(
                child: BannerAdWidget(
                  consentService: ref.read(adMobConsentServiceProvider),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Bottom Action Buttons: Yes | No
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // YES Button
                _PillActionButton(
                  text: 'Yes',
                  color: const Color(0xFF0D47A1),
                  borderColor: AppColors.gold,
                  onTap: () {
                    Navigator.of(context).pop();
                    onYes();
                  },
                ),

                // NO Button
                _PillActionButton(
                  text: 'No',
                  color: const Color(0xFF0D47A1),
                  borderColor: AppColors.gold,
                  onTap: () {
                    Navigator.of(context).pop();
                    onNo();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PillActionButton extends StatelessWidget {
  final String text;
  final Color color;
  final Color borderColor;
  final VoidCallback onTap;

  const _PillActionButton({
    required this.text,
    required this.color,
    required this.borderColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 120,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 2),
          boxShadow: const [
            BoxShadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 3)),
          ],
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
