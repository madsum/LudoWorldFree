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
  }) async {
    await _storage.write(key: AppConstants.keyUserId, value: userId);
    await _storage.write(key: AppConstants.keyUserName, value: userName);
    await _storage.write(key: AppConstants.keyIsGuest, value: isGuest.toString());
    if (userEmail != null) {
      await _storage.write(key: 'user_email', value: userEmail);
    }
    if (avatarUrl != null) {
      await _storage.write(key: 'user_avatar', value: avatarUrl);
    }
    if (country != null) {
      await _storage.write(key: 'user_country', value: country);
    }
    if (countryFlag != null) {
      await _storage.write(key: 'user_country_flag', value: countryFlag);
    }
    if (coins != null) {
      await _storage.write(key: 'user_coins', value: coins.toString());
    }
    if (diamonds != null) {
      await _storage.write(key: 'user_diamonds', value: diamonds.toString());
    }
  }

  Future<Map<String, String?>> getUserData() async {
    final userId = await _storage.read(key: AppConstants.keyUserId);
    final userName = await _storage.read(key: AppConstants.keyUserName);
    final userEmail = await _storage.read(key: 'user_email');
    final isGuest = await _storage.read(key: AppConstants.keyIsGuest);
    final avatarUrl = await _storage.read(key: 'user_avatar');
    final country = await _storage.read(key: 'user_country');
    final countryFlag = await _storage.read(key: 'user_country_flag');
    final coins = await _storage.read(key: 'user_coins');
    final diamonds = await _storage.read(key: 'user_diamonds');

    return {
      'userId': userId,
      'userName': userName,
      'userEmail': userEmail,
      'isGuest': isGuest,
      'avatarUrl': avatarUrl,
      'country': country,
      'countryFlag': countryFlag,
      'coins': coins,
      'diamonds': diamonds,
    };
  }

  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
