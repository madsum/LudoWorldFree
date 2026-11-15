import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/game/domain/dice_randomizer.dart';

void main() {
  test('1,000 secure dice rolls are balanced and show no simple pattern', () {
    final dice = DiceRandomizer();
    final rolls = List<int>.generate(1000, (_) => dice.roll());
    final frequencies = List<int>.filled(6, 0);

    for (final roll in rolls) {
      expect(roll, inInclusiveRange(1, 6));
      frequencies[roll - 1]++;
    }
    print('1,000-roll face distribution: $frequencies');

    // Each face has an expected count of about 167. These bounds are wide
    // enough for normal random variation while catching meaningful bias.
    expect(frequencies.every((count) => count >= 100 && count <= 235), isTrue,
        reason: 'Observed face counts: $frequencies');

    // Independent rolls should change about five sixths of the time. This
    // rejects fixed, alternating, and strongly repetitive sequences.
    final transitions = Iterable<int>.generate(rolls.length - 1)
        .where((index) => rolls[index] != rolls[index + 1])
        .length;
    expect(transitions, inInclusiveRange(780, 890),
        reason: 'Observed $transitions changes in 999 adjacent rolls');
  });
}
