# Voice and video call relay setup

The call signaling WebSocket exchanges offers and ICE candidates. Mobile clients
currently use Google's public STUN server for direct peer connections. Networks
that block direct media paths also need a TURN relay; without one, both callers
can remain on “Connecting” even though signaling and call invitations work.

The backend can issue short-lived TURN credentials using the Coturn REST shared
secret mechanism. To enable it:

1. Provision a public TURN service, such as Coturn, with UDP port 3478 reachable
   and `use-auth-secret` plus `static-auth-secret` configured. Use the same
   secret value in Coturn and Google Secret Manager. TURN over TLS/TCP is also
   recommended for networks that block UDP.
2. Store that shared secret in Secret Manager as `voice-turn-shared-secret`.
   The Europe deployment script grants the Cloud Run runtime account access to
   this secret when TURN is enabled.
3. Deploy with `VOICE_TURN_URLS` set to the TURN URL or comma-separated URLs:

   ```sh
   cd backend
   VOICE_TURN_URLS='turn:turn.example.com:3478?transport=udp,turns:turn.example.com:5349?transport=tcp' \
     ./deploy-europe-west1.sh
   ```

The backend returns expiring credentials with the signaling-ready event, so
the shared secret is never sent to mobile clients. Credentials expire after an
hour by default; set `VOICE_TURN_CREDENTIAL_TTL_SECONDS` to change that.
