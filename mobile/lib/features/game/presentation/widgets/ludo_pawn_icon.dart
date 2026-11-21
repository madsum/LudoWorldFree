import 'package:flutter/material.dart';

import '../../domain/models/ludo_color.dart';

/// Compact rendering of the matching color pawn asset.
class LudoPawnIcon extends StatelessWidget {
  final LudoColor color;
  final double size;
  final double? width;
  final double? height;

  const LudoPawnIcon({
    super.key,
    required this.color,
    required this.size,
    this.width,
    this.height,
  });

  static String assetFor(LudoColor color) => switch (color) {
        LudoColor.blue => 'assets/images/pawn-blue.png',
        LudoColor.red => 'assets/images/pawn-red.png',
        LudoColor.green => 'assets/images/pawn-green.png',
        LudoColor.yellow => 'assets/images/pawn-yellow.png',
      };

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width ?? size,
        height: height ?? size,
        child: Image.asset(
          assetFor(color),
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      );
}
