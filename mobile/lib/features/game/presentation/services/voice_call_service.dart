import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../../core/constants/app_constants.dart';

enum VoiceCallPhase { incoming, outgoing, connecting, connected }

class VoiceCallSession {
  const VoiceCallSession({
    required this.callId,
    required this.peerId,
    required this.peerName,
    required this.phase,
    this.muted = false,
    this.withVideo = false,
  });

  final String callId;
  final String peerId;
  final String peerName;
  final VoiceCallPhase phase;
  final bool muted;
  final bool withVideo;

  VoiceCallSession copyWith({VoiceCallPhase? phase, bool? muted}) =>
      VoiceCallSession(
        callId: callId,
        peerId: peerId,
        peerName: peerName,
        phase: phase ?? this.phase,
        muted: muted ?? this.muted,
        withVideo: withVideo,
      );
}

final voiceCallServiceProvider =
    ChangeNotifierProvider<VoiceCallService>((ref) {
  final service = VoiceCallService();
  ref.onDispose(service.dispose);
  return service;
});

class VoiceCallService extends ChangeNotifier {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Timer? _callTimeout;
  String? _playerId;
  bool _shouldReconnect = false;
  bool _disposed = false;
  int _ringtoneGeneration = 0;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  RTCPeerConnection? _peerConnection;
  final List<RTCIceCandidate> _queuedCandidates = [];
  final AudioPlayer _ringtonePlayer = AudioPlayer();

  VoiceCallSession? call;
  String? lastError;
  bool isCallUiMinimized = false;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;

  String? takeLastError() {
    final error = lastError;
    lastError = null;
    return error;
  }

  bool get isConnected => _channel != null && _channel!.closeCode == null;

  Future<void> connect(String playerId) async {
    if (_playerId == playerId && isConnected) return;
    _playerId = playerId;
    _shouldReconnect = true;
    _reconnectTimer?.cancel();
    await _openChannel();
  }

  Future<void> _openChannel() async {
    final playerId = _playerId;
    if (playerId == null || !_shouldReconnect || _disposed) return;
    await _subscription?.cancel();
    final uri = Uri.parse(AppConstants.defaultWebSocketUrl).replace(
      path: '/ws/voice',
      queryParameters: {'playerId': playerId},
    );
    final channel = WebSocketChannel.connect(uri);
    _channel = channel;
    _subscription = channel.stream.listen(
      (event) {
        if (event is! String) return;
        try {
          final decoded = jsonDecode(event);
          if (decoded is Map) {
            unawaited(_handleMessage(Map<String, dynamic>.from(decoded)));
          }
        } catch (error) {
          debugPrint('Ignoring malformed voice-call message: $error');
        }
      },
      onError: (Object error) {
        debugPrint('Voice-call connection error: $error');
        _handleChannelClosed(channel);
      },
      onDone: () => _handleChannelClosed(channel),
      cancelOnError: false,
    );
    try {
      await channel.ready;
    } catch (error) {
      debugPrint('Could not connect voice-call signaling: $error');
      _handleChannelClosed(channel);
    }
  }

  void _handleChannelClosed(WebSocketChannel channel) {
    if (!identical(_channel, channel)) return;
    _channel = null;
    _subscription = null;
    if (_shouldReconnect && !_disposed && _reconnectTimer == null) {
      _reconnectTimer = Timer(const Duration(seconds: 2), () {
        _reconnectTimer = null;
        unawaited(_openChannel());
      });
    }
  }

  Future<void> disconnect() async {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    if (call != null) await endCall();
    final channel = _channel;
    _channel = null;
    await _subscription?.cancel();
    _subscription = null;
    await channel?.sink.close();
  }

  Future<void> startCall(
    String peerId,
    String peerName, {
    bool withVideo = false,
  }) async {
    if (call != null) throw StateError('Finish your current call first.');
    if (!isConnected) {
      final playerId = _playerId;
      if (playerId != null) await connect(playerId);
    }
    if (!isConnected) {
      throw StateError('Voice calling is reconnecting. Try again.');
    }
    final callId = DateTime.now().microsecondsSinceEpoch.toString();
    call = VoiceCallSession(
      callId: callId,
      peerId: peerId,
      peerName: peerName,
      phase: VoiceCallPhase.outgoing,
      withVideo: withVideo,
    );
    isCallUiMinimized = false;
    lastError = null;
    notifyListeners();
    _send('voice_call_request', peerId, callId, withVideo: withVideo);
    _startTimeout(callId);
    unawaited(_startRingtone());
  }

  Future<void> acceptIncomingCall() async {
    final current = call;
    if (current == null || current.phase != VoiceCallPhase.incoming) return;
    await _stopRingtone();
    call = current.copyWith(phase: VoiceCallPhase.connecting);
    notifyListeners();
    if (!await _preparePeer()) {
      _send('voice_call_decline', current.peerId, current.callId);
      await _clearCall();
      lastError = current.withVideo
          ? 'Camera and microphone access are needed for video calls.'
          : 'Microphone access is needed for voice calls.';
      notifyListeners();
      return;
    }
    _send('voice_call_accept', current.peerId, current.callId);
    _startTimeout(current.callId);
  }

  void declineIncomingCall() {
    final current = call;
    if (current == null || current.phase != VoiceCallPhase.incoming) return;
    _send('voice_call_decline', current.peerId, current.callId);
    unawaited(_clearCall());
  }

  Future<void> endCall() async {
    final current = call;
    if (current != null) {
      _send('voice_call_end', current.peerId, current.callId);
    }
    await _clearCall();
  }

  Future<void> toggleMute() async {
    final current = call;
    if (current == null || current.phase != VoiceCallPhase.connected) return;
    final muted = !current.muted;
    for (final track
        in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !muted;
    }
    call = current.copyWith(muted: muted);
    notifyListeners();
  }

  void _send(
    String type,
    String targetPlayerId,
    String callId, {
    bool? withVideo,
    Map<String, dynamic>? description,
    Map<String, dynamic>? candidate,
  }) {
    final channel = _channel;
    if (!isConnected || channel == null) return;
    channel.sink.add(jsonEncode({
      'type': type,
      'targetPlayerId': targetPlayerId,
      'callId': callId,
      if (withVideo != null) 'withVideo': withVideo,
      if (description != null) 'description': description,
      if (candidate != null) 'candidate': candidate,
    }));
  }

  Future<void> _handleMessage(Map<String, dynamic> message) async {
    final type = message['type']?.toString();
    if (type == 'error') {
      final code = message['code']?.toString();
      if (code != 'VOICE_CONNECTION_REJECTED') {
        lastError = message['message']?.toString() ?? 'Voice call failed.';
      }
      await _clearCall();
      notifyListeners();
      return;
    }
    final fromId = message['fromPlayerId']?.toString();
    final callId = message['callId']?.toString();
    if (type == null || fromId == null || callId == null) return;

    if (type == 'voice_call_incoming') {
      if (call != null) {
        _send('voice_call_decline', fromId, callId);
        return;
      }
      call = VoiceCallSession(
        callId: callId,
        peerId: fromId,
        peerName: message['fromPlayerName']?.toString() ?? 'Buddy',
        phase: VoiceCallPhase.incoming,
        withVideo: message['withVideo'] == true,
      );
      isCallUiMinimized = false;
      notifyListeners();
      unawaited(_startRingtone());
      return;
    }

    final current = call;
    if (current == null ||
        current.callId != callId ||
        current.peerId != fromId) {
      return;
    }
    switch (type) {
      case 'voice_call_accept':
        await _stopRingtone();
        if (!await _preparePeer()) {
          await endCall();
          lastError = current.withVideo
              ? 'Camera and microphone access are needed for video calls.'
              : 'Microphone access is needed for voice calls.';
          notifyListeners();
          return;
        }
        call = current.copyWith(phase: VoiceCallPhase.connecting);
        notifyListeners();
        final offer = await _peerConnection!.createOffer();
        await _peerConnection!.setLocalDescription(offer);
        _send('voice_call_offer', fromId, callId,
            description: offer.toMap().cast<String, dynamic>());
        return;
      case 'voice_call_offer':
        if (_peerConnection == null && !await _preparePeer()) return;
        final description = message['description'];
        if (description is! Map) return;
        await _peerConnection!.setRemoteDescription(RTCSessionDescription(
          description['sdp']?.toString(),
          description['type']?.toString(),
        ));
        await _applyQueuedCandidates();
        final answer = await _peerConnection!.createAnswer();
        await _peerConnection!.setLocalDescription(answer);
        _send('voice_call_answer', fromId, callId,
            description: answer.toMap().cast<String, dynamic>());
        return;
      case 'voice_call_answer':
        final answer = message['description'];
        if (answer is! Map || _peerConnection == null) return;
        await _peerConnection!.setRemoteDescription(RTCSessionDescription(
          answer['sdp']?.toString(),
          answer['type']?.toString(),
        ));
        await _applyQueuedCandidates();
        return;
      case 'voice_call_ice':
        final candidate = message['candidate'];
        if (candidate is! Map) return;
        final rtcCandidate = RTCIceCandidate(
          candidate['candidate']?.toString(),
          candidate['sdpMid']?.toString(),
          (candidate['sdpMLineIndex'] as num?)?.toInt(),
        );
        if (await _peerConnection?.getRemoteDescription() == null) {
          _queuedCandidates.add(rtcCandidate);
        } else {
          await _peerConnection?.addCandidate(rtcCandidate);
        }
        return;
      case 'voice_call_decline':
        await _clearCall();
        lastError = '${current.peerName} declined the call.';
        notifyListeners();
        return;
      case 'voice_call_end':
        await _clearCall();
        lastError = 'Voice call ended.';
        notifyListeners();
        return;
    }
  }

  Future<bool> _preparePeer() async {
    if (_peerConnection != null) return true;
    try {
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': call?.withVideo == true,
      });
      final peer = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ],
      });
      _localStream = stream;
      _remoteStream = null;
      _peerConnection = peer;
      for (final track in stream.getTracks()) {
        await peer.addTrack(track, stream);
      }
      peer.onIceCandidate = (candidate) {
        final current = call;
        if (current == null || candidate.candidate == null) return;
        _send('voice_call_ice', current.peerId, current.callId,
            candidate: candidate.toMap().cast<String, dynamic>());
      };
      peer.onTrack = (event) {
        if (event.streams.isEmpty) return;
        _remoteStream = event.streams.first;
        notifyListeners();
      };
      peer.onConnectionState = (state) {
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _callTimeout?.cancel();
          final current = call;
          if (current != null) {
            call = current.copyWith(phase: VoiceCallPhase.connected);
            unawaited(_stopRingtone());
            notifyListeners();
          }
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          lastError = 'Could not connect the voice call.';
          unawaited(endCall());
        }
      };
      return true;
    } catch (error) {
      debugPrint('Could not start voice call media: $error');
      return false;
    }
  }

  Future<void> _applyQueuedCandidates() async {
    final peer = _peerConnection;
    if (peer == null) return;
    for (final candidate in _queuedCandidates) {
      await peer.addCandidate(candidate);
    }
    _queuedCandidates.clear();
  }

  void _startTimeout(String callId) {
    _callTimeout?.cancel();
    _callTimeout = Timer(const Duration(seconds: 30), () {
      if (call?.callId != callId || call?.phase == VoiceCallPhase.connected) {
        return;
      }
      lastError = 'No answer. The voice call was ended.';
      unawaited(endCall());
    });
  }

  Future<void> _clearCall() async {
    _callTimeout?.cancel();
    _callTimeout = null;
    await _stopRingtone();
    final peer = _peerConnection;
    final stream = _localStream;
    _peerConnection = null;
    _localStream = null;
    _remoteStream = null;
    _queuedCandidates.clear();
    call = null;
    isCallUiMinimized = false;
    if (!_disposed) notifyListeners();
    if (stream != null) {
      for (final track in stream.getTracks()) {
        await track.stop();
      }
      await stream.dispose();
    }
    await peer?.close();
    await peer?.dispose();
  }

  void minimizeCallUi() {
    if (call == null || isCallUiMinimized) return;
    isCallUiMinimized = true;
    notifyListeners();
  }

  void restoreCallUi() {
    if (call == null || !isCallUiMinimized) return;
    isCallUiMinimized = false;
    notifyListeners();
  }

  Future<void> _startRingtone() async {
    final generation = ++_ringtoneGeneration;
    try {
      await _ringtonePlayer.setReleaseMode(ReleaseMode.loop);
      if (generation != _ringtoneGeneration || _disposed) return;
      await _ringtonePlayer.play(AssetSource('audio/ring.mp3'));
      if (generation != _ringtoneGeneration || _disposed) {
        await _ringtonePlayer.stop();
      }
    } catch (error) {
      debugPrint('Could not play the voice-call ringtone: $error');
    }
  }

  Future<void> _stopRingtone() async {
    _ringtoneGeneration++;
    try {
      await _ringtonePlayer.stop();
    } catch (error) {
      debugPrint('Could not stop the voice-call ringtone: $error');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _ringtoneGeneration++;
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _callTimeout?.cancel();
    unawaited(_ringtonePlayer.stop());
    unawaited(_ringtonePlayer.dispose());
    unawaited(_subscription?.cancel());
    unawaited(_channel?.sink.close());
    unawaited(_peerConnection?.close());
    final stream = _localStream;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        unawaited(track.stop());
      }
      unawaited(stream.dispose());
    }
    super.dispose();
  }
}
