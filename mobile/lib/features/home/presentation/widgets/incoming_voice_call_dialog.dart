import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../game/presentation/services/voice_call_service.dart';

/// A focused call surface shown above the current screen for every call phase.
/// Incoming calls can be answered or declined; active calls can be muted or hung up.
class IncomingVoiceCallDialog extends StatefulWidget {
  const IncomingVoiceCallDialog({
    super.key,
    required this.voiceCallService,
    required this.onMinimize,
  });

  final VoiceCallService voiceCallService;
  final VoidCallback onMinimize;

  @override
  State<IncomingVoiceCallDialog> createState() =>
      _IncomingVoiceCallDialogState();
}

class _IncomingVoiceCallDialogState extends State<IncomingVoiceCallDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1050),
  );
  bool _closeQueued = false;
  bool _maximized = false;
  Size _windowSize = const Size(360, 500);

  @override
  void initState() {
    super.initState();
    widget.voiceCallService.addListener(_handleCallChanged);
    if (widget.voiceCallService.call?.phase == VoiceCallPhase.incoming) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    widget.voiceCallService.removeListener(_handleCallChanged);
    _pulseController.dispose();
    super.dispose();
  }

  void _handleCallChanged() {
    if (!mounted) return;
    if (widget.voiceCallService.call == null) {
      if (_closeQueued) return;
      _closeQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
      });
      return;
    }
    if (widget.voiceCallService.call?.phase == VoiceCallPhase.incoming) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      _pulseController.stop();
      _pulseController.value = 0;
    }
    setState(() {});
  }

  String _statusFor(VoiceCallSession call) => switch (call.phase) {
        VoiceCallPhase.incoming =>
          'INCOMING ${call.withVideo ? 'VIDEO' : 'VOICE'} CALL',
        VoiceCallPhase.outgoing =>
          '${call.withVideo ? 'VIDEO' : 'VOICE'} CALLING',
        VoiceCallPhase.connecting =>
          'CONNECTING ${call.withVideo ? 'VIDEO' : 'AUDIO'}…',
        VoiceCallPhase.connected => call.muted
            ? 'MICROPHONE MUTED'
            : call.withVideo
                ? 'VIDEO CALL'
                : 'VOICE CALL',
      };

  String _initials(String name) => name
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .take(2)
      .map((word) => word.characters.first.toUpperCase())
      .join();

  @override
  Widget build(BuildContext context) {
    final call = widget.voiceCallService.call;
    if (call == null) return const SizedBox.shrink();
    final incoming = call.phase == VoiceCallPhase.incoming;
    final connected = call.phase == VoiceCallPhase.connected;
    final screenSize = MediaQuery.sizeOf(context);
    final maxWindowWidth = math.max(280.0, screenSize.width - 28);
    final maxWindowHeight = math.max(380.0, screenSize.height - 28);
    final windowWidth = _maximized
        ? screenSize.width
        : _windowSize.width.clamp(300.0, maxWindowWidth).toDouble();
    final windowHeight = _maximized
        ? screenSize.height
        : _windowSize.height.clamp(420.0, maxWindowHeight).toDouble();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(widget.voiceCallService.endCall());
      },
      child: Dialog(
        backgroundColor: const Color(0xFF101D32),
        constraints: _maximized ? const BoxConstraints() : null,
        insetPadding: _maximized
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_maximized ? 0 : 30),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: windowWidth,
          height: windowHeight,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              _maximized ? 24 : 22,
              _maximized ? 16 : 20,
              _maximized ? 24 : 22,
              _maximized ? 12 : 16,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _statusFor(call),
                        style: GoogleFonts.poppins(
                          color: const Color(0xFFB6C5D8),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.8,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Minimize call window',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        widget.onMinimize();
                        Navigator.of(context, rootNavigator: true).pop();
                      },
                      icon: const Icon(Icons.minimize_rounded),
                      color: Colors.white70,
                    ),
                    IconButton(
                      tooltip: _maximized
                          ? 'Restore call window'
                          : 'Maximize call window',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _maximized = !_maximized),
                      icon: Icon(_maximized
                          ? Icons.close_fullscreen_rounded
                          : Icons.open_in_full_rounded),
                      color: Colors.white70,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (call.withVideo && !incoming)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _VoiceVideoCallSurface(
                        voiceCallService: widget.voiceCallService,
                      ),
                    ),
                  )
                else ...[
                  const SizedBox(height: 10),
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      final pulse = incoming ? _pulseController.value : 0.0;
                      return Container(
                        padding: EdgeInsets.all(8 + pulse * 7),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF2E8B74).withValues(
                              alpha: incoming ? 0.12 + pulse * 0.1 : 0.12),
                        ),
                        child: child,
                      );
                    },
                    child: CircleAvatar(
                      radius: 48,
                      backgroundColor: const Color(0xFF26735F),
                      child: Text(
                        _initials(call.peerName).isEmpty
                            ? '?'
                            : _initials(call.peerName),
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 27,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Text(
                  call.peerName,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  incoming
                      ? 'Your buddy is calling you'
                      : connected
                          ? '${call.withVideo ? 'Video' : 'Voice'} call is active'
                          : call.phase == VoiceCallPhase.outgoing
                              ? 'Waiting for them to answer'
                              : call.withVideo
                                  ? 'Setting up camera and microphone'
                                  : 'Setting up secure audio',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    color: const Color(0xFFADBACD),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 22),
                if (incoming)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _CallActionButton(
                        label: 'Decline',
                        icon: Icons.call_end_rounded,
                        color: const Color(0xFFE5484D),
                        onPressed: widget.voiceCallService.declineIncomingCall,
                      ),
                      _CallActionButton(
                        label: call.withVideo ? 'Answer video' : 'Answer',
                        icon: call.withVideo
                            ? Icons.video_call_rounded
                            : Icons.call_rounded,
                        color: const Color(0xFF1FAD75),
                        onPressed: () => unawaited(
                          widget.voiceCallService.acceptIncomingCall(),
                        ),
                      ),
                    ],
                  )
                else if (connected)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _CallActionButton(
                        label: call.muted ? 'Unmute' : 'Mute',
                        icon: call.muted
                            ? Icons.mic_off_rounded
                            : Icons.mic_rounded,
                        color: const Color(0xFF334761),
                        onPressed: widget.voiceCallService.toggleMute,
                      ),
                      _CallActionButton(
                        label: 'Hang up',
                        icon: Icons.call_end_rounded,
                        color: const Color(0xFFE5484D),
                        onPressed: () =>
                            unawaited(widget.voiceCallService.endCall()),
                      ),
                    ],
                  )
                else
                  _CallActionButton(
                    label: 'Cancel call',
                    icon: Icons.call_end_rounded,
                    color: const Color(0xFFE5484D),
                    onPressed: () =>
                        unawaited(widget.voiceCallService.endCall()),
                  ),
                if (!_maximized) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: GestureDetector(
                      onPanUpdate: (details) {
                        setState(() {
                          _windowSize = Size(
                            (_windowSize.width + details.delta.dx)
                                .clamp(300.0, maxWindowWidth)
                                .toDouble(),
                            (_windowSize.height + details.delta.dy)
                                .clamp(420.0, maxWindowHeight)
                                .toDouble(),
                          );
                        });
                      },
                      child: const Tooltip(
                        message: 'Drag to resize call window',
                        child: Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.open_in_full_rounded,
                            size: 17,
                            color: Colors.white38,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  const _CallActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: color,
              shape: const CircleBorder(),
              elevation: 5,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onPressed,
                child: SizedBox(
                  width: 66,
                  height: 66,
                  child: Icon(icon, color: Colors.white, size: 29),
                ),
              ),
            ),
            const SizedBox(height: 9),
            Text(
              label,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
}

class MinimizedVoiceCallChip extends StatelessWidget {
  const MinimizedVoiceCallChip({
    super.key,
    required this.voiceCallService,
    required this.onRestore,
  });

  final VoiceCallService voiceCallService;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final call = voiceCallService.call;
    if (call == null) return const SizedBox.shrink();
    return Material(
      color: const Color(0xFF101D32),
      elevation: 12,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        padding: const EdgeInsets.only(left: 12, right: 4, top: 4, bottom: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFF26735F),
              child: Text(
                call.peerName.isEmpty
                    ? '?'
                    : call.peerName.characters.first.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 112),
              child: Text(
                call.phase == VoiceCallPhase.incoming
                    ? '${call.peerName} is calling'
                    : call.peerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              tooltip: call.phase == VoiceCallPhase.incoming
                  ? 'Answer call'
                  : 'Restore call window',
              visualDensity: VisualDensity.compact,
              onPressed: call.phase == VoiceCallPhase.incoming
                  ? () => unawaited(voiceCallService.acceptIncomingCall())
                  : onRestore,
              icon: Icon(
                call.phase == VoiceCallPhase.incoming
                    ? Icons.call_rounded
                    : Icons.open_in_full_rounded,
                color: const Color(0xFF54D895),
                size: 19,
              ),
            ),
            if (call.phase == VoiceCallPhase.incoming)
              IconButton(
                tooltip: 'Decline call',
                visualDensity: VisualDensity.compact,
                onPressed: voiceCallService.declineIncomingCall,
                icon: const Icon(Icons.call_end_rounded,
                    color: Color(0xFFFF7377), size: 19),
              )
            else ...[
              IconButton(
                tooltip: call.muted ? 'Unmute' : 'Mute',
                visualDensity: VisualDensity.compact,
                onPressed: call.phase == VoiceCallPhase.connected
                    ? voiceCallService.toggleMute
                    : null,
                icon: Icon(
                  call.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              IconButton(
                tooltip: 'Hang up',
                visualDensity: VisualDensity.compact,
                onPressed: () => unawaited(voiceCallService.endCall()),
                icon: const Icon(Icons.call_end_rounded,
                    color: Color(0xFFFF7377), size: 19),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _VoiceVideoCallSurface extends StatefulWidget {
  const _VoiceVideoCallSurface({required this.voiceCallService});

  final VoiceCallService voiceCallService;

  @override
  State<_VoiceVideoCallSurface> createState() => _VoiceVideoCallSurfaceState();
}

class _VoiceVideoCallSurfaceState extends State<_VoiceVideoCallSurface> {
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    widget.voiceCallService.addListener(_syncStreams);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await Future.wait([
        _remoteRenderer.initialize(),
        _localRenderer.initialize(),
      ]);
      if (!mounted) return;
      _ready = true;
      _syncStreams();
    } catch (_) {
      if (mounted) setState(() => _ready = false);
    }
  }

  void _syncStreams() {
    if (!_ready) return;
    _remoteRenderer.srcObject = widget.voiceCallService.remoteStream;
    _localRenderer.srcObject = widget.voiceCallService.localStream;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.voiceCallService.removeListener(_syncStreams);
    unawaited(_remoteRenderer.dispose());
    unawaited(_localRenderer.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Container(
          color: const Color(0xFF07111F),
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 190),
          child: !_ready || _remoteRenderer.srcObject == null
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.videocam_rounded,
                          color: Colors.white54, size: 36),
                      SizedBox(height: 8),
                      Text('Connecting video…',
                          style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    RTCVideoView(
                      _remoteRenderer,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                    if (_localRenderer.srcObject != null)
                      Positioned(
                        right: 12,
                        top: 12,
                        width: 88,
                        height: 124,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: RTCVideoView(
                            _localRenderer,
                            mirror: true,
                            objectFit: RTCVideoViewObjectFit
                                .RTCVideoViewObjectFitCover,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      );
}
