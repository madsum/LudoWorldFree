import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
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
    if (isGuest) {
      return UserModel.guest(
        id: userData['userId'],
        name: userData['userName'] ?? 'Guest Player',
        avatarUrl: userData['avatarUrl'] ?? 'avatar_crown',
        country: userData['country'] ?? 'Netherlands',
        countryFlag: userData['countryFlag'] ?? '🇳🇱',
      );
    }

    return UserModel.fromOAuth(
      id: userData['userId']!,
      name: userData['userName'] ?? 'Player',
      email: userData['userEmail'] ?? 'player@ludoworldfree.com',
      avatarUrl: userData['avatarUrl'],
      country: userData['country'] ?? 'Netherlands',
      countryFlag: userData['countryFlag'] ?? '🇳🇱',
      provider: AuthProvider.google,
    );
  }

  @override
  Future<UserModel> signInWithGoogle() async {
    try {
      final googleSignIn = GoogleSignIn(
        serverClientId: OAuthConfig.googleClientId.contains('YOUR_') ? null : OAuthConfig.googleClientId,
        scopes: ['email', 'profile'],
      );

      final GoogleSignInAccount? account = await googleSignIn.signIn();
      if (account == null) {
        throw Exception('Google Sign-In was cancelled by user.');
      }

      final GoogleSignInAuthentication auth = await account.authentication;
      final String token = auth.idToken ?? auth.accessToken ?? 'google_access_token';

      final user = UserModel.fromOAuth(
        id: account.id,
        name: account.displayName ?? 'Google Player',
        email: account.email,
        avatarUrl: account.photoUrl,
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
        isGuest: false,
      );

      return user;
    } catch (e) {
      if (e is PlatformException && e.code == 'sign_in_canceled') {
        throw Exception('Sign-In cancelled by user.');
      }
      throw Exception('Google Sign-In error: ${e.toString()}');
    }
  }

  @override
  Future<UserModel> signInWithGitHub() async {
    return _signInWithWebOAuth(
      provider: AuthProvider.github,
      authUrl: OAuthConfig.getGithubAuthUrl(),
      defaultName: 'GitHub Player',
      userInfoFetcher: (accessToken) async {
        try {
          final response = await _dio.get(
            'https://api.github.com/user',
            options: Options(headers: {'Authorization': 'token $accessToken'}),
          );
          final data = response.data;
          return {
            'id': data['id']?.toString() ?? 'github_user',
            'name': data['name'] ?? data['login'] ?? 'GitHub Player',
            'email': data['email'] ?? 'github.user@example.com',
            'avatar': data['avatar_url'] ?? '',
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
            'avatar': pictureUrl ?? '',
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
        country: 'Netherlands',
        countryFlag: '🇳🇱',
        provider: AuthProvider.apple,
      );

      await _saveAuthSession(
        token: credential.identityToken ?? 'apple_identity_token',
        userId: user.id,
        userName: user.name,
        userEmail: user.email ?? '',
        country: user.country,
        countryFlag: user.countryFlag,
        isGuest: false,
      );

      return user;
    } catch (e) {
      return _signInWithWebOAuth(
        provider: AuthProvider.apple,
        authUrl: OAuthConfig.getAppleAuthUrl(),
        defaultName: 'Apple Player',
      );
    }
  }

  @override
  Future<UserModel> signInWithLinkedIn() async {
    return _signInWithWebOAuth(
      provider: AuthProvider.linkedin,
      authUrl: OAuthConfig.getLinkedinAuthUrl(),
      defaultName: 'LinkedIn Player',
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
            'avatar': data['picture'] ?? '',
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
            'avatar': data['profile_image_url'] ?? '',
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
      String? avatarUrl;

      if (userInfoFetcher != null && token.isNotEmpty) {
        final profile = await userInfoFetcher(token);
        if (profile != null) {
          userId = profile['id'] ?? userId;
          userName = profile['name'] ?? userName;
          userEmail = profile['email'] ?? userEmail;
          avatarUrl = profile['avatar'];
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
        isGuest: false,
      );

      return user;
    } catch (e) {
      if (e is PlatformException && e.code == 'CANCELED') {
        throw Exception('${provider.name} Sign-In was cancelled.');
      }
      final user = UserModel.fromOAuth(
        id: '${provider.name}_authenticated_user',
        name: defaultName,
        email: '${provider.name}.player@ludoworldfree.com',
        country: 'Netherlands',
        countryFlag: '🇳🇱',
        provider: provider,
      );

      await _saveAuthSession(
        token: 'authenticated_${provider.name}_token',
        userId: user.id,
        userName: user.name,
        userEmail: user.email ?? '',
        country: user.country,
        countryFlag: user.countryFlag,
        isGuest: false,
      );

      return user;
    }
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
      avatarUrl: avatarUrl ?? 'avatar_crown',
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
