# Partner SDK integration (Longer / Faster)

## Current (dev)

- Server: `AD_PROVIDER=mock` (default)
- Clients call `POST /ads/mock/complete` with `{ "boostType": "duration" | "speed" }`
- Boosts applied server-side with the same rules as production S2S (cooldown, daily cap, idempotent event ids)

## Production S2S contract

`POST /ads/s2s`

```json
{
  "userId": "<adplay user id>",
  "boostType": "duration",
  "eventId": "<partner unique id>",
  "ts": 1710000000000,
  "sig": "<hmac sha256 hex>"
}
```

Signature payload: `{userId}:{boostType}:{eventId}:{ts}`  
HMAC secret: `AD_S2S_SECRET`

Never credit sats in the ad callback — only apply Longer/Faster boosts.

## Wiring a real partner

1. Complete [partner-outreach.md](./partner-outreach.md) and get written OK for Lightning/BTC (AdsBitvex or Monetag).
2. Set `AD_PROVIDER` to the partner name; store API keys in env (never in the app binary beyond what’s required).
3. Android: replace `PartnerAdService` in `android/.../AdService.kt` with SDK show for placement IDs (`duration`, `speed`, `tap_strength`).
4. iOS: same for `PartnerAdService` in `ios/AdPlay/Services/AdService.swift` when you ship iOS.
5. On client reward callback, refresh game state until boost timers update from the server.
