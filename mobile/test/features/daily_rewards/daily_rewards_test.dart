import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/daily_rewards/domain/models/daily_reward_models.dart';
import 'package:mobile/features/daily_rewards/presentation/widgets/daily_bonus_dialog.dart';

void main() {
  group('Daily Rewards Domain Models', () {
    test('DailyRewardStatusModel fallback produces 7 days and 4 milestones', () {
      final fallback = DailyRewardStatusModel.fallback();

      expect(fallback.rewards.length, 7);
      expect(fallback.milestones.length, 4);
      expect(fallback.canClaimToday, isTrue);
      expect(fallback.rewards[0].amount, 500);
      expect(fallback.rewards[1].amount, 1000);
      expect(fallback.rewards[0].status, RewardItemStatus.claimable);
      expect(fallback.rewards[1].status, RewardItemStatus.locked);
    });

    test('DailyRewardStatusModel.fromJson parses JSON correctly', () {
      final json = {
        'currentStreak': 2,
        'activeDay': 3,
        'canClaimToday': true,
        'lastClaimDate': '2025-05-18',
        'secondsUntilNextClaim': 3600,
        'bonusAdClaimedToday': false,
        'rewards': [
          {
            'day': 1,
            'rewardType': 'COINS',
            'amount': 500,
            'status': 'CLAIMED',
            'label': '500',
            'description': '500 Gold Coins'
          },
          {
            'day': 2,
            'rewardType': 'COINS',
            'amount': 1000,
            'status': 'CLAIMED',
            'label': '1000',
            'description': '1000 Gold Coins'
          },
          {
            'day': 3,
            'rewardType': 'DIAMONDS',
            'amount': 6,
            'status': 'CLAIMABLE',
            'label': '6',
            'description': '6 Diamonds'
          },
        ],
        'milestones': [
          {'day': 7, 'chestType': 'BRONZE', 'unlocked': false, 'label': '7'},
        ],
      };

      final status = DailyRewardStatusModel.fromJson(json);

      expect(status.currentStreak, 2);
      expect(status.activeDay, 3);
      expect(status.canClaimToday, isTrue);
      expect(status.rewards.length, 3);
      expect(status.rewards[0].status, RewardItemStatus.claimed);
      expect(status.rewards[2].status, RewardItemStatus.claimable);
    });

    test('DailyRewardClaimResult.fromJson parses claim result', () {
      final json = {
        'success': true,
        'message': 'Successfully claimed Day 1 daily bonus!',
        'claimedDay': 1,
        'rewardType': 'COINS',
        'amount': 500,
        'currentCoins': 2500,
        'currentDiamonds': 100,
      };

      final result = DailyRewardClaimResult.fromJson(json);

      expect(result.success, isTrue);
      expect(result.claimedDay, 1);
      expect(result.amount, 500);
      expect(result.currentCoins, 2500);
    });
  });

  group('DailyBonusDialog Widget Tests', () {
    testWidgets('Renders Daily Bonus Title and close button', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: DailyBonusDialog(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('DAILY BONUS'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      expect(find.text('Come back every day for new reward'), findsOneWidget);
      expect(find.text('Day 1'), findsOneWidget);
      expect(find.text('Day 7 Milestone'), findsOneWidget);
      expect(find.text('500 COINS'), findsNWidgets(2));
      expect(find.text('1000 COINS'), findsOneWidget);
    });
  });
}
