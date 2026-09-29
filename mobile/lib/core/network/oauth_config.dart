import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class OAuthConfig {
  OAuthConfig._();

  static const String callbackScheme = 'ludoworldfree';
  static const String callbackHost = 'oauth-callback';
  static const String redirectUri = '$callbackScheme://$callbackHost';

  // --------------------------------------------------------------------------
  // OAuth Credentials (Loaded dynamically from .env file)
  // --------------------------------------------------------------------------

  // Google
  static String get googleClientId =>
      dotenv.env['GOOGLE_CLIENT_ID'] ?? '';
  static String get googleClientSecret =>
      dotenv.env['GOOGLE_CLIENT_SECRET'] ?? '';

  // GitHub
  static String get githubClientId =>
      dotenv.env['GITHUB_CLIENT_ID'] ?? '';
  static String get githubClientSecret =>
      dotenv.env['GITHUB_CLIENT_SECRET'] ?? '';

  // Facebook
  static String get facebookAppId =>
      dotenv.env['FACEBOOK_APP_ID'] ?? '';
  static String get facebookClientSecret =>
      dotenv.env['FACEBOOK_CLIENT_SECRET'] ?? '';

  // LinkedIn
  static String get linkedinClientId =>
      dotenv.env['LINKEDIN_CLIENT_ID'] ?? '';
  static String get linkedinClientSecret =>
      dotenv.env['LINKEDIN_CLIENT_SECRET'] ?? '';

  // Apple
  static String get appleClientId =>
      dotenv.env['APPLE_CLIENT_ID'] ?? 'nl.iprosoft.ludo.sid';
  static String get appleTeamId =>
      dotenv.env['APPLE_TEAM_ID'] ?? '';
  static String get appleKeyId =>
      dotenv.env['APPLE_KEY_ID'] ?? '';
  static String get appleClientSecret =>
      dotenv.env['APPLE_CLIENT_SECRET'] ?? '';

  // X / Twitter
  static String get twitterClientId =>
      dotenv.env['TWITTER_CLIENT_ID'] ?? '';
  static String get twitterClientSecret =>
      dotenv.env['TWITTER_CLIENT_SECRET'] ?? '';

  // --------------------------------------------------------------------------
  // Authorization URL Builders
  // --------------------------------------------------------------------------

  static String getGithubAuthUrl() {
    return 'https://github.com/login/oauth/authorize'
        '?client_id=$githubClientId'
        '&redirect_uri=${Uri.encodeComponent(redirectUri)}'
        '&scope=read:user%20user:email';
  }

  static String getFacebookAuthUrl() {
    return 'https://www.facebook.com/v18.0/dialog/oauth'
        '?client_id=$facebookAppId'
        '&redirect_uri=${Uri.encodeComponent(redirectUri)}'
        '&scope=email,public_profile'
        '&response_type=token';
  }

  static String getGoogleWebAuthUrl() {
    return 'https://accounts.google.com/o/oauth2/v2/auth'
        '?client_id=$googleClientId'
        '&redirect_uri=${Uri.encodeComponent(redirectUri)}'
        '&response_type=token'
        '&scope=email%20profile';
  }

  static String getLinkedinAuthUrl() {
    return 'https://www.linkedin.com/oauth/v2/authorization'
        '?response_type=code'
        '&client_id=$linkedinClientId'
        '&redirect_uri=${Uri.encodeComponent(redirectUri)}'
        '&scope=openid%20profile%20email';
  }

  static String getAppleAuthUrl() {
    return 'https://appleid.apple.com/auth/authorize'
        '?client_id=$appleClientId'
        '&redirect_uri=${Uri.encodeComponent(redirectUri)}'
        '&scope=name%20email'
        '&response_mode=fragment';
  }

  static String getTwitterAuthUrl({required String codeChallenge}) {
    return 'https://twitter.com/i/oauth2/authorize'
        '?response_type=code'
        '&client_id=$twitterClientId'
        '&redirect_uri=${Uri.encodeComponent(redirectUri)}'
        '&scope=tweet.read%20users.read%20offline.access'
        '&state=ludoworldstate'
        '&code_challenge=$codeChallenge'
        '&code_challenge_method=S256';
  }

  /// Generates a PKCE Code Challenge (SHA-256) for Twitter OAuth 2.0
  static String generatePkceChallenge(String codeVerifier) {
    final bytes = utf8.encode(codeVerifier);
    final digest = sha256.convert(bytes);
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }
}
