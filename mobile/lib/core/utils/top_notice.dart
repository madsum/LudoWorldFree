import 'dart:async';

import 'package:flutter/material.dart';

/// Shows short lived app feedback at the top of the screen, away from game
/// controls and the dice area at the bottom.
class TopNotice {
  TopNotice._();

  static const Color _noticeBackground = Color(0xFF00FF00);
  static const Color _noticeForeground = Colors.black;

  static final Map<OverlayState, OverlayEntry> _entries = {};

  // Keep the color parameters source-compatible with existing callers; every
  // top notice uses the same high-contrast palette regardless of call site.
  static void show(
    BuildContext context,
    String message, {
    Color backgroundColor = _noticeBackground,
    Color foregroundColor = _noticeForeground,
    Duration duration = const Duration(seconds: 4),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    showOnOverlay(
      Overlay.maybeOf(context, rootOverlay: true),
      message,
      backgroundColor: _noticeBackground,
      foregroundColor: _noticeForeground,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void showOnOverlay(
    OverlayState? overlay,
    String message, {
    Color backgroundColor = _noticeBackground,
    Color foregroundColor = _noticeForeground,
    Duration duration = const Duration(seconds: 4),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (overlay == null) return;

    _entries.remove(overlay)?.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) {
        return Positioned(
          top: 8,
          left: 12,
          right: 12,
          child: SafeArea(
            bottom: false,
            child: Material(
              color: Colors.transparent,
              child: Semantics(
                liveRegion: true,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 52),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: _noticeBackground,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white24),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black38,
                        blurRadius: 16,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          message,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _noticeForeground,
                            fontSize: 14,
                            height: 1.3,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (actionLabel != null && onAction != null) ...[
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () {
                            if (identical(_entries[overlay], entry)) {
                              _entries.remove(overlay);
                              entry.remove();
                            }
                            onAction();
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: _noticeForeground,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          child: Text(actionLabel),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    _entries[overlay] = entry;
    overlay.insert(entry);
    Timer(duration, () {
      if (!identical(_entries[overlay], entry)) return;
      _entries.remove(overlay);
      entry.remove();
    });
  }
}
