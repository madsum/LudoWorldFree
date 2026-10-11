import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../constants/app_constants.dart';

final webSocketServiceProvider = Provider<WebSocketService>((ref) {
  return WebSocketService();
});

class WebSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  final StreamController<String> _messageStreamController =
      StreamController<String>.broadcast();

  Stream<String> get messageStream => _messageStreamController.stream;
  bool get isConnected => _channel != null;

  /// Connects to the Google Cloud Run Production WebSocket Backend Endpoint
  void connect({String? customWsUrl}) {
    if (_channel != null) return;

    final urlString = customWsUrl ?? AppConstants.defaultWebSocketUrl;
    final wsUrl = Uri.parse(urlString);

    try {
      debugPrint('🔌 [WebSocket] Connecting to Google Cloud Run: $wsUrl');
      _channel = WebSocketChannel.connect(wsUrl);

      _subscription = _channel!.stream.listen(
        (data) {
          debugPrint('📥 [WebSocket Message Received]: $data');
          _messageStreamController.add(data.toString());
        },
        onError: (error) {
          debugPrint('❌ [WebSocket Error]: $error');
          disconnect();
        },
        onDone: () {
          debugPrint('⚠️ [WebSocket Connection Closed]');
          disconnect();
        },
      );
    } catch (e) {
      debugPrint('❌ [WebSocket Connection Failed]: $e');
      disconnect();
    }
  }

  /// Sends raw payload string or JSON string to WebSocket server
  void sendMessage(String message) {
    if (_channel != null) {
      debugPrint('📤 [WebSocket Sending]: $message');
      _channel!.sink.add(message);
    } else {
      debugPrint('⚠️ [WebSocket Not Connected] Attempting auto-reconnect...');
      connect();
      _channel?.sink.add(message);
    }
  }

  /// Disconnects the active WebSocket channel
  void disconnect() {
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    debugPrint('🔌 [WebSocket] Disconnected cleanly.');
  }

  void dispose() {
    disconnect();
    _messageStreamController.close();
  }
}
