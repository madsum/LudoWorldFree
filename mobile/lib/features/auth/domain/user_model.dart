enum AuthProvider {
  google,
  facebook,
  apple,
  linkedin,
  twitter,
  github,
  guest,
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

  const UserModel({
    required this.id,
    required this.name,
    this.email,
    this.avatarUrl,
    this.country = 'Netherlands',
    this.countryFlag = '🇳🇱',
    required this.isGuest,
    required this.authProvider,
    this.diamonds = 50,
    this.coins = 2350,
  });

  factory UserModel.guest({
    String? id,
    String name = 'Guest Player',
    String avatarUrl = 'avatar_crown',
    String country = 'Netherlands',
    String countryFlag = '🇳🇱',
  }) {
    return UserModel(
      id: id ?? 'guest_${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
      name: name,
      avatarUrl: avatarUrl,
      country: country,
      countryFlag: countryFlag,
      isGuest: true,
      authProvider: AuthProvider.guest,
      diamonds: 50,
      coins: 2350,
    );
  }

  factory UserModel.fromOAuth({
    required String id,
    required String name,
    required String email,
    String? avatarUrl,
    String country = 'Netherlands',
    String countryFlag = '🇳🇱',
    required AuthProvider provider,
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
      diamonds: 100, // Welcome bonus for social login
      coins: 5000,
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
    );
  }
}
