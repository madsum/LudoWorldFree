class AppConstants {
  AppConstants._();

  static const String appName = 'Ludo World Free';
  static const String appSubtitle =
      'Play with friends across the world for FREE';
  static const String publisher = 'iProSoft';
  static const String appVersion = '1.0.0';

  // Production Spring Boot Backend & WebSocket Endpoints
  static const String prodApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue:
        'https://ludo-websocket-backend-7rhnb54xmq-ew.a.run.app/api/v1',
  );
  static const String prodWebSocketUrl = String.fromEnvironment(
    'WEBSOCKET_URL',
    defaultValue: 'wss://ludo-websocket-backend-7rhnb54xmq-ew.a.run.app/ws',
  );

  static const String devApiBaseUrl = 'http://10.0.2.2:8080/api/v1';
  static const String devWebSocketUrl = 'ws://10.0.2.2:8080/ws';
  static const String defaultApiBaseUrl = prodApiBaseUrl;
  static const String defaultWebSocketUrl = prodWebSocketUrl;

  static const String keyAccessToken = 'access_token';
  static const String keyRefreshToken = 'refresh_token';
  static const String keyUserId = 'user_id';
  static const String keyUserName = 'user_name';
  static const String keyIsGuest = 'is_guest';
}
