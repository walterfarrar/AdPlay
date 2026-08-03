# Partner approval (rewarded video only)

AdPlay has **no offerwall**. Monetization is opt-in **rewarded video** (Longer / Faster / Stronger boosts only). Sats come from gameplay; users redeem via Lightning.

## Who we use

| Priority | Provider | Role | Status |
|---|---|---|---|
| **1st (waterfall)** | **[AdMob](https://admob.google.com/)** | Native rewarded via Google Mobile Ads SDK. Mediation-ready (standard ad units, partner bidding off). | Live in client — policy risk at release |
| **2nd (waterfall)** | **[AdsBitvex](https://adsbitvex.com/)** | WebView JS reward ads if AdMob no-fills / fails / bans | Live fallback |
| Fallback | **Mock** | Dev only if `adProvider=mock` | Available |
| **Deferred** | **[Unity Ads](https://unity.com/products/unity-ads)** | Native rewarded (good fill once live) | **Not yet eligible** — see below |
| **Next outreach** | **[Monetag](https://monetag.com/in-app/)** | Extra independent rung (Android in-app / APK friendly) | Pending written OK |
| **Later outreach** | Mintegral, Pangle, BIGO Ads, Chartboost, Liftoff | Direct SDK *or* AdMob Mediation adapters | Ask crypto policy first |
| **Not used** | BitLabs, AdGate, AyeT, PubScale, Torox | Offerwall / surveys / CPA walls | Do not apply |
| **Avoid as primary** | AppLovin MAX | Same crypto cash-out risk class as AdMob | Only if they explicitly OK |

**Decision:** Clients use `adProvider=waterfall`: **AdMob → AdsBitvex**. Add more client rungs after written OK. While AdMob remains approved, prefer **AdMob Mediation** (Pangle / Mintegral / BIGO / etc. as adapters) so one SDK pulls more demand.

### Unity Ads — deferred, not rejected

Unity SMB support (Vaiva), paraphrased:

- App must be **published** on App Store or Google Play
- **≥ 3.5★** average rating
- **≥ 50 reviews**

Re-apply once those are met. Until then: do not block release on Unity; keep a calendar reminder post-launch.

### AdMob IDs

| | iOS | Android |
|---|---|---|
| App ID | `ca-app-pub-1524015618608684~3874360461` | `ca-app-pub-1524015618608684~9712547486` |
| Rewarded ad unit | `ca-app-pub-1524015618608684/6403169508` | `ca-app-pub-1524015618608684/6292177229` |

Partner bidding checkbox: **leave unchecked** (standard unit) so AdMob Mediation / waterfall remains available. Debug builds use Google sample rewarded units; Release / TestFlight always use the production units above.

## If AdMob bans us — independent fallbacks

AdMob Mediation dies with the AdMob account. Plan independent rungs:

| Rank | Network | Why | Notes |
|---|---|---|---|
| 1 | **AdsBitvex** | Already wired | Thin fill risk — don’t rely alone |
| 2 | **Monetag** | Explicit in-app / APK monetization; crypto-adjacent traffic common | Confirm rewarded (not only smartlinks) + Lightning OK |
| 3 | **Unity Ads** | Strong rewarded demand | Unlock after store rating/review gate |
| 4 | **Mintegral / Pangle / BIGO / Chartboost / Liftoff** | Real rewarded SDKs, mediation-friendly | Email policy template below; integrate winners as waterfall rungs or via a non-Google mediation later |
| — | **AppLovin MAX** | Excellent fill | High chance of same “no crypto cash-out” stance — only if they say yes in writing |

Telegram-only nets (AdsGram, Monetag TMA tags) are **not** a fit for native iOS/Android AdPlay.

## Ask them (copy/paste)

Subject: Publisher inquiry — iOS/Android rewarded video app with Lightning BTC redemption

Hi,

We’re building **AdPlay**, an iOS (primary) / Android app with optional rewarded video only — **no offerwall**.

Gameplay:
- Manual taps (daily UTC cap) fill a progress bar.
- Optional rewarded video placements grant **in-game boosts only** (Longer / Faster / Stronger).
- When the bar completes, our server credits **1 sat**. Users redeem by pasting a Lightning invoice; we pay manually (Speed wallet).

Questions:
1. Do your publisher terms allow users to redeem earnings as **Bitcoin via Lightning**?
2. May we use rewarded video whose in-app reward is **earn-rate boosts** (not direct cash), while sats come from gameplay?
3. Do you support **server-to-server** completion callbacks with a stable event id for idempotency?
4. iOS / Android SDK availability, geo / age / frequency caps we must enforce?

Thanks,

## Until approved

- Debug only: Skip ads bypass when `DEBUG_BYPASS_ADS` is compiled in; Reset when server `DEBUG_RESET=1`.
- Release / TestFlight: live waterfall (AdMob → AdsBitvex), production AdMob units, no Skip ads / Reset. Policy risk on AdMob remains; AdsBitvex covers fill if Google restricts the account.

## When adding another waterfall rung

1. Get written OK if the network cares about Lightning/BTC.
2. Keep keys in Firebase / env (never commit secrets).
3. Add an `AdServing` / `AdNetwork` implementation and insert it in `WaterfallAdService` order (iOS + Android).
4. Prefer partner S2S when available — never credit sats in the ad callback.
5. See [partner-sdk.md](./partner-sdk.md).
