import '../core/constants/app_constants.dart';

enum EnvironmentType { dev, staging, prod }

class Environment {
  static EnvironmentType type = EnvironmentType.dev;

  static String get baseUrl {
    switch (type) {
      case EnvironmentType.dev:
        return 'http://10.0.2.2:8080/api/v1';
      case EnvironmentType.staging:
        return AppConstants.prodApiBaseUrl;
      case EnvironmentType.prod:
        return AppConstants.defaultApiBaseUrl;
    }
  }

  static String get webSocketUrl {
    switch (type) {
      case EnvironmentType.dev:
        return 'ws://10.0.2.2:8080/ws';
      case EnvironmentType.staging:
        return AppConstants.prodWebSocketUrl;
      case EnvironmentType.prod:
        return AppConstants.defaultWebSocketUrl;
    }
  }
}
