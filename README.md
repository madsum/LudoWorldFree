# Ludo World Free

Flutter client and Spring Boot API for Ludo World Free.

## Deploy to Google Cloud

The deployment script publishes the API and Flutter web client as separate
Cloud Run services in one region. It uses the existing Cloud SQL instance and
the `db-user` and `db-password` Secret Manager secrets by default.

Prerequisites:

- `gcloud` is installed and authenticated with permission to deploy Cloud Run
  services, build containers, manage Artifact Registry, and use the configured
  Cloud SQL instance and secrets.
- The Google Cloud project has the Cloud SQL instance and Secret Manager
  secrets named above. The Cloud Run runtime identity needs Cloud SQL Client and
  Secret Manager Secret Accessor roles.
- The Cloud Build service account can write to the Artifact Registry repository.

Deploy using the active `gcloud` project, or override project and resource
settings with environment variables:

```sh
./deploy-google-cloud.sh
```

For example:

```sh
PROJECT_ID=my-project REGION=europe-west1 \
SQL_INSTANCE=my-project:europe-west1:my-postgres \
DATABASE_NAME=ludoworldfreedb \
DATABASE_USER_SECRET=db-user DATABASE_PASSWORD_SECRET=db-password \
./deploy-google-cloud.sh
```

The script prints the Cloud Run URLs after deployment. It builds the web
client with the API URL discovered from Cloud Run. Flutter builds can also
override `API_BASE_URL` and `WEBSOCKET_URL` using `--dart-define`.

OAuth provider settings are managed separately from deployment. Add the web
service URL to the relevant provider's allowed origins/redirect URLs. Mobile
OAuth callbacks continue to use the `ludoworldfree://oauth-callback` scheme.

## Game WebSocket protocol

The API exposes a plain JSON WebSocket at `/ws` (no STOMP framing). After
connecting, send a `join` message using the room and player IDs returned by the
matchmaking API:

```json
{"type":"join","roomId":"room_online_...","playerId":"player-uuid"}
```

The server replies with `joined` and sends `player_joined` / `player_left`
notices to the other room member. Relay game actions by sending
`{"type":"event","event":{"action":"..."}}`; the other member receives
the event wrapped with its `roomId` and sender `playerId`. Send `{"type":"ping"}`
to receive `{"type":"pong"}`. A player can only join a room returned for that
player by matchmaking.
