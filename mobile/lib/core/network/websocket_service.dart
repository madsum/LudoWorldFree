import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../constants/app_constants.dart';

final webSocketServiceProvider = Provider<WebSocketService>((ref) {
  final service = WebSocketService();
  ref.onDispose(service.dispose);
  return service;
});

class WebSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  final StreamController<Map<String, dynamic>> _messageStreamController =
      StreamController<Map<String, dynamic>>.broadcast();
  Completer<bool>? _roomReadyCompleter;
  Completer<int>? _diceRollCompleter;
  int? _pendingDiceRollOpportunityId;
  String? _roomId;
  String? _playerId;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  DateTime _lastPongAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _reconnectAttempts = 0;
  bool _shouldReconnect = false;
  bool _hasConnectedToRoom = false;

  Stream<Map<String, dynamic>> get messageStream =>
      _messageStreamController.stream;
  bool get isConnected => _channel != null && _channel!.closeCode == null;

  Future<bool> connectToRoom({
    required String roomId,
    required String playerId,
  }) async {
    await leaveRoom();
    _roomId = roomId;
    _playerId = playerId;
    _shouldReconnect = true;
    final baseUri = Uri.parse(AppConstants.defaultWebSocketUrl);
    final readyCompleter = Completer<bool>();
    _roomReadyCompleter = readyCompleter;
    try {
      await _openSocket(baseUri);
      return await readyCompleter.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () => false,
      );
    } catch (e) {
      debugPrint('[WebSocket] Could not join the game room: $e');
      await leaveRoom();
      return false;
    }
  }

  Future<void> _openSocket(Uri baseUri) async {
    final roomId = _roomId;
    final playerId = _playerId;
    if (!_shouldReconnect || roomId == null || playerId == null) return;
    final wsUrl = baseUri.replace(
      path: '/ws/game',
      queryParameters: {'roomId': roomId, 'playerId': playerId},
    );
    final channel = WebSocketChannel.connect(wsUrl);
    _channel = channel;
    _lastPongAt = DateTime.now();
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!identical(_channel, channel) || !_shouldReconnect) return;
      if (DateTime.now().difference(_lastPongAt) >
          const Duration(seconds: 45)) {
        channel.sink.close();
        _handleSocketClosed(channel);
        return;
      }
      _send({'type': 'ping'});
    });
    debugPrint('[WebSocket] Connecting to game room: $wsUrl');
    _subscription = channel.stream.listen(
      (data) {
        try {
          final decoded = jsonDecode(data.toString());
          if (decoded is! Map) return;
          final message = Map<String, dynamic>.from(decoded);
          if (message['type'] == 'pong') _lastPongAt = DateTime.now();
          if (message['type'] == 'dice_roll' &&
              message['rollOpportunityId'] == _pendingDiceRollOpportunityId) {
            final completer = _diceRollCompleter;
            final value = message['value'];
            if (completer != null && !completer.isCompleted && value is num) {
              completer.complete(value.toInt());
            }
          }
          if (message['type'] == 'error' &&
              message['code'] == 'ROLL_REJECTED') {
            final completer = _diceRollCompleter;
            if (completer != null && !completer.isCompleted) {
              completer
                  .completeError(StateError('Server rejected the dice roll.'));
            }
          }
          final readyCompleter = _roomReadyCompleter;
          if (message['type'] == 'room_ready') {
            _reconnectAttempts = 0;
            final wasConnectedBefore = _hasConnectedToRoom;
            if (!_hasConnectedToRoom &&
                readyCompleter != null &&
                !readyCompleter.isCompleted) {
              readyCompleter.complete(true);
            }
            _hasConnectedToRoom = true;
            if (wasConnectedBefore && !_messageStreamController.isClosed) {
              _messageStreamController.add({'type': 'connection_restored'});
            }
          } else if (message['type'] == 'error' &&
              readyCompleter != null &&
              !readyCompleter.isCompleted) {
            readyCompleter.complete(false);
          }
          if (message['type'] == 'match_finished') {
            _shouldReconnect = false;
            _reconnectTimer?.cancel();
            _reconnectTimer = null;
          }
          _messageStreamController.add(message);
        } catch (error) {
          debugPrint('[WebSocket] Ignored malformed server message: $error');
        }
      },
      onError: (error) {
        debugPrint('[WebSocket] Connection error: $error');
        if (identical(_channel, channel)) _handleSocketClosed(channel);
      },
      onDone: () {
        if (identical(_channel, channel)) _handleSocketClosed(channel);
      },
    );
    await channel.ready;
  }

  void _handleSocketClosed(WebSocketChannel channel) {
    if (!identical(_channel, channel)) return;
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    final readyCompleter = _roomReadyCompleter;
    if (!_hasConnectedToRoom &&
        readyCompleter != null &&
        !readyCompleter.isCompleted) {
      readyCompleter.complete(false);
    }
    if (!_shouldReconnect) return;
    if (!_messageStreamController.isClosed) {
      _messageStreamController.add({'type': 'connection_lost'});
    }
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect || _reconnectTimer?.isActive == true) return;
    if (_reconnectAttempts >= 8) {
      if (!_messageStreamController.isClosed) {
        _messageStreamController.add({'type': 'connection_failed'});
      }
      return;
    }
    final delaySeconds = (1 << _reconnectAttempts).clamp(1, 20);
    _reconnectAttempts++;
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      _reconnectTimer = null;
      if (!_shouldReconnect) return;
      try {
        await _openSocket(Uri.parse(AppConstants.defaultWebSocketUrl));
      } catch (error) {
        debugPrint('[WebSocket] Reconnect attempt failed: $error');
        _scheduleReconnect();
      }
    });
  }

  void sendGameState(Map<String, dynamic> state) {
    _send({'type': 'game_state', 'state': state});
  }

  void sendChatMessage(String text) {
    final message = text.trim();
    if (message.isEmpty || message.length > 200) return;
    _send({'type': 'chat', 'text': message});
  }

  void sendBellAlert(String targetPlayerId) {
    if (!isConnected || targetPlayerId.isEmpty) return;
    _send({'type': 'bell_alert', 'targetPlayerId': targetPlayerId});
  }

  void forfeitDisconnectedOpponent(String disconnectedPlayerId) {
    if (!isConnected || disconnectedPlayerId.isEmpty) return;
    _send({
      'type': 'forfeit_disconnected',
      'disconnectedPlayerId': disconnectedPlayerId,
    });
  }

  bool requestRematch() {
    if (!isConnected) return false;
    _send({'type': 'rematch_request'});
    return true;
  }

  void sendRematchResponse(String roundId, bool accept) {
    _send({
      'type': 'rematch_response',
      'roundId': roundId,
      'accept': accept,
    });
  }

  Future<int> requestDiceRoll(int rollOpportunityId) {
    if (!isConnected) {
      return Future<int>.error(StateError('The game server is disconnected.'));
    }
    final pending = _diceRollCompleter;
    if (pending != null &&
        !pending.isCompleted &&
        _pendingDiceRollOpportunityId == rollOpportunityId) {
      return pending.future;
    }
    final completer = Completer<int>();
    _diceRollCompleter = completer;
    _pendingDiceRollOpportunityId = rollOpportunityId;
    _send({'type': 'roll_request', 'rollOpportunityId': rollOpportunityId});
    return completer.future.timeout(const Duration(seconds: 12), onTimeout: () {
      throw TimeoutException('Timed out waiting for a server dice roll.');
    }).whenComplete(() {
      if (identical(_diceRollCompleter, completer)) {
        _diceRollCompleter = null;
        _pendingDiceRollOpportunityId = null;
      }
    });
  }

  Future<void> leaveRoom() async {
    final channel = _channel;
    final wasConnected = channel != null && channel.closeCode == null;
    if (wasConnected) _send({'type': 'leave'});
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    // Give the server time to persist the leave and deliver match_finished to
    // players connected through another backend instance before closing TCP.
    if (wasConnected) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    if (channel != null && _channel != null && !identical(_channel, channel)) {
      return;
    }
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _roomId = null;
    _playerId = null;
    _hasConnectedToRoom = false;
    final readyCompleter = _roomReadyCompleter;
    _roomReadyCompleter = null;
    if (readyCompleter != null && !readyCompleter.isCompleted) {
      readyCompleter.complete(false);
    }
    final diceCompleter = _diceRollCompleter;
    _diceRollCompleter = null;
    _pendingDiceRollOpportunityId = null;
    if (diceCompleter != null && !diceCompleter.isCompleted) {
      diceCompleter.completeError(StateError('The game room was closed.'));
    }
  }

  void _send(Map<String, dynamic> payload) {
    if (!isConnected) return;
    try {
      _channel!.sink.add(jsonEncode(payload));
    } catch (error) {
      debugPrint('[WebSocket] Could not send game update: $error');
    }
  }

  /// Disconnects the active WebSocket channel
  void disconnect() {
    unawaited(leaveRoom());
  }

  void dispose() {
    disconnect();
    _messageStreamController.close();
  }
}
