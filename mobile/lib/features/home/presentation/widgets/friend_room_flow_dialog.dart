import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/websocket_service.dart';
import '../../../../core/utils/top_notice.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../game/domain/models/game_mode.dart';
import '../../../game/domain/models/ludo_color.dart';
import '../../../game/domain/models/player_model.dart';

class FriendRoomFlowDialog extends ConsumerStatefulWidget {
  const FriendRoomFlowDialog({
    super.key,
    required this.onStartMatch,
    this.initialRoomCode,
  });

  final void Function(List<PlayerModel> players, String roomId, String playerId,
      LudoColor selectedColor, GameMode gameMode) onStartMatch;
  final String? initialRoomCode;

  static Future<void> show(
    BuildContext context, {
    String? initialRoomCode,
    required void Function(List<PlayerModel> players, String roomId,
            String playerId, LudoColor selectedColor, GameMode gameMode)
        onStartMatch,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (_) => FriendRoomFlowDialog(
        onStartMatch: onStartMatch,
        initialRoomCode: initialRoomCode,
      ),
    );
  }

  @override
  ConsumerState<FriendRoomFlowDialog> createState() =>
      _FriendRoomFlowDialogState();
}

class _FriendRoomFlowDialogState extends ConsumerState<FriendRoomFlowDialog> {
  static const _gold = Color(0xFFFFC928);
  static const _navy = Color(0xFF082A63);
  static const _panel = Color(0xFF0D3475);
  static const _colors = LudoColor.values;
  static const _skinNames = [
    'Classic Pawn',
    'Lightning',
    'Whirlwind',
    'Ranger'
  ];
  static const _skinIcons = [
    Icons.location_on,
    Icons.bolt,
    Icons.cyclone,
    Icons.shield,
  ];

  int _step = 0;
  int _playerCount = 2;
  int _entryFee = 100;
  bool _voiceChat = false;
  bool _isJoinFlow = false;
  bool _busy = false;
  int _skinIndex = 0;
  LudoColor _selectedColor = LudoColor.red;
  GameMode _gameMode = GameMode.classic;
  final TextEditingController _codeController = TextEditingController();
  final String _sessionId = _newSessionId();
  Map<String, dynamic>? _room;
  Timer? _roomPollTimer;
  bool _launchingMatch = false;
  bool _isHost = false;

  @override
  void initState() {
    super.initState();
    final initialCode = widget.initialRoomCode?.trim();
    if (initialCode != null && RegExp(r'^\d{8}$').hasMatch(initialCode)) {
      _isJoinFlow = true;
      _codeController.text = initialCode;
    }
  }

  static String _newSessionId() {
    final random = math.Random.secure();
    return List.generate(
            4, (_) => random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0'))
        .join();
  }

  @override
  void dispose() {
    _roomPollTimer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _nextStep() async {
    final user = ref.read(authControllerProvider).user;
    if (user == null) {
      _notice('Sign in to create or join a friend room.');
      return;
    }
    if (!_isJoinFlow && _entryFee > user.coins) {
      _notice('Your coin balance is too low for this entry amount.');
      return;
    }
    if (_isJoinFlow && _codeController.text.trim().length != 8) {
      _notice('Enter the eight-digit room code.');
      return;
    }
    if (_isJoinFlow) {
      setState(() => _busy = true);
      try {
        final response = await ref.read(apiClientProvider).get(
              '/friend-rooms/${_codeController.text.trim()}/preview',
              options: Options(headers: {'X-Player-ID': user.id}),
            );
        final room = Map<String, dynamic>.from(response.data as Map);
        final seats = (room['seats'] as List?) ?? const [];
        final occupied = seats
            .whereType<Map>()
            .map((seat) => seat['selectedColor']?.toString())
            .whereType<String>()
            .toSet();
        final available =
            _colors.where((color) => !occupied.contains(color.name));
        if (available.isEmpty) {
          _notice('This room has no available colors.');
          return;
        }
        setState(() {
          _room = room;
          _playerCount = (room['playerCount'] as num).toInt();
          _entryFee = (room['entryFee'] as num).toInt();
          _gameMode = GameMode.fromWireValue(room['gameMode']);
          if (occupied.contains(_selectedColor.name)) {
            _selectedColor = available.first;
          }
          _step = 1;
        });
      } catch (error) {
        _notice(_errorText(error));
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
    setState(() => _step = 1);
  }

  Future<void> _createRoom() async {
    final user = ref.read(authControllerProvider).user;
    if (user == null) return;
    setState(() => _busy = true);
    try {
      final response = await ref.read(apiClientProvider).post(
            '/friend-rooms',
            data: {
              'displayName': user.name,
              'avatarUrl': user.avatarUrl ?? 'assets/images/black-mask.webp',
              'country': user.country,
              'countryFlag': user.countryFlag,
              'entryFee': _entryFee,
              'playerCount': _playerCount,
              'selectedColor': _selectedColor.name,
              'gameMode': _gameMode.wireValue,
              'sessionId': _sessionId,
              'tokenSkinId': 'default',
              'voiceChat': _voiceChat,
            },
            options: Options(headers: {'X-Player-ID': user.id}),
          );
      _room = Map<String, dynamic>.from(response.data as Map);
      _isHost = true;
      _enterRoomScreen();
    } catch (error) {
      _notice(_errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _joinRoom() async {
    final user = ref.read(authControllerProvider).user;
    final code = _codeController.text.trim();
    if (user == null) return;
    setState(() => _busy = true);
    try {
      final response = await ref.read(apiClientProvider).post(
            '/friend-rooms/$code/join',
            data: {
              'displayName': user.name,
              'avatarUrl': user.avatarUrl ?? 'assets/images/black-mask.webp',
              'country': user.country,
              'countryFlag': user.countryFlag,
              'selectedColor': _selectedColor.name,
              'sessionId': _sessionId,
              'tokenSkinId': 'default',
            },
            options: Options(headers: {'X-Player-ID': user.id}),
          );
      _room = Map<String, dynamic>.from(response.data as Map);
      _isHost = false;
      _playerCount = (_room!['playerCount'] as num).toInt();
      _entryFee = (_room!['entryFee'] as num).toInt();
      _gameMode = GameMode.fromWireValue(_room!['gameMode']);
      _enterRoomScreen();
    } catch (error) {
      _notice(_errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _enterRoomScreen() {
    setState(() => _step = 2);
    unawaited(_refreshRoom());
    _roomPollTimer?.cancel();
    _roomPollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_refreshRoom()),
    );
  }

  Future<void> _refreshRoom() async {
    final user = ref.read(authControllerProvider).user;
    final code = _room?['roomCode']?.toString();
    if (user == null || code == null || _launchingMatch) return;
    try {
      final response = await ref.read(apiClientProvider).get(
            '/friend-rooms/$code/status',
            options: Options(headers: {'X-Player-ID': user.id}),
          );
      if (!mounted) return;
      final next = Map<String, dynamic>.from(response.data as Map);
      setState(() => _room = next);
      if (next['started'] == true) {
        final match = next['match'];
        await _launchMatch(
          match is Map ? Map<String, dynamic>.from(match) : const {},
        );
      }
    } catch (error) {
      if (error is DioException && error.response?.statusCode == 404) {
        _roomPollTimer?.cancel();
        _notice('This room is no longer available.');
      }
    }
  }

  Future<void> _startRoom() async {
    final user = ref.read(authControllerProvider).user;
    final code = _room?['roomCode']?.toString();
    if (user == null || code == null) return;
    setState(() => _busy = true);
    try {
      final response = await ref.read(apiClientProvider).post(
            '/friend-rooms/$code/start',
            options: Options(headers: {'X-Player-ID': user.id}),
          );
      final body = Map<String, dynamic>.from(response.data as Map);
      setState(() => _room = body);
      final match = body['match'];
      await _launchMatch(
        match is Map ? Map<String, dynamic>.from(match) : const {},
      );
    } catch (error) {
      _notice(_errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _launchMatch(Map<String, dynamic> match) async {
    if (_launchingMatch || !mounted) return;
    _launchingMatch = true;
    final user = ref.read(authControllerProvider).user;
    final roomId = match['roomId']?.toString() ?? _room?['roomId']?.toString();
    final playerId = match['playerId']?.toString() ??
        (user == null ? null : _resolvedPlayerId(user.id));
    final sessionId = match['sessionId']?.toString() ?? _sessionId;
    final players =
        _parsePlayers(match['players']) ?? _parseRoomSeats(_room?['seats']);
    if (user == null || roomId == null || playerId == null || players == null) {
      _launchingMatch = false;
      _notice('The room is ready, but the match details are incomplete.');
      return;
    }
    final connected = await ref.read(webSocketServiceProvider).connectToRoom(
          roomId: roomId,
          playerId: playerId,
          matchmakingSessionId: sessionId,
        );
    if (!connected || !mounted) {
      _launchingMatch = false;
      _notice('Could not connect to the game room. Please try again.');
      return;
    }
    _roomPollTimer?.cancel();
    if (mounted) Navigator.of(context).pop();
    widget.onStartMatch(players, roomId, playerId, _selectedColor, _gameMode);
  }

  List<PlayerModel>? _parsePlayers(dynamic value) {
    final expectedCount =
        (_room?['playerCount'] as num?)?.toInt() ?? _playerCount;
    if (value is! List || value.length != expectedCount) return null;
    final user = ref.read(authControllerProvider).user;
    final players = <PlayerModel>[];
    for (final row in value) {
      if (row is! Map) return null;
      final colorName =
          (row['color'] ?? row['selectedColor'])?.toString().toLowerCase();
      final color = _colors.where((item) => item.name == colorName).firstOrNull;
      final id = (row['id'] ?? row['playerId'])?.toString();
      final name = (row['name'] ?? row['displayName'])?.toString();
      if (color == null || id == null || name == null) return null;
      players.add(PlayerModel.initial(
        id: id,
        name: name,
        avatarUrl: row['avatarUrl']?.toString(),
        country: row['country']?.toString() ?? 'World',
        countryFlag: row['countryFlag']?.toString() ?? '🌐',
        coins: (row['coins'] as num?)?.toInt() ?? 0,
        diamonds: (row['diamonds'] as num?)?.toInt() ?? 0,
        color: color,
        isBot: false,
      ));
    }
    if (players.length != expectedCount || players.any((p) => p.isBot)) {
      return null;
    }
    if (user != null && !players.any((p) => _samePlayerId(p.id, user.id))) {
      return null;
    }
    return players;
  }

  List<PlayerModel>? _parseRoomSeats(dynamic value) {
    final expectedCount =
        (_room?['playerCount'] as num?)?.toInt() ?? _playerCount;
    if (value is! List || value.length != expectedCount) return null;
    final user = ref.read(authControllerProvider).user;
    final players = <PlayerModel>[];
    for (var index = 0; index < value.length; index++) {
      final row = value[index];
      if (row is! Map) return null;
      var colorName = row['selectedColor']?.toString().toLowerCase();
      if (expectedCount == 2 && index == 1 && players.isNotEmpty) {
        colorName = switch (players.first.color) {
          LudoColor.red => LudoColor.yellow.name,
          LudoColor.green => LudoColor.blue.name,
          LudoColor.yellow => LudoColor.red.name,
          LudoColor.blue => LudoColor.green.name,
        };
      }
      final color = _colors.where((item) => item.name == colorName).firstOrNull;
      final id = row['playerId']?.toString();
      final name = row['displayName']?.toString();
      if (color == null || id == null || name == null) return null;
      players.add(PlayerModel.initial(
        id: id,
        name: name,
        avatarUrl: row['avatarUrl']?.toString(),
        country: row['country']?.toString() ?? 'World',
        countryFlag: row['countryFlag']?.toString() ?? '🌐',
        coins: user != null && _samePlayerId(id, user.id) ? user.coins : 0,
        diamonds:
            user != null && _samePlayerId(id, user.id) ? user.diamonds : 0,
        color: color,
        isBot: false,
      ));
    }
    if (user != null &&
        !players.any((player) => _samePlayerId(player.id, user.id))) {
      return null;
    }
    return players;
  }

  bool _samePlayerId(String serverId, String appId) =>
      serverId.toLowerCase() == _resolvedPlayerId(appId);

  String _resolvedPlayerId(String appId) {
    final normalized = appId.toLowerCase();
    if (RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    ).hasMatch(normalized)) {
      return normalized;
    }

    // Mirror PlayerIdResolver.resolve on the backend: UUID.nameUUIDFromBytes
    // creates a deterministic UUID v3 from the UTF-8 bytes of the app ID.
    final bytes = List<int>.from(md5.convert(utf8.encode(appId)).bytes);
    bytes[6] = (bytes[6] & 0x0f) | 0x30;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }

  Uri? _roomInviteUri(String? code) {
    if (code == null) return null;
    final apiBase = Uri.parse(AppConstants.defaultApiBaseUrl);
    return apiBase.replace(
      path: '${apiBase.path.replaceFirst(RegExp(r'/+$'), '')}'
          '/friend-rooms/invite/$code',
      query: null,
      fragment: null,
    );
  }

  Future<void> _shareRoom() async {
    final code = _room?['roomCode']?.toString();
    if (code == null) return;
    final inviteUri = _roomInviteUri(code);
    await SharePlus.instance.share(ShareParams(
      text: 'Join my Ludo World game! Room code: $code\n'
          'Mode: ${_gameMode.displayName} · Entry: $_entryFee coins'
          '${inviteUri == null ? '' : '\nOpen room: $inviteUri'}',
      subject: 'Join my Ludo World room',
    ));
  }

  Future<void> _shareWhatsApp() async {
    final code = _room?['roomCode']?.toString();
    if (code == null) return;
    final text = Uri.encodeComponent(
      'Join my Ludo World game! Room code: $code. '
      'Mode: ${_gameMode.displayName} · Entry: $_entryFee coins. '
      'Open room: ${_roomInviteUri(code)}',
    );
    final uri = Uri.parse('https://wa.me/?text=$text');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      await _shareRoom();
    }
  }

  Future<void> _copyCode() async {
    final code = _room?['roomCode']?.toString();
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) _notice('Room code copied.');
  }

  Future<void> _closeRoomAndExit() async {
    _roomPollTimer?.cancel();
    final user = ref.read(authControllerProvider).user;
    final code = _room?['roomCode']?.toString();
    if (_isHost && user != null && code != null && _room?['started'] != true) {
      try {
        await ref.read(apiClientProvider).delete('/friend-rooms/$code',
            options: Options(headers: {'X-Player-ID': user.id}));
      } catch (_) {}
    } else if (user != null && code != null && _room?['started'] != true) {
      try {
        await ref.read(apiClientProvider).delete('/friend-rooms/$code/leave',
            options: Options(headers: {'X-Player-ID': user.id}));
      } catch (_) {}
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _notice(String message) {
    if (mounted) TopNotice.show(context, message);
  }

  String _errorText(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['message'] != null) {
        return data['message'].toString();
      }
      if (data is Map && data['detail'] != null) {
        return data['detail'].toString();
      }
    }
    return 'Could not complete the room request. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final size = MediaQuery.sizeOf(context);
    return Dialog.fullscreen(
      backgroundColor: const Color(0xE8000615),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Column(
                children: [
                  _buildHeader(user?.coins ?? 0, user?.diamonds ?? 0),
                  const SizedBox(height: 12),
                  _buildProgress(),
                  const SizedBox(height: 12),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: _step == 0
                          ? _buildLobbyStep(user?.coins ?? 0)
                          : _step == 1
                              ? _buildSelectionStep(user?.coins ?? 0)
                              : _buildRoomStep(user),
                    ),
                  ),
                  if (size.height > 650) const SizedBox(height: 6),
                  if (_step < 2) _buildFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(int coins, int diamonds) => Row(
        children: [
          _circleButton(Icons.arrow_back_rounded, _closeRoomAndExit),
          const SizedBox(width: 10),
          Expanded(
            child: Text('FRIEND ROOM',
                textAlign: TextAlign.center,
                style: _font(20, _gold, weight: FontWeight.w900)),
          ),
          _balancePill(Icons.diamond, diamonds, const Color(0xFF59CEFF)),
          const SizedBox(width: 6),
          _balancePill(Icons.monetization_on, coins, _gold),
        ],
      );

  Widget _buildProgress() => Row(
        children: List.generate(3, (index) {
          final active = index <= _step;
          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              height: 5,
              decoration: BoxDecoration(
                color: active ? _gold : Colors.white24,
                borderRadius: BorderRadius.circular(8),
                boxShadow: active
                    ? const [BoxShadow(color: Color(0x99FFC928), blurRadius: 6)]
                    : null,
              ),
            ),
          );
        }),
      );

  Widget _buildLobbyStep(int coins) => _stepPanel(
        key: const ValueKey('step-lobby'),
        title: 'SELECT PLAYERS',
        subtitle: 'Set up a private game for your friends',
        children: [
          Row(children: [
            _choiceChip('2 PLAYERS', _playerCount == 2,
                () => setState(() => _playerCount = 2)),
            const SizedBox(width: 8),
            _choiceChip('4 PLAYERS', _playerCount == 4,
                () => setState(() => _playerCount = 4)),
            const SizedBox(width: 8),
            _choiceChip('TEAM UP · SOON', false, null),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            _tab('CREATE', !_isJoinFlow,
                () => setState(() => _isJoinFlow = false)),
            _tab('JOIN', _isJoinFlow, () => setState(() => _isJoinFlow = true)),
          ]),
          const SizedBox(height: 12),
          if (_isJoinFlow) ...[
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              maxLength: 8,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              style: _font(26, Colors.white, weight: FontWeight.w900),
              decoration: _inputDecoration('8-digit room code'),
            ),
          ] else ...[
            _panelCard(
              child: Column(children: [
                Row(children: [
                  const Icon(Icons.mic_rounded, color: _gold),
                  const SizedBox(width: 9),
                  Expanded(
                      child:
                          Text('Voice Chat', style: _font(15, Colors.white))),
                  Switch.adaptive(
                    value: _voiceChat,
                    activeThumbColor: _gold,
                    onChanged: (value) => setState(() => _voiceChat = value),
                  ),
                ]),
                const Divider(color: Color(0x55FFFFFF)),
                Text('ENTRY AMOUNT',
                    style: _font(13, _gold, weight: FontWeight.w800)),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _roundControl(
                      Icons.remove,
                      _entryFee <= 100
                          ? null
                          : () => setState(() => _entryFee -= 100)),
                  const SizedBox(width: 18),
                  Column(children: [
                    const Icon(Icons.monetization_on, color: _gold, size: 28),
                    Text(_entryFee.toString(),
                        style:
                            _font(24, Colors.white, weight: FontWeight.w900)),
                  ]),
                  const SizedBox(width: 18),
                  _roundControl(
                      Icons.add,
                      _entryFee + 100 > coins
                          ? null
                          : () => setState(() => _entryFee += 100)),
                ]),
                Text('Available: $coins coins',
                    style: _font(11, Colors.white70)),
              ]),
            ),
          ],
        ],
      );

  Widget _buildSelectionStep(int coins) => SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 8),
        child: _stepPanel(
          key: const ValueKey('step-select'),
          title: 'SELECT TOKEN / COLOR',
          subtitle: _isJoinFlow
              ? 'Choose your color to join the host’s game'
              : 'Your choices are saved in the room',
          children: [
            if (!_isJoinFlow) ...[
              _skinPicker(),
              const SizedBox(height: 14),
            ],
            _panelCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CHOOSE YOUR COLOR',
                        style: _font(14, _gold, weight: FontWeight.w900)),
                    const SizedBox(height: 10),
                    Wrap(
                        spacing: 9,
                        runSpacing: 9,
                        children: _colors.map((color) {
                          final selected = _selectedColor == color;
                          final taken = _isJoinFlow &&
                              ((_room?['seats'] as List?) ?? const [])
                                  .whereType<Map>()
                                  .any((seat) =>
                                      seat['selectedColor'] == color.name);
                          return InkWell(
                            onTap: taken
                                ? null
                                : () => setState(() => _selectedColor = color),
                            borderRadius: BorderRadius.circular(30),
                            child: Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: taken
                                    ? color.color.withValues(alpha: 0.28)
                                    : color.color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: selected
                                        ? Colors.white
                                        : Colors.white54,
                                    width: selected ? 3 : 1),
                                boxShadow: selected
                                    ? const [
                                        BoxShadow(color: _gold, blurRadius: 12)
                                      ]
                                    : null,
                              ),
                              child: taken
                                  ? const Icon(Icons.block,
                                      color: Colors.white70, size: 22)
                                  : selected
                                      ? const Icon(Icons.check,
                                          color: Colors.white, size: 28)
                                      : null,
                            ),
                          );
                        }).toList()),
                  ]),
            ),
            if (!_isJoinFlow) ...[
              const SizedBox(height: 14),
              _gameModePicker(),
            ],
            if (_isJoinFlow)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                    'Host selected ${_gameMode.displayName}. Room settings and entry amount are set by the host.',
                    style: _font(12, Colors.white70),
                    textAlign: TextAlign.center),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('Entry: $_entryFee coins · Available: $coins',
                    style: _font(12, Colors.white70),
                    textAlign: TextAlign.center),
              ),
          ],
        ),
      );

  Widget _buildRoomStep(dynamic user) {
    final seats = (_room?['seats'] as List?) ?? const [];
    final target = (_room?['playerCount'] as num?)?.toInt() ?? _playerCount;
    final code = _room?['roomCode']?.toString() ?? '--------';
    return _stepPanel(
      key: const ValueKey('step-room'),
      title: 'ONLINE MULTIPLAYER',
      subtitle: 'Invite friends to join your room',
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF860C14),
            border: Border.all(color: Colors.white, width: 2),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(children: [
            Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  Text('Room Code:',
                      style: _font(17, Colors.white, weight: FontWeight.w800)),
                  SelectableText(code,
                      style: _font(22, _gold, weight: FontWeight.w900)),
                  _smallAction(Icons.copy, 'Copy', _copyCode),
                  _smallAction(Icons.share, 'Share', _shareRoom),
                ]),
            const SizedBox(height: 5),
            Text('${_gameMode.displayName}  ›  Entry Amount: $_entryFee coins',
                textAlign: TextAlign.center,
                style: _font(13, const Color(0xFF9BFF59),
                    weight: FontWeight.w800)),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _smallAction(Icons.chat, 'WhatsApp', _shareWhatsApp),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: GridView.builder(
            itemCount: target,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: target == 2 ? 2 : 2,
              childAspectRatio: 1.55,
              crossAxisSpacing: 9,
              mainAxisSpacing: 9,
            ),
            itemBuilder: (context, index) {
              final seat = index < seats.length ? seats[index] : null;
              return _seatCard(seat, user, index);
            },
          ),
        ),
        Text('${seats.length} / $target players joined',
            style: _font(13, Colors.white70, weight: FontWeight.w700)),
        const SizedBox(height: 10),
        if (_isHost)
          _primaryButton(
            seats.length == target ? 'START GAME' : 'WAITING FOR PLAYERS',
            seats.length == target && !_busy ? _startRoom : null,
            busy: _busy,
          )
        else
          Text('Waiting for the host to start…',
              style: _font(13, _gold, weight: FontWeight.w700)),
      ],
    );
  }

  Widget _seatCard(dynamic seat, dynamic user, int index) {
    if (seat is! Map) {
      return InkWell(
        onTap: _shareRoom,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            border: Border.all(color: Colors.white70, width: 1.4),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.person_add_alt_1, color: _gold, size: 32),
            const SizedBox(height: 4),
            Text('INVITE FRIEND',
                style: _font(10, Colors.white70, weight: FontWeight.w800)),
          ]),
        ),
      );
    }
    final name = seat['displayName']?.toString() ?? 'Player';
    final avatar = seat['avatarUrl']?.toString();
    final color =
        _colors.where((c) => c.name == seat['selectedColor']).firstOrNull;
    final host =
        seat['playerId']?.toString() == _room?['hostPlayerId']?.toString();
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _panel,
        border: Border.all(color: color?.color ?? _gold, width: 2),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: Colors.white12,
          backgroundImage: avatar == null || avatar.startsWith('assets/')
              ? null
              : NetworkImage(avatar),
          child: avatar == null || avatar.startsWith('assets/')
              ? const Icon(Icons.person, color: Colors.white, size: 28)
              : null,
        ),
        const SizedBox(width: 8),
        Expanded(
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _font(12, Colors.white, weight: FontWeight.w800)),
              Text(host ? 'HOST' : 'FRIEND',
                  style: _font(10, _gold, weight: FontWeight.w700)),
            ])),
        if (color != null)
          Container(
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                color: color.color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1),
              )),
      ]),
    );
  }

  Widget _skinPicker() => _panelCard(
        child: Column(children: [
          Text('SELECT TOKEN',
              style: _font(14, _gold, weight: FontWeight.w900)),
          const SizedBox(height: 10),
          Row(children: [
            IconButton(
              onPressed: () => setState(
                  () => _skinIndex = (_skinIndex - 1) < 0 ? 3 : _skinIndex - 1),
              icon: const Icon(Icons.chevron_left, color: _gold, size: 32),
            ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(
                    4,
                    (index) => InkWell(
                          onTap: () {
                            if (index != 0) {
                              _notice(
                                  'This token is locked. The Classic Pawn is available.');
                              return;
                            }
                            setState(() => _skinIndex = index);
                          },
                          child: Stack(clipBehavior: Clip.none, children: [
                            Container(
                              width: 48,
                              height: 54,
                              decoration: BoxDecoration(
                                color: index == _skinIndex
                                    ? const Color(0xFF174D9A)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: index == 0
                                    ? Border.all(color: _gold, width: 2)
                                    : null,
                              ),
                              child: Icon(_skinIcons[index],
                                  color: index == 0 ? _gold : Colors.white54,
                                  size: 34),
                            ),
                            if (index > 0)
                              const Positioned(
                                  right: -2,
                                  top: -4,
                                  child:
                                      Icon(Icons.lock, color: _gold, size: 15)),
                          ]),
                        )),
              ),
            ),
            IconButton(
              onPressed: () =>
                  setState(() => _skinIndex = (_skinIndex + 1) % 4),
              icon: const Icon(Icons.chevron_right, color: _gold, size: 32),
            ),
          ]),
          Text(_skinNames[_skinIndex], style: _font(11, Colors.white70)),
        ]),
      );

  Widget _gameModePicker() => _panelCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text('SELECT GAME',
                    style: _font(14, _gold, weight: FontWeight.w900))),
            IconButton(
              tooltip: 'Game rules',
              onPressed: _showModeInfo,
              icon: const Icon(Icons.help_outline, color: _gold),
            ),
          ]),
          _modeTile(GameMode.classic),
          _modeTile(GameMode.firstKill),
        ]),
      );

  Widget _modeTile(GameMode mode) {
    final selected = _gameMode == mode;
    return InkWell(
      onTap: () => setState(() => _gameMode = mode),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: mode == GameMode.classic
                  ? const [Color(0xFF2378D9), Color(0xFF123F94)]
                  : const [Color(0xFFBA1D2C), Color(0xFF791320)]),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? _gold : Colors.white30,
              width: selected ? 2.4 : 1),
          boxShadow: selected
              ? const [BoxShadow(color: Color(0x88FFC928), blurRadius: 9)]
              : null,
        ),
        child: Row(children: [
          Icon(selected ? Icons.check_circle : Icons.circle_outlined,
              color: selected ? _gold : Colors.white70),
          const SizedBox(width: 9),
          Text(mode.displayName.toUpperCase(),
              style: _font(15, Colors.white, weight: FontWeight.w900)),
          const Spacer(),
          if (mode == GameMode.firstKill)
            const Icon(Icons.flash_on, color: _gold),
        ]),
      ),
    );
  }

  Future<void> _showModeInfo() => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
            backgroundColor: _navy,
            title: Text(_gameMode.displayName,
                style: _font(18, _gold, weight: FontWeight.w900)),
            content: Text(
                _gameMode == GameMode.classic
                    ? 'Move your pawns around the board and bring them all home to win.'
                    : 'The first player to capture an opponent pawn wins the entire game.',
                style: _font(14, Colors.white)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('GOT IT',
                      style: _font(13, _gold, weight: FontWeight.w800)))
            ]),
      );

  Widget _stepPanel(
          {required Key key,
          required String title,
          required String subtitle,
          required List<Widget> children}) =>
      Container(
        key: key,
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_panel, _navy]),
          border: Border.all(color: _gold, width: 2),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(color: Color(0xAAFFC928), blurRadius: 15)
          ],
        ),
        child: Column(children: [
          Text(title,
              textAlign: TextAlign.center,
              style: _font(20, _gold, weight: FontWeight.w900)),
          Text(subtitle,
              textAlign: TextAlign.center, style: _font(11, Colors.white70)),
          const SizedBox(height: 14),
          ...children,
        ]),
      );

  Widget _buildFooter() => Row(children: [
        if (_step > 0)
          Expanded(
              child: _secondaryButton('BACK', () => setState(() => _step--))),
        if (_step > 0) const SizedBox(width: 10),
        Expanded(
          flex: _step == 0 ? 1 : 2,
          child: _primaryButton(
            _step == 0 ? 'NEXT' : (_isJoinFlow ? 'JOIN ROOM' : 'CREATE ROOM'),
            _busy
                ? null
                : (_step == 0
                    ? _nextStep
                    : (_isJoinFlow ? _joinRoom : _createRoom)),
            busy: _busy,
          ),
        ),
      ]);

  Widget _primaryButton(String title, VoidCallback? onPressed,
          {bool busy = false}) =>
      SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1269D3),
              disabledBackgroundColor: Colors.white12,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                  side: const BorderSide(color: _gold, width: 2)),
            ),
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(title,
                    style: _font(15, Colors.white, weight: FontWeight.w900)),
          ));

  Widget _secondaryButton(String title, VoidCallback onPressed) => SizedBox(
      height: 48,
      child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white54),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26))),
          child: Text(title,
              style: _font(13, Colors.white, weight: FontWeight.w800))));

  Widget _choiceChip(String title, bool selected, VoidCallback? onTap) =>
      Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF1C67BD) : Colors.black26,
              border: Border.all(
                  color: selected ? _gold : Colors.white38,
                  width: selected ? 2 : 1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(title,
                textAlign: TextAlign.center,
                style: _font(10, onTap == null ? Colors.white38 : Colors.white,
                    weight: FontWeight.w900)),
          ),
        ),
      );

  Widget _tab(String label, bool selected, VoidCallback onTap) => Expanded(
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF105CC3) : Colors.black26,
              border: Border(
                  bottom: BorderSide(
                      color: selected ? _gold : Colors.white24,
                      width: selected ? 3 : 1)),
            ),
            child: Text(label,
                textAlign: TextAlign.center,
                style: _font(13, selected ? _gold : Colors.white70,
                    weight: FontWeight.w900)),
          ),
        ),
      );

  Widget _roundControl(IconData icon, VoidCallback? onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                border: Border.all(
                    color: onTap == null ? Colors.white24 : _gold, width: 2),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(icon,
                color: onTap == null ? Colors.white24 : Colors.white,
                size: 27)),
      );

  Widget _panelCard({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF061D46).withValues(alpha: 0.78),
          border: Border.all(color: const Color(0x77FFC928)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: child,
      );

  Widget _circleButton(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(25),
        child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: Colors.blue.shade800,
                shape: BoxShape.circle,
                border: Border.all(color: _gold, width: 2)),
            child: Icon(icon, color: Colors.white, size: 20)),
      );

  Widget _balancePill(IconData icon, int value, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
            color: Colors.black38,
            border: Border.all(color: color.withValues(alpha: 0.7)),
            borderRadius: BorderRadius.circular(18)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 3),
          Text(
              value >= 10000
                  ? '${(value / 1000).toStringAsFixed(0)}K'
                  : '$value',
              style: _font(10, Colors.white, weight: FontWeight.w900)),
        ]),
      );

  Widget _smallAction(IconData icon, String label, VoidCallback onTap) =>
      TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: _gold, size: 17),
        label: Text(label,
            style: _font(11, Colors.white, weight: FontWeight.w800)),
        style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 5)),
      );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        counterText: '',
        hintText: hint,
        hintStyle: _font(13, Colors.white54),
        filled: true,
        fillColor: const Color(0xFF061D46),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _gold)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white, width: 2)),
      );

  TextStyle _font(double size, Color color,
          {FontWeight weight = FontWeight.w600}) =>
      GoogleFonts.poppins(fontSize: size, color: color, fontWeight: weight);
}
