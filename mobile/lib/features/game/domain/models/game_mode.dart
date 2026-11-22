enum GameMode {
  classic,
  firstKill;

  String get wireValue => switch (this) {
        GameMode.classic => 'CLASSIC',
        GameMode.firstKill => 'FIRST_KILL',
      };

  static GameMode fromWireValue(Object? value) =>
      value?.toString().toUpperCase() == 'FIRST_KILL'
          ? GameMode.firstKill
          : GameMode.classic;
}
