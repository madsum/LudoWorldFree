enum AuthProvider {
  google,
  facebook,
  apple,
  linkedin,
  twitter,
  github,
  guest,
}

enum GameType {
  classic,
  quick,
  teamUp,
  computer,
  passNPlay;

  String get displayName {
    switch (this) {
      case GameType.classic:
        return 'Classic';
      case GameType.quick:
        return 'Quick';
      case GameType.teamUp:
        return 'Team Up';
      case GameType.computer:
        return 'Vs Computer';
      case GameType.passNPlay:
        return 'Pass & Play';
    }
  }

  String get apiName {
    switch (this) {
      case GameType.classic:
        return 'CLASSIC';
      case GameType.quick:
        return 'QUICK';
      case GameType.teamUp:
        return 'TEAM_UP';
      case GameType.computer:
        return 'COMPUTER';
      case GameType.passNPlay:
        return 'PASS_N_PLAY';
    }
  }

  static GameType parse(String? value) {
    if (value == null) return GameType.classic;
    final normalized = value.toLowerCase().replaceAll('_', '').replaceAll(' ', '');
    if (normalized.contains('quick')) return GameType.quick;
    if (normalized.contains('team')) return GameType.teamUp;
    if (normalized.contains('computer')) return GameType.computer;
    if (normalized.contains('pass')) return GameType.passNPlay;
    return GameType.classic;
  }
}

class UserModel {
  final String id;
  final String name;
  final String? email;
  final String? avatarUrl;
  final String country;
  final String countryFlag;
  final bool isGuest;
  final AuthProvider authProvider;
  final int diamonds;
  final int coins;
  final GameType preferredGameType;
  final GameType mostPlayedGameType;

  const UserModel({
    required this.id,
    required this.name,
    this.email,
    this.avatarUrl,
    this.country = 'World',
    this.countryFlag = '🌐',
    required this.isGuest,
    required this.authProvider,
    this.diamonds = 100,
    this.coins = 2000,
    this.preferredGameType = GameType.classic,
    this.mostPlayedGameType = GameType.classic,
  });

  factory UserModel.guest({
    String? id,
    String name = 'Guest Player',
    String avatarUrl = 'assets/images/black-mask.webp',
    String country = 'World',
    String countryFlag = '🌐',
    GameType preferredGameType = GameType.classic,
    GameType mostPlayedGameType = GameType.classic,
  }) {
    return UserModel(
      id: id ?? 'guest_${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
      name: name,
      avatarUrl: avatarUrl,
      country: country,
      countryFlag: countryFlag,
      isGuest: true,
      authProvider: AuthProvider.guest,
      diamonds: 100,
      coins: 2000,
      preferredGameType: preferredGameType,
      mostPlayedGameType: mostPlayedGameType,
    );
  }

  factory UserModel.fromOAuth({
    required String id,
    required String name,
    required String email,
    String? avatarUrl,
    String country = 'World',
    String countryFlag = '🌐',
    required AuthProvider provider,
    GameType preferredGameType = GameType.classic,
    GameType mostPlayedGameType = GameType.classic,
  }) {
    return UserModel(
      id: id,
      name: name,
      email: email,
      avatarUrl: avatarUrl,
      country: country,
      countryFlag: countryFlag,
      isGuest: false,
      authProvider: provider,
      diamonds: 100,
      coins: 5000,
      preferredGameType: preferredGameType,
      mostPlayedGameType: mostPlayedGameType,
    );
  }

  UserModel copyWith({
    String? name,
    String? email,
    String? avatarUrl,
    String? country,
    String? countryFlag,
    int? diamonds,
    int? coins,
    GameType? preferredGameType,
    GameType? mostPlayedGameType,
  }) {
    return UserModel(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      country: country ?? this.country,
      countryFlag: countryFlag ?? this.countryFlag,
      isGuest: isGuest,
      authProvider: authProvider,
      diamonds: diamonds ?? this.diamonds,
      coins: coins ?? this.coins,
      preferredGameType: preferredGameType ?? this.preferredGameType,
      mostPlayedGameType: mostPlayedGameType ?? this.mostPlayedGameType,
    );
  }
}
