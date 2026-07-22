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
- Rewarded ads are optional and skippable via the partner UI.
- Boosts are applied only after server-to-server verification.
- Until a rewards partner is approved for crypto redemption, TestFlight builds use `AD_PROVIDER=mock` (simulated rewarded completion) so reviewers can exercise Longer/Faster without live ads.

## Backend for review
Provide a reachable API base URL in the build’s `ADPLAY_API_URL` (or default staging).  
Admin payout tooling is **not** exposed in the iOS binary.

## Age / content
- 17+ recommended (contests / advertising).
- No real-money gambling or slots.
- No get-rich claims in metadata.

## Privacy
Privacy policy URL: host `docs/app-store/privacy-policy.html` (or your production URL).  
Account deletion: contact support / in-app request (v1: wipe via backend user delete endpoint to be exposed before launch).
