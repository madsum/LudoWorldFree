import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../data/daily_reward_repository.dart';
import '../../domain/models/daily_reward_models.dart';

class DailyRewardState {
  final bool isLoading;
  final bool isClaiming;
  final DailyRewardStatusModel status;
  final DailyRewardClaimResult? lastClaimResult;
  final String? errorMessage;

  DailyRewardState({
    this.isLoading = false,
    this.isClaiming = false,
    DailyRewardStatusModel? status,
    this.lastClaimResult,
    this.errorMessage,
  }) : status = status ?? DailyRewardStatusModel.fallback();

  DailyRewardState copyWith({
    bool? isLoading,
    bool? isClaiming,
    DailyRewardStatusModel? status,
    DailyRewardClaimResult? lastClaimResult,
    String? errorMessage,
  }) {
    return DailyRewardState(
      isLoading: isLoading ?? this.isLoading,
      isClaiming: isClaiming ?? this.isClaiming,
      status: status ?? this.status,
      lastClaimResult: lastClaimResult ?? this.lastClaimResult,
      errorMessage: errorMessage,
    );
  }
}

final dailyRewardControllerProvider =
    StateNotifierProvider<DailyRewardController, DailyRewardState>((ref) {
  final repository = ref.watch(dailyRewardRepositoryProvider);
  return DailyRewardController(ref, repository);
});

class DailyRewardController extends StateNotifier<DailyRewardState> {
  final Ref _ref;
  final DailyRewardRepository _repository;

  DailyRewardController(this._ref, this._repository) : super(DailyRewardState());

  Future<void> fetchStatus() async {
    final user = _ref.read(authControllerProvider).user;
    if (user == null) return;

    state = state.copyWith(isLoading: true, errorMessage: null);
    final status = await _repository.getRewardStatus(user.id);
    state = state.copyWith(isLoading: false, status: status);
  }

  Future<DailyRewardClaimResult?> claimDailyReward() async {
    final user = _ref.read(authControllerProvider).user;
    if (user == null || state.isClaiming) return null;

    state = state.copyWith(isClaiming: true, errorMessage: null);
    final result = await _repository.claimDailyReward(user.id);

    if (result.success) {
      final updatedStatus = result.updatedStatus ?? state.status;
      state = state.copyWith(
        isClaiming: false,
        status: updatedStatus,
        lastClaimResult: result,
      );

      // Update Riverpod Auth User Wallet state immediately!
      final authNotifier = _ref.read(authControllerProvider.notifier);
      final currentUser = _ref.read(authControllerProvider).user;
      if (currentUser != null) {
        authNotifier.applyUserUpdate(currentUser.copyWith(
          coins: result.currentCoins,
          diamonds: result.currentDiamonds > 0 ? result.currentDiamonds : currentUser.diamonds,
        ));
      }
    } else {
      state = state.copyWith(isClaiming: false, errorMessage: result.message);
    }

    return result;
  }

  Future<DailyRewardClaimResult?> claimBonusAdReward(String providerRewardId) async {
    final user = _ref.read(authControllerProvider).user;
    if (user == null || state.isClaiming) return null;

    state = state.copyWith(isClaiming: true, errorMessage: null);
    final result = await _repository.claimBonusAdReward(user.id, providerRewardId);

    if (result.success) {
      final updatedStatus = result.updatedStatus ?? state.status;
      state = state.copyWith(
        isClaiming: false,
        status: updatedStatus,
        lastClaimResult: result,
      );

      final authNotifier = _ref.read(authControllerProvider.notifier);
      final currentUser = _ref.read(authControllerProvider).user;
      if (currentUser != null) {
        authNotifier.applyUserUpdate(currentUser.copyWith(
          coins: result.currentCoins,
        ));
      }
    } else {
      state = state.copyWith(isClaiming: false, errorMessage: result.message);
    }

    return result;
  }
}
