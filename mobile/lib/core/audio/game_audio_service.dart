import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final gameAudioServiceProvider =
    ChangeNotifierProvider<GameAudioService>((ref) {
  return GameAudioService();
});

class GameAudioService extends ChangeNotifier {
  final AudioPlayer _musicPlayer = AudioPlayer();
  final AudioPlayer _effectPlayer = AudioPlayer();

  bool _musicEnabled = true;
  bool _effectsEnabled = true;
  String? _currentMusic;
  bool _disposed = false;
  int _musicRequestId = 0;

  bool get musicEnabled => _musicEnabled;
  bool get effectsEnabled => _effectsEnabled;

  Future<void> playWaitingMusic() =>
      _playMusic('audio/online-search-waiting.m4a');

  Future<void> playGameMusic() => _playMusic('audio/game-background-music.m4a');

  Future<void> _playMusic(String asset) async {
    final requestId = ++_musicRequestId;
    _currentMusic = asset;
    try {
      await _musicPlayer.stop();
      if (requestId != _musicRequestId || !_musicEnabled || _disposed) return;
      await _musicPlayer.setReleaseMode(ReleaseMode.loop);
      if (requestId != _musicRequestId || !_musicEnabled || _disposed) return;
      await _musicPlayer.play(AssetSource(asset));
    } catch (error) {
      debugPrint('Could not play music $asset: $error');
    }
  }

  Future<void> stopMusic() async {
    _musicRequestId++;
    _currentMusic = null;
    try {
      await _musicPlayer.stop();
    } catch (error) {
      debugPrint('Could not stop music: $error');
    }
  }

  Future<void> pauseMusic() async {
    try {
      await _musicPlayer.pause();
    } catch (error) {
      debugPrint('Could not pause music: $error');
    }
  }

  Future<void> resumeMusic() async {
    if (!_musicEnabled || _currentMusic == null || _disposed) return;
    try {
      await _musicPlayer.resume();
    } catch (error) {
      debugPrint('Could not resume music: $error');
    }
  }

  Future<void> setMusicEnabled(bool enabled) async {
    if (_musicEnabled == enabled) return;
    _musicEnabled = enabled;
    notifyListeners();
    if (enabled) {
      final asset = _currentMusic;
      if (asset != null) await _playMusic(asset);
    } else {
      await pauseMusic();
    }
  }

  Future<void> setEffectsEnabled(bool enabled) async {
    if (_effectsEnabled == enabled) return;
    _effectsEnabled = enabled;
    notifyListeners();
    if (!enabled) {
      try {
        await _effectPlayer.stop();
      } catch (error) {
        debugPrint('Could not stop sound effects: $error');
      }
    }
  }

  void playEffect(String asset) {
    if (!_effectsEnabled || _disposed) return;
    unawaited(_playEffect(asset));
  }

  Future<void> _playEffect(String asset) async {
    try {
      await _effectPlayer.stop();
      if (!_effectsEnabled || _disposed) return;
      await _effectPlayer.play(AssetSource(asset));
    } catch (error) {
      debugPrint('Could not play sound effect $asset: $error');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_musicPlayer.dispose());
    unawaited(_effectPlayer.dispose());
    super.dispose();
  }
}
