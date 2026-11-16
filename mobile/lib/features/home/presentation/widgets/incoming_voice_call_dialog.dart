import 'package:flutter/material.dart';

import '../../../game/presentation/services/voice_call_service.dart';

class IncomingVoiceCallDialog extends StatelessWidget {
  const IncomingVoiceCallDialog({super.key, required this.voiceCallService});

  final VoiceCallService voiceCallService;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Incoming voice call'),
        content: Text(
            '${voiceCallService.call?.peerName ?? 'Your buddy'} is calling.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              voiceCallService.declineIncomingCall();
            },
            child: const Text('DECLINE'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              voiceCallService.acceptIncomingCall();
            },
            icon: const Icon(Icons.call_rounded),
            label: const Text('ANSWER'),
          ),
        ],
      );
}
