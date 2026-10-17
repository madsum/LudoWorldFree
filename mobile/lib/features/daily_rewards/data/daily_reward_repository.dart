import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/models/daily_reward_models.dart';

final dailyRewardRepositoryProvider = Provider<DailyRewardRepository>((ref) {
  final dio = ref.watch(apiClientProvider);
  return DailyRewardRepository(dio);
});

class DailyRewardRepository {
  final Dio _dio;

  DailyRewardRepository(this._dio);

  Future<DailyRewardStatusModel> getRewardStatus(String playerId) async {
    try {
      final response = await _dio.get(
        '/daily-rewards',
        options: Options(headers: {'X-Player-ID': playerId}),
      );
      if (response.data != null) {
        return DailyRewardStatusModel.fromJson(response.data as Map<String, dynamic>);
      }
    } catch (_) {}
    return DailyRewardStatusModel.fallback();
  }

  Future<DailyRewardClaimResult> claimDailyReward(String playerId) async {
    try {
      final response = await _dio.post(
        '/daily-rewards/claim',
        options: Options(headers: {'X-Player-ID': playerId}),
      );
      if (response.data != null) {
        return DailyRewardClaimResult.fromJson(response.data as Map<String, dynamic>);
      }
    } catch (e) {
      return DailyRewardClaimResult(
        success: false,
        message: 'Network error while claiming daily reward. Check your internet connection.',
        claimedDay: 0,
        rewardType: 'NONE',
        amount: 0,
        currentCoins: 0,
        currentDiamonds: 0,
      );
    }
    return DailyRewardClaimResult(
      success: false,
      message: 'Failed to claim daily reward.',
      claimedDay: 0,
      rewardType: 'NONE',
      amount: 0,
      currentCoins: 0,
      currentDiamonds: 0,
    );
  }

  Future<DailyRewardClaimResult> claimBonusAdReward(String playerId, String providerRewardId) async {
    try {
      final response = await _dio.post(
        '/daily-rewards/bonus-ad/claim',
        data: {'providerRewardId': providerRewardId},
        options: Options(headers: {'X-Player-ID': playerId}),
      );
      if (response.data != null) {
        return DailyRewardClaimResult.fromJson(response.data as Map<String, dynamic>);
      }
    } catch (e) {
      return DailyRewardClaimResult(
        success: false,
        message: 'Failed to claim extra bonus ad reward.',
        claimedDay: 0,
        rewardType: 'BONUS_AD',
        amount: 0,
        currentCoins: 0,
        currentDiamonds: 0,
      );
    }
    return DailyRewardClaimResult(
      success: false,
      message: 'Failed to claim bonus ad reward.',
      claimedDay: 0,
      rewardType: 'BONUS_AD',
      amount: 0,
      currentCoins: 0,
      currentDiamonds: 0,
    );
  }
}
