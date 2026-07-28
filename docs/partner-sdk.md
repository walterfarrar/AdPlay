# Partner SDK integration (Longer / Faster / Stronger)

## Current

- Cloud Functions / tunables expose `adProvider` (default **`waterfall`**).
- Clients:
  1. **AdMob** rewarded (native SDK)
  2. **AdsBitvex** WebView if AdMob fails to load/present
  3. On reward earned → `mockCompleteBoost` (same boost rules as S2S)
- `adProvider=mock` skips live ads (delay + server credit). Debug bypass does the same when enabled.

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

Never credit sats in the ad callback — only apply boosts.

## Waterfall / AdMob

1. iOS App ID + rewarded unit: see [partner-outreach.md](./partner-outreach.md).
2. Leave AdMob **Partner bidding** unchecked so units stay usable in AdMob Mediation.
3. Android: create an AdMob Android app and replace sample IDs in `android/app/build.gradle.kts`.
4. Add mediation ad sources in the AdMob console later; no client change required for AdMob-hosted mediation.
5. To force a single network: set `adProvider` to `admob` or `adsbitvex`.

## Adding another client-side rung

1. Implement `AdServing` (iOS + Android).
2. Insert into `WaterfallAdService` order.
3. Prefer partner S2S when available; keep `mockCompleteBoost` only until then.
