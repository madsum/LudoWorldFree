import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/app_constants.dart';

final secureStorageServiceProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

class SecureStorageService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<void> saveAccessToken(String token) async {
    await _storage.write(key: AppConstants.keyAccessToken, value: token);
  }

  Future<String?> getAccessToken() async {
    return await _storage.read(key: AppConstants.keyAccessToken);
  }

  Future<void> saveUserData({
    required String userId,
    required String userName,
    required bool isGuest,
    String? userEmail,
    String? avatarUrl,
    String? country,
    String? countryFlag,
    int? coins,
    int? diamonds,
    String? preferredGameType,
    String? mostPlayedGameType,
  }) async {
    final writes = <Future<void>>[
      _storage.write(key: AppConstants.keyUserId, value: userId),
      _storage.write(key: AppConstants.keyUserName, value: userName),
      _storage.write(key: AppConstants.keyIsGuest, value: isGuest.toString()),
    ];
    if (userEmail != null) {
      writes.add(_storage.write(key: 'user_email', value: userEmail));
    }
    if (avatarUrl != null) {
      writes.add(_storage.write(key: 'user_avatar', value: avatarUrl));
    }
    if (country != null) {
      writes.add(_storage.write(key: 'user_country', value: country));
    }
    if (countryFlag != null) {
      writes.add(_storage.write(key: 'user_country_flag', value: countryFlag));
    }
    if (coins != null) {
      writes.add(_storage.write(key: 'user_coins', value: coins.toString()));
    }
    if (diamonds != null) {
      writes.add(
        _storage.write(key: 'user_diamonds', value: diamonds.toString()),
      );
    }
    if (preferredGameType != null) {
      writes.add(_storage.write(key: 'preferred_game_type', value: preferredGameType));
    }
    if (mostPlayedGameType != null) {
      writes.add(_storage.write(key: 'most_played_game_type', value: mostPlayedGameType));
    }
    await Future.wait(writes);
  }

  Future<Map<String, String?>> getUserData() async {
    final values = await Future.wait([
      _storage.read(key: AppConstants.keyUserId),
      _storage.read(key: AppConstants.keyUserName),
      _storage.read(key: 'user_email'),
      _storage.read(key: AppConstants.keyIsGuest),
      _storage.read(key: 'user_avatar'),
      _storage.read(key: 'user_country'),
      _storage.read(key: 'user_country_flag'),
      _storage.read(key: 'user_coins'),
      _storage.read(key: 'user_diamonds'),
      _storage.read(key: 'preferred_game_type'),
      _storage.read(key: 'most_played_game_type'),
    ]);

    return {
      'userId': values[0],
      'userName': values[1],
      'userEmail': values[2],
      'isGuest': values[3],
      'avatarUrl': values[4],
      'country': values[5],
      'countryFlag': values[6],
      'coins': values[7],
      'diamonds': values[8],
      'preferredGameType': values[9],
      'mostPlayedGameType': values[10],
    };
  }

  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
