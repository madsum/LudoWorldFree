# Ludo King feature comparison

Reference inspected: installed Android package `com.ludo.king`, version `10.7.0.423` (version code 423), updated 2026-11-08 on device `285d6bbc0d057ece`.

Ludo King is a Unity IL2CPP app. The feature names below come from static metadata and string inspection of the installed APK set. They show that code or assets for a feature are present; they do not prove the feature is currently enabled for every player or region. The extracted `/home/masum/dev/LudoWorldFree/king` folder is an OKX app and is not used as the game reference.

## Comparison

| Area | Ludo World today | Ludo King 10.7 reference evidence | Gap and next work |
| --- | --- | --- | --- |
| Local Ludo | Computer and Pass & Play modes; 2 or 4 players; local rules, AI and animations | Core Ludo plus `TeamUpOnline` game state symbols | Keep improving rules and polish against observed play; do not copy assets or code. |
| Online play | REST queue pairs two players; `/ws/game` requires both to join, relays ordered game-state events through PostgreSQL, gates turns to the current player, and handles heartbeats and reconnects across instances. Dice values are issued by the server. Pawn position changes must match a legal single move, capture, and turn continuation, and game-over claims require a finished player. The 45-second timeout fails visibly instead of inventing an AI opponent. Other game-state metadata and triple-six rollback are not yet fully authoritative. | Online/team-up socket and game-state symbols | Move the full game simulation and all result/reward decisions to the server; cover triple-six rollback and replay/timeout cases. |
| Team Up | Lobby card is a coming-soon action | `TeamUpOnline` data, turn and player swap symbols | 2v2 team matchmaking, partner state and shared result flow are absent. |
| Friends | Social Hub supports exact-username requests, incoming acceptance, outgoing requests, and removal; backed by `/api/v1/friends` | Friend panels and chat-room friend management symbols | In-game invites/private rooms, blocking, and presence are absent. |
| Social/chat/voice | Friends can exchange plain-text messages through a PostgreSQL-backed conversation API and chat dialog; the dialog refreshes every five seconds. Bottom Live Chat remains a placeholder. | Chat-room, socket, voice-call and club-chat symbols | Real-time push, read state, presence, moderation/blocking, group and club chat, and voice integration are absent. |
| Leaderboards | Social Hub shows a server-ranked gold leaderboard with game-count tie-breaks | Leaderboard and reward symbols | Competitive win/season standings still need match-result data. |
| Goals and missions | Daily bonus plus three UTC-reset goals: play two games, win a game, and complete an online game; progress is recorded by game result and rewards are claimed through the backend | Daily Goals, objective, mission and reward symbols | Multi-step objectives, mission seasons, and richer reward tracks are absent. |
| Tournaments | No tournament flow or API | Tournament data symbols | Brackets, registration, match progression and prize settlement are absent. |
| Inventory and cosmetics | No inventory/store flow | Dice, token, theme preview, inventory and spin-wheel symbols | Cosmetic ownership, equip state, catalog and reward flows are absent. |

## Implementation stages

1. ~~Add a usable server-backed leaderboard using the wallet and profile data that already exists.~~
2. ~~Replace the simulated online result with room-based WebSocket gameplay and reconnect handling.~~ ~~Persist queue, room, and ordered state events in PostgreSQL for Cloud Run instances.~~ ~~Issue online dice values on the server and validate legal pawn-position transitions.~~ Move full state simulation and result settlement server-side.
3. Extend the basic friends flow with invitations, private rooms and presence.
4. Expand the basic daily goals into multi-step missions and reward tracks.
5. Add tournament, club/chat/voice and cosmetic inventory systems as separate backend-backed modules.

The implemented rows are partial feature stages, not feature parity. Ludo King is used as a functional reference only; Ludo World uses its own code, UI and assets.

The current device install was verified with Android package metadata and pulled to `/tmp/ludoking_107_latest` on 2026-11-08. REA static APK inspection tools are not configured in this environment, so the feature evidence for this update remains the earlier static metadata/string inspection; version and install time are directly verified from the device.
The remaining feature work is prioritized with acceptance criteria in [the follow-up roadmap](ludo-king-follow-up-roadmap.md).
