# Partner approval (rewarded video only)

AdPlay has **no offerwall**. Monetization is opt-in **rewarded video** (Longer / Faster / Stronger boosts only). Sats come from gameplay; users redeem via Lightning.

## Who we use

| Priority | Provider | Role | Status |
|---|---|---|---|
| **Now** | **[AdsBitvex](https://adsbitvex.com/)** | WebView JS reward ads (`App ID 000241`). Client Promise → `mockCompleteBoost`. | **Wiring / testing** |
| Fallback | **Mock** | Dev only if `adProvider=mock` | Available |
| **2nd outreach** | **[Monetag](https://monetag.com/in-app/)** | Native Android if AdsBitvex fails | Pending |
| **Not used** | AdMob, AppLovin, Unity, ironSource | Ban / high risk for crypto cash-out apps | Do not apply |
| **Not used** | BitLabs, AdGate, AyeT, PubScale, Torox | Offerwall / surveys / CPA walls — out of scope | Do not apply |

**Decision:** Android uses AdsBitvex via WebView (`adProvider=adsbitvex`). Boosts still applied by our `mockCompleteBoost` after their Promise resolves (no partner S2S). Revisit Monetag if fill/quality is bad.

ZBD Earn (and similar) are **payout engines**, not ad networks — they don’t replace the video provider.

## Ask them (copy/paste)

Subject: Publisher inquiry — Android rewarded video app with Lightning BTC redemption

Hi,

We’re building **AdPlay**, an Android app (Play Store target) with optional rewarded video only — **no offerwall**.

Gameplay:
- Manual taps (daily UTC cap) fill a progress bar.
- Three optional rewarded video placements grant **in-game boosts only**:
  1. **Longer** — extends auto-fill duration
  2. **Faster** — increases fill rate
  3. **Stronger** — increases tap power
- When the bar completes, our server credits **1 sat**. Users redeem by pasting a Lightning invoice; we pay manually (Speed wallet).

Questions:
1. Do your publisher terms allow users to redeem earnings as **Bitcoin via Lightning**?
2. May we use rewarded video whose in-app reward is **earn-rate boosts** (not direct cash), while sats come from gameplay?
3. Do you support **server-to-server** completion callbacks with a stable event id for idempotency?
4. Android SDK availability, geo / age / frequency caps we must enforce?

Thanks,

## Until approved

Run with mock ads (Android “Watch (dev)” → `mockCompleteBoost`). Full game loop works without a live network.

## When approved

1. Get written OK; store keys in Firebase / env (never commit).
2. Set partner name in tunables / env (`AD_PROVIDER=adsbitvex` or `monetag`).
3. Android: replace `PartnerAdService` in `android/.../AdService.kt` with the SDK for three placement IDs.
4. Keep S2S (or partner callback → Cloud Function) as source of truth for boosts — never credit sats in the ad callback.
5. See [partner-sdk.md](./partner-sdk.md).
