enum EnvironmentType { dev, staging, prod }

class Environment {
  static EnvironmentType type = EnvironmentType.dev;

  static String get baseUrl {
    switch (type) {
      case EnvironmentType.dev:
        return 'http://10.0.2.2:8080/api/v1';
      case EnvironmentType.staging:
        return 'https://staging-api.ludoworldfree.com/api/v1';
      case EnvironmentType.prod:
        return 'https://api.ludoworldfree.com/api/v1';
    }
  }

  static String get webSocketUrl {
    switch (type) {
      case EnvironmentType.dev:
        return 'ws://10.0.2.2:8080/ws';
      case EnvironmentType.staging:
        return 'wss://staging-api.ludoworldfree.com/ws';
      case EnvironmentType.prod:
        return 'wss://api.ludoworldfree.com/ws';
    }
  }
}
