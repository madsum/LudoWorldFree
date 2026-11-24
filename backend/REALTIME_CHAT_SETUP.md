# Realtime chat backend

This backend adds JWT-protected REST and WebSocket chat APIs to the existing Spring Boot service. PostgreSQL is the durable source of truth; Redis provides cross-instance event fanout and expiring presence. Message writes and outbox rows commit in one PostgreSQL transaction before a `sent` acknowledgement is returned.

## Data model

- `user_accounts` and `player_profiles` remain the identity/profile tables already used by Ludo World Free.
- `conversations` stores DIRECT/GROUP metadata and the monotonically increasing `last_sequence` counter.
- `conversation_participants` controls membership and stores each member's read cursor.
- `messages` is hash partitioned into 16 PostgreSQL partitions by `conversation_id`. Its `(conversation_id, sequence)` key provides ordered sync; a unique client message ID per sender/conversation makes retries idempotent.
- `message_receipts` tracks delivery/read times per recipient.
- `chat_outbox` is the durable event outbox consumed by any application instance and published through Redis.
- `chat_presence` stores last-seen timestamps; Redis sorted sets hold per-device heartbeats with TTL.
- `chat_media_uploads` binds short-lived upload grants and attached media objects to a user and conversation.
- `chat_device_key_bundles` stores only public E2EE identity keys, signed prekeys, signatures and one-time prekeys. Device private keys are never sent to the server.

The migration is `src/main/resources/db/migration/V8__create_realtime_chat.sql`; `src/main/resources/schema.sql` includes the equivalent schema for manual provisioning. Existing friendship rows are required to start direct and group conversations.

## Local setup

From the `backend` directory:

```sh
export CHAT_JWT_SECRET="$(openssl rand -hex 32)"
docker compose -f compose.chat.yml up --build
```

This starts PostgreSQL on `localhost:5432`, Redis on `localhost:6379`, and the API on `localhost:8080`. Flyway applies the schema migrations on startup. To stop the services, run `docker compose -f compose.chat.yml down`; add `-v` only when you intend to delete the local database and Redis data.

Use an existing trusted identity provider to issue JWTs whose `sub` is the account UUID in `user_accounts`. Configure `CHAT_JWT_SECRET` to the same HS256 signing secret locally, or configure the intended issuer/audience values with `CHAT_JWT_ISSUER` and `CHAT_JWT_AUDIENCE`. Production secrets belong in a secret manager. The API verifies signatures, expiry, optional issuer and audience; it does not mint login tokens. If the secret is missing or shorter than 32 UTF-8 bytes, the backend logs an error and continues starting, while chat endpoints reject JWTs until the secret is configured. This keeps the existing game APIs available during chat setup.

For S3-compatible media in realtime conversations, set `CHAT_MEDIA_BUCKET`, `CHAT_MEDIA_REGION` (for example `eu-west-1`), and AWS credentials in the backend environment. `CHAT_MEDIA_ENDPOINT` may point at an S3-compatible provider. Leave the bucket unset to disable realtime conversation media endpoints. Uploads are limited to supported image, audio, and common document MIME types up to 20 MB; the pre-signed PUT binds content type, length and SHA-256 checksum. Buddy chat attachments use the persistent database and do not depend on the S3 bucket configuration.

## HTTP API

All routes below require `Authorization: Bearer <JWT>`.

- `GET /api/v1/chat/me` and `PATCH /api/v1/chat/me` read/update profile fields.
- `GET /api/v1/chat/contacts?q=...` searches accepted friends and reports presence/last seen.
- `POST /api/v1/chat/conversations/direct` with `{ "userId": "..." }` creates or returns the unique direct conversation.
- `POST /api/v1/chat/conversations/groups` with `{ "title": "...", "memberIds": ["..."] }` creates a group with the caller and selected friends.
- `GET /api/v1/chat/conversations` lists the caller's conversations.
- `GET /api/v1/chat/conversations/{id}/messages?afterSequence=0&limit=100` syncs ordered history and returns `nextAfterSequence`, `conversationLastSequence` and `hasMore` for paging.
- `POST /api/v1/chat/conversations/{id}/messages` persists and sends a message. Supply a stable UUID `clientMessageId` on retries.
- `POST /api/v1/chat/conversations/{id}/delivered` and `/read` with `{ "sequence": 123 }` persist receipts.
- `POST /api/v1/chat/conversations/{id}/media/uploads` creates a media upload grant; `GET /api/v1/chat/conversations/{id}/media/{attachmentId}` creates an authorized download URL.

## WebSocket protocol

Connect to `ws://localhost:8080/ws/chat` (TLS in production) with the same Bearer JWT in the HTTP upgrade `Authorization` header. JSON frames support:

- `{ "type":"heartbeat" }` — renews online TTL; send every 25 seconds (TTL defaults to 65 seconds).
- `{ "type":"subscribe", "conversationIds":["..."] }` — validates membership for the selected conversations.
- `{ "type":"send", "conversationId":"...", "clientMessageId":"...", "body":"...", "contentType":"TEXT" }` — accepts optional `encrypted`, `ciphertext`, `attachments`, and `replyToSequence` fields. The `sent` response means PostgreSQL commit completed.
- `{ "type":"delivered"|"read", "conversationId":"...", "sequence":123 }` — records and broadcasts a receipt.
- `{ "type":"typing", "conversationId":"...", "isTyping":true }` — ephemeral event, not persisted.

Incoming `message`, `receipt`, `presence`, and `typing` events are routed to all local sockets for each recipient via Redis Pub/Sub. Reconnect clients should sync using `afterSequence` and deduplicate/order by conversation plus sequence. The outbox is at-least-once across process failure, so consumers must tolerate repeated event delivery.

## Encryption extension

The schema supports a public per-device prekey bundle. To add E2EE, clients should generate identity keys, sign a rotating prekey, publish one-time prekeys, fetch recipients' bundles over authenticated APIs, then establish per-device sessions using a reviewed protocol such as X3DH plus Double Ratchet. Encrypt media before uploading. Send only ciphertext and opaque attachment metadata; never send private key material to this backend. Key publication/fetch endpoints and client cryptographic code are an extension point, not implemented in this server deliverable.
