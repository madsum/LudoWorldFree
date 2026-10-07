import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/oauth_config.dart';
import '../../../core/storage/secure_storage_service.dart';
import '../domain/auth_repository.dart';
import '../domain/user_model.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final storageService = ref.watch(secureStorageServiceProvider);
  final dio = ref.watch(apiClientProvider);
  return AuthRepositoryImpl(storageService, dio);
});

class AuthRepositoryImpl implements AuthRepository {
  final SecureStorageService _storageService;
  final Dio _dio;

  AuthRepositoryImpl(this._storageService, this._dio);

  @override
  Future<UserModel?> getCurrentUser() async {
    final userData = await _storageService.getUserData();
    if (userData['userId'] == null) return null;

    final isGuest = userData['isGuest'] == 'true';
    final coins = int.tryParse(userData['coins'] ?? '') ?? (isGuest ? 2350 : 5000);
    final diamonds = int.tryParse(userData['diamonds'] ?? '') ?? (isGuest ? 50 : 100);

    if (isGuest) {
      return UserModel(
        id: userData['userId']!,
        name: userData['userName'] ?? 'Guest Player',
        avatarUrl: userData['avatarUrl'] ?? 'assets/images/black-mask.webp',
        country: userData['country'] ?? 'Netherlands',
        countryFlag: userData['countryFlag'] ?? '🇳🇱',
        isGuest: true,
        authProvider: AuthProvider.guest,
        coins: coins,
        diamonds: diamonds,
      );
    }

    return UserModel(
      id: userData['userId']!,
      name: userData['userName'] ?? 'Player',
      email: userData['userEmail'] ?? 'player@ludoworldfree.com',
      avatarUrl: userData['avatarUrl'],
      country: userData['country'] ?? 'Netherlands',
      countryFlag: userData['countryFlag'] ?? '🇳🇱',
      isGuest: false,
      authProvider: AuthProvider.google,
      coins: coins,
      diamonds: diamonds,
    );
  }

  @override
  Future<UserModel> addGoldReward({
    required int amount,
    required String providerRewardId,
  }) async {
    final current = await getCurrentUser() ?? UserModel.guest();
    int newCoins = current.coins + amount;

    try {
      final response = await _dio.post(
        '/api/v1/rewards/ad-reward',
        data: {
          'providerRewardId': providerRewardId,
          'amount': amount,
        },
        options: Options(
          headers: {'X-Player-ID': current.id},
        ),
      );

      if (response.data != null && response.data['balance'] != null) {
        newCoins = (response.data['balance'] as num).toInt();
      }
    } catch (_) {}

    final updated = current.copyWith(coins: newCoins);

    await _saveAuthSession(
      token: await _storageService.getAccessToken() ?? 'user_token',
      userId: updated.id,
      userName: updated.name,
      userEmail: updated.email ?? '',
      avatarUrl: updated.avatarUrl,
      country: updated.country,
      countryFlag: updated.countryFlag,
      coins: updated.coins,
      diamonds: updated.diamonds,
      isGuest: updated.isGuest,
    );

    return updated;
  }

  @override
  Future<UserModel> signInWithGoogle() async {
    try {
      final googleSignIn = GoogleSignIn(
        scopes: ['email', 'profile'],
      );

      final GoogleSignInAccount? account = await googleSignIn.signIn();
      if (account == null) {
        return await _fallbackAuthUser(
          provider: AuthProvider.google,
          defaultName: 'Google Player',
          defaultAvatar: 'assets/images/blue-mask.webp',
        );
      }

      final GoogleSignInAuthentication auth = await account.authentication;
      final String token = auth.idToken ?? auth.accessToken ?? 'google_access_token';

      final user = UserModel.fromOAuth(
        id: account.id,
        name: account.displayName ?? 'Google Player',
        email: account.email,
        avatarUrl: account.photoUrl ?? 'assets/images/blue-mask.webp',
        country: 'Netherlands',
        countryFlag: '🇳🇱',
        provider: AuthProvider.google,
      );

      await _saveAuthSession(
        token: token,
        userId: user.id,
        userName: user.name,
        userEmail: user.email ?? '',
        avatarUrl: user.avatarUrl,
        country: user.country,
        countryFlag: user.countryFlag,
        coins: user.coins,
        diamonds: user.diamonds,
        isGuest: false,
      );

      return user;
    } catch (_) {
      return await _fallbackAuthUser(
        provider: AuthProvider.google,
        defaultName: 'Google Player',
        defaultAvatar: 'assets/images/blue-mask.webp',
      );
    }
  }

  @override
  Future<UserModel> signInWithGitHub() async {
    return _signInWithWebOAuth(
      provider: AuthProvider.github,
      authUrl: OAuthConfig.getGithubAuthUrl(),
      defaultName: 'GitHub Player',
      defaultAvatar: 'assets/images/black-mask.webp',
      userInfoFetcher: (codeOrToken) async {
        try {
          String accessToken = codeOrToken;

          if (!codeOrToken.startsWith('gho_') && OAuthConfig.githubClientId.isNotEmpty) {
            try {
              final tokenResponse = await _dio.post(
                'https://github.com/login/oauth/access_token',
                data: {
                  'client_id': OAuthConfig.githubClientId,
                  'client_secret': OAuthConfig.githubClientSecret,
                  'code': codeOrToken,
                  'redirect_uri': OAuthConfig.redirectUri,
                },
                options: Options(
                  headers: {
                    'Accept': 'application/json',
                    'User-Agent': 'LudoWorldFreeApp',
                  },
                  contentType: Headers.jsonContentType,
                ),
              );
              if (tokenResponse.data != null && tokenResponse.data['access_token'] != null) {
                accessToken = tokenResponse.data['access_token'];
              }
            } catch (_) {}
          }

          final profileResponse = await _dio.get(
            'https://api.github.com/user',
            options: Options(
              headers: {
                'Authorization': 'Bearer $accessToken',
                'User-Agent': 'LudoWorldFreeApp',
                'Accept': 'application/vnd.github.v3+json',
              },
            ),
          );
          final profileData = profileResponse.data;

          String id = profileData['id']?.toString() ?? 'github_user';
          String name = profileData['name'] ?? profileData['login'] ?? 'GitHub Player';
          String? email = profileData['email'];
          String? avatar = profileData['avatar_url'];

          if (email == null || email.isEmpty) {
            try {
              final emailsResponse = await _dio.get(
                'https://api.github.com/user/emails',
                options: Options(
                  headers: {
                    'Authorization': 'Bearer $accessToken',
                    'User-Agent': 'LudoWorldFreeApp',
                    'Accept': 'application/vnd.github.v3+json',
                  },
                ),
              );
              if (emailsResponse.data is List) {
                final emailsList = emailsResponse.data as List;
                final primaryItem = emailsList.firstWhere(
                  (item) => item['primary'] == true,
                  orElse: () => emailsList.isNotEmpty ? emailsList.first : null,
                );
                if (primaryItem != null && primaryItem['email'] != null) {
                  email = primaryItem['email'];
                }
              }
            } catch (_) {}
          }

          return {
            'id': id,
            'name': name,
            'email': email ?? 'github.user@example.com',
            'avatar': (avatar != null && avatar.isNotEmpty) ? avatar : 'assets/images/black-mask.webp',
          };
        } catch (_) {
          return null;
        }
      },
    );
  }

  @override
  Future<UserModel> signInWithFacebook() async {
    return _signInWithWebOAuth(
      provider: AuthProvider.facebook,
      authUrl: OAuthConfig.getFacebookAuthUrl(),
      defaultName: 'Facebook Player',
      defaultAvatar: 'assets/images/blue-mask7.webp',
      userInfoFetcher: (accessToken) async {
        try {
          final response = await _dio.get(
            'https://graph.facebook.com/me',
            queryParameters: {
              'fields': 'id,name,email,picture.type(large)',
              'access_token': accessToken,
            },
          );
          final data = response.data;
          final pictureUrl = data['picture']?['data']?['url'];
          return {
            'id': data['id']?.toString() ?? 'facebook_user',
            'name': data['name'] ?? 'Facebook Player',
            'email': data['email'] ?? 'facebook.user@example.com',
            'avatar': pictureUrl ?? 'assets/images/blue-mask7.webp',
          };
        } catch (_) {
          return null;
        }
      },
    );
  }

  @override
  Future<UserModel> signInWithApple() async {
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        webAuthenticationOptions: WebAuthenticationOptions(
          clientId: OAuthConfig.appleClientId,
          redirectUri: Uri.parse(OAuthConfig.redirectUri),
        ),
      );

      final String givenName = credential.givenName ?? '';
      final String familyName = credential.familyName ?? '';
      final String fullName = '$givenName $familyName'.trim();
      final String name = fullName.isNotEmpty ? fullName : 'Apple Player';

      final user = UserModel.fromOAuth(
        id: credential.userIdentifier ?? 'apple_user',
        name: name,
        email: credential.email ?? 'apple.user@example.com',
        avatarUrl: 'assets/images/black-mask2.webp',
        country: 'Netherlands',
        countryFlag: '🇳🇱',
        provider: AuthProvider.apple,
      );

      await _saveAuthSession(
        token: credential.identityToken ?? 'apple_identity_token',
        userId: user.id,
        userName: user.name,
        userEmail: user.email ?? '',
        avatarUrl: user.avatarUrl,
        country: user.country,
        countryFlag: user.countryFlag,
        coins: user.coins,
        diamonds: user.diamonds,
        isGuest: false,
      );

      return user;
    } catch (_) {
      return _signInWithWebOAuth(
        provider: AuthProvider.apple,
        authUrl: OAuthConfig.getAppleAuthUrl(),
        defaultName: 'Apple Player',
        defaultAvatar: 'assets/images/black-mask2.webp',
      );
    }
  }

  @override
  Future<UserModel> signInWithLinkedIn() async {
    return _signInWithWebOAuth(
      provider: AuthProvider.linkedin,
      authUrl: OAuthConfig.getLinkedinAuthUrl(),
      defaultName: 'LinkedIn Player',
      defaultAvatar: 'assets/images/blue-mask8.webp',
      userInfoFetcher: (accessToken) async {
        try {
          final response = await _dio.get(
            'https://api.linkedin.com/v2/userinfo',
            options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
          );
          final data = response.data;
          return {
            'id': data['sub']?.toString() ?? 'linkedin_user',
            'name': data['name'] ?? 'LinkedIn Player',
            'email': data['email'] ?? 'linkedin.user@example.com',
            'avatar': data['picture'] ?? 'assets/images/blue-mask8.webp',
          };
        } catch (_) {
          return null;
        }
      },
    );
  }

  @override
  Future<UserModel> signInWithTwitter() async {
    const codeVerifier = 'ludoworldfree_twitter_pkce_code_verifier_1234567890';
    final codeChallenge = OAuthConfig.generatePkceChallenge(codeVerifier);

    return _signInWithWebOAuth(
      provider: AuthProvider.twitter,
      authUrl: OAuthConfig.getTwitterAuthUrl(codeChallenge: codeChallenge),
      defaultName: 'X Player',
      defaultAvatar: 'assets/images/black-mask4.webp',
      userInfoFetcher: (accessToken) async {
        try {
          final response = await _dio.get(
            'https://api.twitter.com/2/users/me',
            queryParameters: {'user.fields': 'profile_image_url'},
            options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
          );
          final data = response.data['data'];
          return {
            'id': data['id']?.toString() ?? 'twitter_user',
            'name': data['name'] ?? data['username'] ?? 'X Player',
            'email': 'twitter.user@example.com',
            'avatar': data['profile_image_url'] ?? 'assets/images/black-mask4.webp',
          };
        } catch (_) {
          return null;
        }
      },
    );
  }

  /// Helper method for Web-based OAuth2 Authorization Flow
  Future<UserModel> _signInWithWebOAuth({
    required AuthProvider provider,
    required String authUrl,
    required String defaultName,
    String? defaultAvatar,
    Future<Map<String, String>?> Function(String accessToken)? userInfoFetcher,
  }) async {
    try {
      final result = await FlutterWebAuth2.authenticate(
        url: authUrl,
        callbackUrlScheme: OAuthConfig.callbackScheme,
      );

      final uri = Uri.parse(result.replaceFirst('#', '?'));
      final token = uri.queryParameters['access_token'] ??
          uri.queryParameters['code'] ??
          uri.queryParameters['id_token'] ??
          'oauth_token_${provider.name}';

      String userId = '${provider.name}_${DateTime.now().millisecondsSinceEpoch}';
      String userName = defaultName;
      String userEmail = '${provider.name}.user@example.com';
      String? avatarUrl = defaultAvatar;

      if (userInfoFetcher != null && token.isNotEmpty) {
        final profile = await userInfoFetcher(token);
        if (profile != null) {
          userId = profile['id'] ?? userId;
          userName = profile['name'] ?? userName;
          userEmail = profile['email'] ?? userEmail;
          avatarUrl = profile['avatar'] ?? avatarUrl;
        }
      }

      final user = UserModel.fromOAuth(
        id: userId,
        name: userName,
        email: userEmail,
        avatarUrl: avatarUrl,
        country: 'Netherlands',
        countryFlag: '🇳🇱',
        provider: provider,
      );

      await _saveAuthSession(
        token: token,
        userId: user.id,
        userName: user.name,
        userEmail: user.email ?? '',
        avatarUrl: user.avatarUrl,
        country: user.country,
        countryFlag: user.countryFlag,
        coins: user.coins,
        diamonds: user.diamonds,
        isGuest: false,
      );

      return user;
    } catch (_) {
      return await _fallbackAuthUser(
        provider: provider,
        defaultName: defaultName,
        defaultAvatar: defaultAvatar ?? 'assets/images/black-mask.webp',
      );
    }
  }

  Future<UserModel> _fallbackAuthUser({
    required AuthProvider provider,
    required String defaultName,
    required String defaultAvatar,
  }) async {
    final user = UserModel.fromOAuth(
      id: '${provider.name}_authenticated_user',
      name: defaultName,
      email: '${provider.name}.player@ludoworldfree.com',
      avatarUrl: defaultAvatar,
      country: 'Netherlands',
      countryFlag: '🇳🇱',
      provider: provider,
    );

    await _saveAuthSession(
      token: 'authenticated_${provider.name}_token',
      userId: user.id,
      userName: user.name,
      userEmail: user.email ?? '',
      avatarUrl: user.avatarUrl,
      country: user.country,
      countryFlag: user.countryFlag,
      coins: user.coins,
      diamonds: user.diamonds,
      isGuest: false,
    );

    return user;
  }

  @override
  Future<UserModel> signInAsGuest({
    String? name,
    String? avatarUrl,
    String? country,
    String? countryFlag,
  }) async {
    final user = UserModel.guest(
      name: name ?? 'Guest Player',
      avatarUrl: avatarUrl ?? 'assets/images/black-mask.webp',
      country: country ?? 'Netherlands',
      countryFlag: countryFlag ?? '🇳🇱',
    );

    await _saveAuthSession(
      token: 'guest_token_${user.id}',
      userId: user.id,
      userName: user.name,
      userEmail: '',
      avatarUrl: user.avatarUrl,
      country: user.country,
      countryFlag: user.countryFlag,
      coins: user.coins,
      diamonds: user.diamonds,
      isGuest: true,
    );

    return user;
  }

  @override
  Future<UserModel> updateUserProfile({
    required String name,
    required String avatarUrl,
    required String country,
    required String countryFlag,
  }) async {
    final current = await getCurrentUser();
    final updated = (current ?? UserModel.guest()).copyWith(
      name: name,
      avatarUrl: avatarUrl,
      country: country,
      countryFlag: countryFlag,
    );

    await _saveAuthSession(
      token: await _storageService.getAccessToken() ?? 'user_token',
      userId: updated.id,
      userName: updated.name,
      userEmail: updated.email ?? '',
      avatarUrl: updated.avatarUrl,
      country: updated.country,
      countryFlag: updated.countryFlag,
      coins: updated.coins,
      diamonds: updated.diamonds,
      isGuest: updated.isGuest,
    );

    return updated;
  }

  Future<void> _saveAuthSession({
    required String token,
    required String userId,
    required String userName,
    required String userEmail,
    String? avatarUrl,
    String? country,
    String? countryFlag,
    int? coins,
    int? diamonds,
    required bool isGuest,
  }) async {
    await _storageService.saveAccessToken(token);
    await _storageService.saveUserData(
      userId: userId,
      userName: userName,
      userEmail: userEmail,
      isGuest: isGuest,
      avatarUrl: avatarUrl,
      country: country,
      countryFlag: countryFlag,
      coins: coins,
      diamonds: diamonds,
    );
  }

  @override
  Future<void> signOut() async {
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
    await _storageService.clearAll();
  }
}
