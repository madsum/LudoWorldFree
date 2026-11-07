import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../auth/domain/auth_repository.dart';

class DailyBonusDialog extends StatefulWidget {
  final DailyBonusStatus status;
  final Future<DailyBonusStatus?> Function() onClaim;

  const DailyBonusDialog({
    super.key,
    required this.status,
    required this.onClaim,
  });

  @override
  State<DailyBonusDialog> createState() => _DailyBonusDialogState();
}

class _DailyBonusDialogState extends State<DailyBonusDialog> {
  static const _rewards = [1000, 2000, 4000, 8000, 16000, 32000, 64000];

  bool _isClaiming = false;
  String? _errorMessage;

  int get _day => widget.status.rewardDay.clamp(1, _rewards.length);

  Future<void> _claim() async {
    if (_isClaiming || widget.status.claimedToday) return;
    setState(() {
      _isClaiming = true;
      _errorMessage = null;
    });
    final result = await widget.onClaim();
    if (!mounted) return;
    if (result?.success == true) {
      Navigator.of(context).pop(result);
      return;
    }
    setState(() {
      _isClaiming = false;
      _errorMessage =
          'The ad was not completed or the bonus server could not be reached. Please try again.';
    });
  }

  String _formatCoins(int amount) => amount
      .toString()
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final completedDay = widget.status.claimedToday ? _day : _day - 1;

    return PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 540,
            maxHeight: size.height * 0.94,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF06183D),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFFFC928), width: 3),
              boxShadow: const [
                BoxShadow(color: Color(0xAAFFC928), blurRadius: 20),
              ],
            ),
            child: Column(
              children: [
                _buildTitle(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 11),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF0B3374), Color(0xFF091E4B)],
                            ),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Text(
                            'Collect a bigger coin reward every day',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(height: 13),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: 6,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 9,
                            mainAxisSpacing: 10,
                            childAspectRatio: 0.77,
                          ),
                          itemBuilder: (context, index) => _buildDayCard(
                            day: index + 1,
                            currentDay: _day,
                            completedDay: completedDay,
                            wide: false,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 100,
                          width: double.infinity,
                          child: _buildDayCard(
                            day: 7,
                            currentDay: _day,
                            completedDay: completedDay,
                            wide: true,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Come back every day for a new reward',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              color: const Color(0xFFFFB7B7),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isClaiming ? null : _claim,
                      icon: _isClaiming
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.ondemand_video_rounded),
                      label: Text(
                        _isClaiming
                            ? 'WAITING FOR AD…'
                            : 'CLAIM ${_formatCoins(_rewards[_day - 1])} COINS',
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1478E8),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.blueGrey,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 7,
                        shadowColor: const Color(0xFFFFC928),
                        side: const BorderSide(
                            color: Color(0xFFFFC928), width: 2),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitle() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(15, 12, 15, 0),
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF3B32), Color(0xFFBE0718), Color(0xFFFF3B32)],
        ),
        border: Border.all(color: const Color(0xFFFFD74B), width: 2),
        borderRadius: BorderRadius.circular(9),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 7)],
      ),
      child: Text(
        'DAILY BONUS',
        textAlign: TextAlign.center,
        style: GoogleFonts.poppins(
          color: const Color(0xFFFFF22E),
          fontSize: 23,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
          shadows: const [Shadow(color: Colors.black87, blurRadius: 3)],
        ),
      ),
    );
  }

  Widget _buildDayCard({
    required int day,
    required int currentDay,
    required int completedDay,
    required bool wide,
  }) {
    final isToday = day == currentDay && !widget.status.claimedToday;
    final isDone = day <= completedDay;
    final isLocked = day > currentDay;
    final reward = _rewards[day - 1];
    final colors = day.isEven
        ? const [Color(0xFFCB087C), Color(0xFF50085F)]
        : const [Color(0xFF0876D6), Color(0xFF052A74)];

    return GestureDetector(
      onTap: isToday ? _claim : null,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isToday ? const Color(0xFF69FF26) : const Color(0xFFFFD326),
            width: isToday ? 4 : 2.3,
          ),
          boxShadow: isToday
              ? const [BoxShadow(color: Color(0xFF4BFF12), blurRadius: 12)]
              : null,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: 0,
              left: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: isToday
                      ? const Color(0xFFB600D9)
                      : const Color(0xFFFFD619),
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(12)),
                ),
                child: Text(
                  'Day $day',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    color: isToday ? Colors.white : const Color(0xFF421527),
                    fontWeight: FontWeight.w900,
                    fontSize: wide ? 14 : 12,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              top: 31,
              bottom: 39,
              child: Center(
                child: Icon(
                  isDone
                      ? Icons.check_circle_rounded
                      : Icons.monetization_on_rounded,
                  color: isDone ? const Color(0xFF76FF43) : AppColors.coinGold,
                  size: wide ? 48 : 42,
                  shadows: const [Shadow(color: Colors.black87, blurRadius: 5)],
                ),
              ),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 7,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xCC00102F),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  _formatCoins(reward),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: wide ? 17 : 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            if (isLocked)
              Positioned(
                top: -9,
                right: -7,
                child: Icon(Icons.lock_rounded,
                    color: const Color(0xFFFFD326),
                    size: wide ? 25 : 21,
                    shadows: const [
                      Shadow(color: Colors.black, blurRadius: 4)
                    ]),
              ),
          ],
        ),
      ),
    );
  }
}
