import 'dart:math' as math;
import 'package:flutter/material.dart';

abstract final class FlyingCoinOverlay {
  /// Spawns 3D Flying Coins that animate from [startOffset] to [endOffset] directly on root Overlay
  static void show(
    BuildContext context, {
    required Offset startOffset,
    required Offset endOffset,
    required VoidCallback onComplete,
  }) {
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _FlyingCoinWidget(
        startOffset: startOffset,
        endOffset: endOffset,
        onComplete: () {
          entry.remove();
          onComplete();
        },
      ),
    );

    Overlay.of(context).insert(entry);
  }
}

class _FlyingCoinWidget extends StatefulWidget {
  final Offset startOffset;
  final Offset endOffset;
  final VoidCallback onComplete;

  const _FlyingCoinWidget({
    required this.startOffset,
    required this.endOffset,
    required this.onComplete,
  });

  @override
  State<_FlyingCoinWidget> createState() => _FlyingCoinWidgetState();
}

class _FlyingCoinWidgetState extends State<_FlyingCoinWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  final List<_CoinParticle> _coins = List.generate(10, (index) {
    final random = math.Random();
    return _CoinParticle(
      staggerDelay: index * 0.05,
      curveSpreadX: (random.nextDouble() - 0.5) * 100,
      curveSpreadY: (random.nextDouble() - 0.5) * 50,
      rotationSpeed: random.nextDouble() * math.pi * 4,
    );
  });

  @override
  void initState() {
    super.initState();
    _controller.forward().then((_) {
      widget.onComplete();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Stack(
            children: _coins.map((coin) {
              final double t = ((_controller.value - coin.staggerDelay) /
                      (1.0 - coin.staggerDelay))
                  .clamp(0.0, 1.0);

              if (t <= 0 || t >= 1) return const SizedBox.shrink();

              // Bezier curve interpolation from startOffset to endOffset
              final double controlX =
                  (widget.startOffset.dx + widget.endOffset.dx) / 2 +
                      coin.curveSpreadX;
              final double controlY =
                  (widget.startOffset.dy + widget.endOffset.dy) / 2 -
                      60 +
                      coin.curveSpreadY;

              final double x = (1 - t) * (1 - t) * widget.startOffset.dx +
                  2 * (1 - t) * t * controlX +
                  t * t * widget.endOffset.dx;

              final double y = (1 - t) * (1 - t) * widget.startOffset.dy +
                  2 * (1 - t) * t * controlY +
                  t * t * widget.endOffset.dy;

              final double scale = (math.sin(t * math.pi) * 0.45 + 0.85);

              return Positioned(
                left: x - 14,
                top: y - 14,
                child: Transform.rotate(
                  angle: t * coin.rotationSpeed,
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const RadialGradient(
                          colors: [
                            Color(0xFFFFEA00),
                            Color(0xFFFF8F00),
                            Color(0xFFB76E00)
                          ],
                        ),
                        border: Border.all(color: Colors.white, width: 1.5),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0xFFFF8F00),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.monetization_on_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class _CoinParticle {
  final double staggerDelay;
  final double curveSpreadX;
  final double curveSpreadY;
  final double rotationSpeed;

  const _CoinParticle({
    required this.staggerDelay,
    required this.curveSpreadX,
    required this.curveSpreadY,
    required this.rotationSpeed,
  });
}
