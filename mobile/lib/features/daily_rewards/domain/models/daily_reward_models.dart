enum RewardItemStatus {
  claimed,
  claimable,
  locked;

  static RewardItemStatus parse(String? value) {
    if (value == null) return RewardItemStatus.locked;
    switch (value.toUpperCase()) {
      case 'CLAIMED':
        return RewardItemStatus.claimed;
      case 'CLAIMABLE':
        return RewardItemStatus.claimable;
      default:
        return RewardItemStatus.locked;
    }
  }
}

class DailyRewardItemModel {
  final int day;
  final String rewardType; // COINS, SPIN_TOKENS, DIAMONDS, CHEST
  final int amount;
  final RewardItemStatus status;
  final String label;
  final String description;

  const DailyRewardItemModel({
    required this.day,
    required this.rewardType,
    required this.amount,
    required this.status,
    required this.label,
    required this.description,
  });

  factory DailyRewardItemModel.fromJson(Map<String, dynamic> json) {
    return DailyRewardItemModel(
      day: json['day'] as int? ?? 1,
      rewardType: json['rewardType'] as String? ?? 'COINS',
      amount: (json['amount'] as num? ?? 0).toInt(),
      status: RewardItemStatus.parse(json['status'] as String?),
      label: json['label'] as String? ?? '',
      description: json['description'] as String? ?? '',
    );
  }
}

class DailyMilestoneModel {
  final int day;
  final String chestType; // BRONZE, SILVER, GOLD, ROYAL
  final bool unlocked;
  final String label;

  const DailyMilestoneModel({
    required this.day,
    required this.chestType,
    required this.unlocked,
    required this.label,
  });

  factory DailyMilestoneModel.fromJson(Map<String, dynamic> json) {
    return DailyMilestoneModel(
      day: json['day'] as int? ?? 7,
      chestType: json['chestType'] as String? ?? 'BRONZE',
      unlocked: json['unlocked'] as bool? ?? false,
      label: json['label'] as String? ?? '',
    );
  }
}

class DailyRewardStatusModel {
  final int currentStreak;
  final int activeDay;
  final bool canClaimToday;
  final String? lastClaimDate;
  final String? nextEligibleClaimTime;
  final int secondsUntilNextClaim;
  final bool bonusAdClaimedToday;
  final List<DailyRewardItemModel> rewards;
  final List<DailyMilestoneModel> milestones;

  const DailyRewardStatusModel({
    required this.currentStreak,
    required this.activeDay,
    required this.canClaimToday,
    this.lastClaimDate,
    this.nextEligibleClaimTime,
    required this.secondsUntilNextClaim,
    required this.bonusAdClaimedToday,
    required this.rewards,
    required this.milestones,
  });

  factory DailyRewardStatusModel.fromJson(Map<String, dynamic> json) {
    final rewardList = (json['rewards'] as List<dynamic>?)
            ?.map((e) => DailyRewardItemModel.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    final milestoneList = (json['milestones'] as List<dynamic>?)
            ?.map((e) => DailyMilestoneModel.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    return DailyRewardStatusModel(
      currentStreak: json['currentStreak'] as int? ?? 0,
      activeDay: json['activeDay'] as int? ?? 1,
      canClaimToday: json['canClaimToday'] as bool? ?? true,
      lastClaimDate: json['lastClaimDate'] as String?,
      nextEligibleClaimTime: json['nextEligibleClaimTime'] as String?,
      secondsUntilNextClaim: (json['secondsUntilNextClaim'] as num? ?? 0).toInt(),
      bonusAdClaimedToday: json['bonusAdClaimedToday'] as bool? ?? false,
      rewards: rewardList,
      milestones: milestoneList,
    );
  }

  factory DailyRewardStatusModel.fallback() {
    return DailyRewardStatusModel(
      currentStreak: 0,
      activeDay: 1,
      canClaimToday: true,
      secondsUntilNextClaim: 0,
      bonusAdClaimedToday: false,
      rewards: [
        const DailyRewardItemModel(
            day: 1, rewardType: 'COINS', amount: 1000, status: RewardItemStatus.claimable, label: '1000', description: '1000 Gold Coins'),
        const DailyRewardItemModel(
            day: 2, rewardType: 'SPIN_TOKENS', amount: 2, status: RewardItemStatus.locked, label: '2', description: '2 Spin Tokens'),
        const DailyRewardItemModel(
            day: 3, rewardType: 'DIAMONDS', amount: 6, status: RewardItemStatus.locked, label: '6', description: '6 Diamonds'),
        const DailyRewardItemModel(
            day: 4, rewardType: 'COINS', amount: 500, status: RewardItemStatus.locked, label: '500', description: '500 Gold Coins'),
        const DailyRewardItemModel(
            day: 5, rewardType: 'DIAMONDS', amount: 8, status: RewardItemStatus.locked, label: '8', description: '8 Diamonds'),
        const DailyRewardItemModel(
            day: 6, rewardType: 'COINS', amount: 600, status: RewardItemStatus.locked, label: '600', description: '600 Gold Coins'),
        const DailyRewardItemModel(
            day: 7, rewardType: 'CHEST', amount: 1000, status: RewardItemStatus.locked, label: 'BRONZE', description: 'Bronze Chest'),
      ],
      milestones: [
        const DailyMilestoneModel(day: 7, chestType: 'BRONZE', unlocked: false, label: '7'),
        const DailyMilestoneModel(day: 14, chestType: 'SILVER', unlocked: false, label: '14'),
        const DailyMilestoneModel(day: 21, chestType: 'GOLD', unlocked: false, label: '21'),
        const DailyMilestoneModel(day: 28, chestType: 'ROYAL', unlocked: false, label: '28'),
      ],
    );
  }
}

class DailyRewardClaimResult {
  final bool success;
  final String message;
  final int claimedDay;
  final String rewardType;
  final int amount;
  final int currentCoins;
  final int currentDiamonds;
  final DailyRewardStatusModel? updatedStatus;

  const DailyRewardClaimResult({
    required this.success,
    required this.message,
    required this.claimedDay,
    required this.rewardType,
    required this.amount,
    required this.currentCoins,
    required this.currentDiamonds,
    this.updatedStatus,
  });

  factory DailyRewardClaimResult.fromJson(Map<String, dynamic> json) {
    return DailyRewardClaimResult(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String? ?? '',
      claimedDay: json['claimedDay'] as int? ?? 0,
      rewardType: json['rewardType'] as String? ?? 'NONE',
      amount: (json['amount'] as num? ?? 0).toInt(),
      currentCoins: (json['currentCoins'] as num? ?? 0).toInt(),
      currentDiamonds: (json['currentDiamonds'] as num? ?? 0).toInt(),
      updatedStatus: json['updatedStatus'] != null
          ? DailyRewardStatusModel.fromJson(json['updatedStatus'] as Map<String, dynamic>)
          : null,
    );
  }
}
