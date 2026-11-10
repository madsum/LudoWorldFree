import 'dart:async';

import 'package:flutter/foundation.dart';
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
    final user = await _repository.getStoredCurrentUser();
    state = AuthState(user: user, isLoading: false);
    if (user != null) {
      unawaited(_refreshRestoredUser(user.id));
    }
  }

  Future<void> _refreshRestoredUser(String userId) async {
    try {
      final refreshed = await _repository.getCurrentUser();
      if (refreshed != null && state.user?.id == userId) {
        applyUserUpdate(refreshed);
      }
    } catch (error) {
      debugPrint('Restored profile refresh failed: $error');
    }
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
    state =
        state.copyWith(isLoading: true, loadingProvider: AuthProvider.guest);
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
      state = state.copyWith(
          isLoading: false, errorMessage: 'Failed to update profile.');
      return false;
    }
  }

  Future<bool> uploadProfileAvatar({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final current = state.user;
    if (current == null) return false;
    state = state.copyWith(isLoading: true);
    try {
      final avatarUrl = await _repository.uploadProfileAvatar(
        playerId: current.id,
        bytes: bytes,
        fileName: fileName,
      );
      final updated = await _repository.updateUserProfile(
        name: current.name,
        avatarUrl: avatarUrl,
        country: current.country,
        countryFlag: current.countryFlag,
      );
      state = AuthState(user: updated, isLoading: false);
      return true;
    } catch (_) {
      try {
        final fallback = await _repository.updateUserProfile(
          name: current.name,
          avatarUrl: current.avatarUrl ?? 'assets/images/black-mask.webp',
          country: current.country,
          countryFlag: current.countryFlag,
        );
        state = AuthState(
          user: fallback,
          isLoading: false,
          errorMessage:
              'Image upload failed. Your default avatar is unchanged.',
        );
      } catch (_) {
        state = state.copyWith(
          isLoading: false,
          errorMessage:
              'Image upload failed. Your default avatar is unchanged.',
        );
      }
      return false;
    }
  }

  /// Claims ad reward and updates persistent player wallet balance
  Future<UserModel?> claimGoldReward({
    required int amount,
    required String providerRewardId,
  }) async {
    try {
      return await _repository.addGoldReward(
        amount: amount,
        providerRewardId: providerRewardId,
      );
    } catch (_) {
      return null;
    }
  }

  void applyUserUpdate(UserModel user) {
    state = AuthState(user: user, isLoading: false);
  }

  Future<void> persistWalletBalance(UserModel user) async {
    await _repository.persistWalletBalance(user);
    applyUserUpdate(user);
  }

  Future<bool> addGoldReward({
    required int amount,
    required String providerRewardId,
  }) async {
    final current = state.user;
    if (current != null) {
      // Reflect the reward as soon as the animation finishes; storage and the
      // backend are allowed to complete afterward.
      applyUserUpdate(current.copyWith(coins: current.coins + amount));
    }

    try {
      final updated = await claimGoldReward(
        amount: amount,
        providerRewardId: providerRewardId,
      );
      if (updated == null) {
        if (current != null) applyUserUpdate(current);
        return false;
      }
      applyUserUpdate(updated);
      return true;
    } catch (error) {
      debugPrint('Ad reward claim failed: $error');
      if (current != null) applyUserUpdate(current);
      return false;
    }
  }

  Future<DailyBonusStatus?> getDailyBonusStatus() async {
    try {
      return await _repository.getDailyBonusStatus();
    } catch (error) {
      debugPrint('Daily bonus status request failed: $error');
      return null;
    }
  }

  Future<DailyBonusStatus?> claimDailyBonus() async {
    try {
      final result = await _repository.claimDailyBonus();
      if (!result.success) {
        // A duplicate claim is not a new reward. Still reload the wallet so
        // the visible balance matches the backend's current balance.
        await refreshWalletFromBackend();
        return null;
      }

      // Match the ad reward flow: the server response is authoritative, and
      // the provider is updated immediately so the header and profile rebuild.
      final current = state.user;
      if (current != null) {
        applyUserUpdate(current.copyWith(coins: result.balance));
      }
      await refreshWalletFromBackend();
      return result;
    } catch (error) {
      debugPrint('Daily bonus claim failed: $error');
      return null;
    }
  }

  Future<void> refreshWalletFromBackend() async {
    try {
      final refreshed = await _repository.getCurrentUser();
      if (refreshed != null) applyUserUpdate(refreshed);
    } catch (error) {
      debugPrint('Wallet refresh after daily bonus failed: $error');
    }
  }

  Future<void> signOut() async {
    state = state.copyWith(isLoading: true);
    await _repository.signOut();
    state = const AuthState();
  }
}
