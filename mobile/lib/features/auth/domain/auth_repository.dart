import 'user_model.dart';

abstract class AuthRepository {
  Future<UserModel?> getCurrentUser();

  Future<UserModel> signInWithGoogle();
  Future<UserModel> signInWithFacebook();
  Future<UserModel> signInWithApple();
  Future<UserModel> signInWithLinkedIn();
  Future<UserModel> signInWithTwitter();
  Future<UserModel> signInWithGitHub();

  Future<UserModel> signInAsGuest({
    String? name,
    String? avatarUrl,
    String? country,
    String? countryFlag,
  });

  Future<UserModel> updateUserProfile({
    required String name,
    required String avatarUrl,
    required String country,
    required String countryFlag,
  });

  Future<void> signOut();
}
