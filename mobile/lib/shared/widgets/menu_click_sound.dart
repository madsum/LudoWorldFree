import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/game_audio_service.dart';

class MenuClickSound extends ConsumerStatefulWidget {
  const MenuClickSound({
    required this.child,
    this.enabled = true,
    this.enabledWhen,
    super.key,
  });

  final Widget child;
  final bool enabled;
  final bool Function()? enabledWhen;

  @override
  ConsumerState<MenuClickSound> createState() => _MenuClickSoundState();
}

class _MenuClickSoundState extends ConsumerState<MenuClickSound> {
  final Map<int, _PointerStart> _pointers = <int, _PointerStart>{};

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = _PointerStart(event.position, event.timeStamp);
  }

  void _onPointerMove(PointerMoveEvent event) {
    final start = _pointers[event.pointer];
    if (start == null) return;
    if ((event.position - start.position).distance > kTouchSlop) {
      start.moved = true;
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    final start = _pointers.remove(event.pointer);
    if (start == null ||
        start.moved ||
        event.timeStamp - start.timeStamp > const Duration(milliseconds: 800)) {
      return;
    }
    if (widget.enabled && (widget.enabledWhen?.call() ?? true)) {
      ref.read(gameAudioServiceProvider).playEffect('audio/classic-click.wav');
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: (event) => _pointers.remove(event.pointer),
        child: widget.child,
      );
}

class _PointerStart {
  _PointerStart(this.position, this.timeStamp);

  final Offset position;
  final Duration timeStamp;
  bool moved = false;
}
