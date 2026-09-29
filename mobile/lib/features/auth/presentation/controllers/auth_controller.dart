import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/auth_repository_impl.dart';
import '../../domain/auth_repository.dart';
import '../../domain/user_model.dart';

class AuthState {
  final bool isLoading;
  final UserModel? user;
  final String? errorMessage;
  final AuthProvider? loadingProvider;

  const AuthState({
    this.isLoading = false,
    this.user,
    this.errorMessage,
    this.loadingProvider,
  });

  bool get isAuthenticated => user != null;

  AuthState copyWith({
    bool? isLoading,
    UserModel? user,
    String? errorMessage,
    AuthProvider? loadingProvider,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      user: user ?? this.user,
      errorMessage: errorMessage,
      loadingProvider: loadingProvider,
    );
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return AuthController(repository);
});

class AuthController extends StateNotifier<AuthState> {
  final AuthRepository _repository;

  AuthController(this._repository) : super(const AuthState()) {
    checkCurrentUser();
  }

  Future<void> checkCurrentUser() async {
    state = state.copyWith(isLoading: true);
    final user = await _repository.getCurrentUser();
    state = AuthState(user: user, isLoading: false);
  }

  Future<bool> signInWithOAuth(AuthProvider provider) async {
    state = state.copyWith(isLoading: true, loadingProvider: provider);
    try {
      UserModel user;
      switch (provider) {
        case AuthProvider.google:
          user = await _repository.signInWithGoogle();
          break;
        case AuthProvider.facebook:
          user = await _repository.signInWithFacebook();
          break;
        case AuthProvider.apple:
          user = await _repository.signInWithApple();
          break;
        case AuthProvider.linkedin:
          user = await _repository.signInWithLinkedIn();
          break;
        case AuthProvider.twitter:
          user = await _repository.signInWithTwitter();
          break;
        case AuthProvider.github:
          user = await _repository.signInWithGitHub();
          break;
        default:
          user = await _repository.signInAsGuest();
      }
      state = AuthState(user: user, isLoading: false);
      return true;
    } catch (e) {
      state = AuthState(
        isLoading: false,
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
      );
      return false;
    }
  }

  Future<bool> signInAsGuest({
    String? name,
    String? avatarUrl,
    String? country,
    String? countryFlag,
  }) async {
    state = state.copyWith(isLoading: true, loadingProvider: AuthProvider.guest);
    try {
      final user = await _repository.signInAsGuest(
        name: name,
        avatarUrl: avatarUrl,
        country: country,
        countryFlag: countryFlag,
      );
      state = AuthState(user: user, isLoading: false);
      return true;
    } catch (e) {
      state = AuthState(
        isLoading: false,
        errorMessage: 'Guest sign-in failed.',
      );
      return false;
    }
  }

  Future<bool> updateUserProfile({
    required String name,
    required String avatarUrl,
    required String country,
    required String countryFlag,
  }) async {
    state = state.copyWith(isLoading: true);
    try {
      final updated = await _repository.updateUserProfile(
        name: name,
        avatarUrl: avatarUrl,
        country: country,
        countryFlag: countryFlag,
      );
      state = AuthState(user: updated, isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: 'Failed to update profile.');
      return false;
    }
  }

  Future<void> signOut() async {
    state = state.copyWith(isLoading: true);
    await _repository.signOut();
    state = const AuthState();
  }
}
