# App Review Notes — AdPlay

## Demo account
Sign-in uses an anonymous device session (no password) for Android QA and early TestFlight.  
Optional: Sign in with Apple will be enabled for iOS production builds once the capability is configured.

## Local QA (Android / LDPlayer)
Primary development builds target Android. See `docs/LDPLAYER.md` for API URL / `adb reverse` setup.

## What the app does
AdPlay is an idle progress game:
1. Players tap a progress bar (limited taps per UTC day).
2. Optional rewarded ads grant **in-game boosts only**:
   - **Longer** — extends auto-fill duration
   - **Faster** — increases fill rate while auto-fill is active
3. When the bar fills, the server credits **1 sat** (Bitcoin subunit).
4. Players may request a redemption by pasting a **Lightning BOLT11 invoice**. An operator pays the invoice **manually** outside the app; Apple is not involved in the payment.

## Ads
- Rewarded ads are optional and skippable via the ad UI (AdMob, with AdsBitvex fallback).
- Boosts are applied only after our backend credits the completion (`mockCompleteBoost` / future S2S).
- Release / TestFlight builds use production AdMob units. There is no in-app Skip ads / Reset control in store builds.

## App Tracking Transparency
- The system ATT prompt appears **shortly after the home screen loads** (before AdMob initializes / preloads a rewarded ad), and again is ensured if the player taps a boost before that warm-up finishes.
- Usage string: “AdPlay uses this identifier to show relevant rewarded ads and measure ad performance.”
- To re-test on device: Settings → Privacy & Security → Tracking → enable Tracking, then delete and reinstall AdPlay (or reset the app’s tracking permission).

## Backend for review
Provide a reachable API base URL in the build’s `ADPLAY_API_URL` (or default staging).  
Admin payout tooling is **not** exposed in the iOS binary.

## Age / content
- 17+ recommended (contests / advertising).
- No real-money gambling or slots.
- No get-rich claims in metadata.

## Privacy / store URLs (hosted on fullyversed.com, unlinked from main site nav/footer)
- Privacy: https://fullyversed.com/adplay/privacy  
- Support: https://fullyversed.com/adplay/support  
- Marketing: https://fullyversed.com/adplay  
Account deletion: email support (see Support page) / in-app request when Settings ships.
