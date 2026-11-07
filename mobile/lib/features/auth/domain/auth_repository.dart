import 'user_model.dart';

class DailyBonusStatus {
  final bool claimedToday;
  final bool success;
  final int streak;
  final int rewardDay;
  final int rewardAmount;
  final int balance;

  const DailyBonusStatus({
    required this.claimedToday,
    this.success = false,
    required this.streak,
    required this.rewardDay,
    required this.rewardAmount,
    required this.balance,
  });

  factory DailyBonusStatus.fromJson(Map<String, dynamic> json) {
    return DailyBonusStatus(
      claimedToday: json['claimedToday'] == true,
      success: json['success'] == true,
      streak: (json['streak'] as num?)?.toInt() ?? 0,
      rewardDay: (json['rewardDay'] as num?)?.toInt() ?? 1,
      rewardAmount: (json['rewardAmount'] as num?)?.toInt() ?? 0,
      balance: (json['balance'] as num?)?.toInt() ?? 0,
    );
  }

  DailyBonusStatus copyWith({int? balance}) {
    return DailyBonusStatus(
      claimedToday: claimedToday,
      success: success,
      streak: streak,
      rewardDay: rewardDay,
      rewardAmount: rewardAmount,
      balance: balance ?? this.balance,
    );
  }
}

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

  Future<UserModel> addGoldReward({
    required int amount,
    required String providerRewardId,
  });

  Future<DailyBonusStatus> getDailyBonusStatus();
  Future<DailyBonusStatus> claimDailyBonus();

  Future<void> persistWalletBalance(UserModel user);

  Future<void> signOut();
}
