# Ludo King comparison follow-up roadmap

Reference: installed Ludo King 10.7.0.423 (com.ludo.king), verified on the connected Android device on 2026-11-08. The comparison and evidence limits are recorded in [the feature comparison](ludo-king-feature-parity-10.7.0.423.md).

## Delivered in the current implementation stage

- Online 1v1 queue and room records shared through PostgreSQL for Cloud Run instances.
- Ordered game-state event relay, reconnect handling and deterministic initial seats.
- Server-issued dice rolls and validation of legal pawn movement, captures, skipped captures and turn ownership.
- Daily goals, friend requests, gold leaderboard and one-to-one friend text chat.

This is a functional baseline, not full Ludo King parity. Online game state is still partly client-authored; triple-six rollback, server-side result settlement and adversarial state validation remain open.

## Later implementation stages

### 1. Finish authoritative online play

- Move the game rules and complete match state into the backend. Treat clients as renderers and input senders.
- Implement the three-consecutive-six rollback rule on the server, including persisted turn-sequence snapshots.
- Persist match outcome, player statistics, entry-fee settlement and rewards in the same transaction as match completion.
- Add expiry/cleanup for abandoned queue tickets, match rooms and ordered state events.
- Check player identity from authenticated credentials rather than trusting a caller-supplied player ID.

**Acceptance:** two clients on different Cloud Run instances complete a match; illegal moves, dice values, turn skips, forged wins and replayed commands are rejected; disconnect/reconnect preserves the authoritative state; each reward settles once.

### 2. Add friend invites and private rooms

- Let an accepted friend invite the other player to a private match.
- Add invite expiry, duplicate suppression, cancellation, and notifications while the recipient is online.
- Reuse the authoritative match room and entry-fee rules.

**Acceptance:** invite, accept, decline, expiry and reconnect flows work across backend instances, with one room and one fee settlement per accepted match.

### 3. Upgrade chat and social safety

- Replace five-second polling with cross-instance live delivery.
- Add message read state, pagination, online presence, block/report controls, rate limits and moderation hooks.
- Add group/club chat only after identity, abuse controls and retention rules are established.
- Evaluate a voice provider separately; store short-lived room tokens server-side and never embed provider secrets in the app.

**Acceptance:** messages arrive live on multiple instances, blocked users cannot message or invite each other, and read state and pagination remain consistent after reconnect.

### 4. Implement Team Up 2v2

- Add team membership and partner turn/result state.
- Match four players with partner-aware reconnect, scoring and reward settlement.
- Build an original Ludo World lobby and board flow.

**Acceptance:** four players finish a team match across instances; partners share the correct result, and one disconnect does not create duplicate turns or payouts.

### 5. Expand daily goals into missions

- Add rotating multi-step objectives, streak/season tracking and a reward track.
- Keep progress event IDs idempotent and claims transactional with wallet updates.

**Acceptance:** repeated game events cannot duplicate progress or rewards; reset boundaries and missed-day behavior are explicit and persisted.

### 6. Add cosmetics and inventory

- Create an original catalog for dice, tokens and board themes, plus owned/equipped inventory.
- Add server-authoritative purchases and spin/reward outcomes with idempotency and audit records.

**Acceptance:** ownership and equipped items survive reinstall/login; clients cannot grant items or alter prices/reward odds.

### 7. Add tournaments

- Add tournament seasons, registration, bracket generation, match advancement and prize settlement.
- Reuse authoritative online matches and idempotent wallet transactions.

**Acceptance:** tournament progression is deterministic, disconnections have defined outcomes, and each bracket result and prize can settle only once.

## Verification gate for each stage

- Verify the feature against current Ludo King behavior without copying its assets or code.
- Review migrations for the existing Cloud SQL PostgreSQL deployment path.
- Run focused backend and Flutter checks, then exercise two real clients for online flows.
- Update the comparison matrix with observed evidence, implemented scope and remaining gaps. Claim parity only when the whole named feature passes its acceptance criteria.
