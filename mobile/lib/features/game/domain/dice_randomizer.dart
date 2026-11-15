import 'dart:math' as math;

/// Produces fair six-sided dice rolls from the platform's secure random source.
class DiceRandomizer {
  final math.Random _random = math.Random.secure();

  int roll() => _random.nextInt(6) + 1;
}
