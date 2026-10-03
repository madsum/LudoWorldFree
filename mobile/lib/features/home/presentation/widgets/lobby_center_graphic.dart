import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/constants/app_colors.dart';

class LobbyCenterGraphic extends StatelessWidget {
  const LobbyCenterGraphic({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.royalBlue.withValues(alpha: 0.2),
        border: Border.all(color: AppColors.gold, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withValues(alpha: 0.35),
            blurRadius: 18,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipOval(
        child: SvgPicture.asset(
          AppAssets.logoSvg,
          width: 170,
          height: 170,
          fit: BoxFit.cover,
          placeholderBuilder: (context) => Image.asset(
            AppAssets.logoJpeg,
            width: 170,
            height: 170,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => const Icon(
              Icons.casino_rounded,
              size: 80,
              color: AppColors.gold,
            ),
          ),
        ),
      ),
    );
  }
}
