import 'dart:async';
import 'dart:convert';

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
  });

  final String callId;
  final String peerId;
  final String peerName;
  final VoiceCallPhase phase;
  final bool muted;

  VoiceCallSession copyWith({VoiceCallPhase? phase, bool? muted}) =>
      VoiceCallSession(
        callId: callId,
        peerId: peerId,
        peerName: peerName,
        phase: phase ?? this.phase,
        muted: muted ?? this.muted,
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
  MediaStream? _localStream;
  RTCPeerConnection? _peerConnection;
  final List<RTCIceCandidate> _queuedCandidates = [];

  VoiceCallSession? call;
  String? lastError;

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

  Future<void> startCall(String peerId, String peerName) async {
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
    );
    lastError = null;
    notifyListeners();
    _send('voice_call_request', peerId, callId);
    _startTimeout(callId);
  }

  Future<void> acceptIncomingCall() async {
    final current = call;
    if (current == null || current.phase != VoiceCallPhase.incoming) return;
    call = current.copyWith(phase: VoiceCallPhase.connecting);
    notifyListeners();
    if (!await _preparePeer()) {
      _send('voice_call_decline', current.peerId, current.callId);
      await _clearCall();
      lastError = 'Microphone access is needed for voice calls.';
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
    Map<String, dynamic>? description,
    Map<String, dynamic>? candidate,
  }) {
    final channel = _channel;
    if (!isConnected || channel == null) return;
    channel.sink.add(jsonEncode({
      'type': type,
      'targetPlayerId': targetPlayerId,
      'callId': callId,
      if (description != null) 'description': description,
      if (candidate != null) 'candidate': candidate,
    }));
  }

  Future<void> _handleMessage(Map<String, dynamic> message) async {
    final type = message['type']?.toString();
    if (type == 'error') {
      lastError = message['message']?.toString() ?? 'Voice call failed.';
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
      );
      notifyListeners();
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
        if (!await _preparePeer()) {
          await endCall();
          lastError = 'Microphone access is needed for voice calls.';
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
        'video': false,
      });
      final peer = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ],
      });
      _localStream = stream;
      _peerConnection = peer;
      for (final track in stream.getAudioTracks()) {
        await peer.addTrack(track, stream);
      }
      peer.onIceCandidate = (candidate) {
        final current = call;
        if (current == null || candidate.candidate == null) return;
        _send('voice_call_ice', current.peerId, current.callId,
            candidate: candidate.toMap().cast<String, dynamic>());
      };
      peer.onConnectionState = (state) {
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _callTimeout?.cancel();
          final current = call;
          if (current != null) {
            call = current.copyWith(phase: VoiceCallPhase.connected);
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
    final peer = _peerConnection;
    final stream = _localStream;
    _peerConnection = null;
    _localStream = null;
    _queuedCandidates.clear();
    call = null;
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

  @override
  void dispose() {
    _disposed = true;
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _callTimeout?.cancel();
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
