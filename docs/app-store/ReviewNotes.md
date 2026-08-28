# App Review Notes — AdPlay

## Demo account
Sign-in starts as an anonymous device session (no password). On iOS, Settings → Save progress with Apple links that session so a new phone can restore it. First launch is never behind a login wall.

## Local QA (Android / LDPlayer)
Primary development builds target Android. See `docs/LDPLAYER.md` for API URL / `adb reverse` setup.

## What the app does
AdPlay is an idle progress game with Play, Daily Goals, Store, and Redeem:
1. First-run onboarding explains tap, ad hold, boosts, and Lightning redeem.
2. Players tap a progress wheel (limited taps per UTC day).
3. Optional rewarded ads grant **in-game boosts only** (Activate, Longer, Faster, Stronger, Skip Time).
4. When the wheel fills, the server credits **1 sat** (Bitcoin subunit).
5. Daily Goals tracks login streak and UTC daily goals. A trophy on Play opens achievements. Completing those can raise how many boost ads the player can hold (ad currency). Extra ad-hold slots may be purchased via IAP on Store; that expands the rewarded-ad bank only — it does **not** buy Bitcoin or sats. Settings is a gear on Play.
6. Players may request a redemption on the Redeem tab by pasting a **Lightning BOLT11 invoice**. An operator pays the invoice **manually** outside the app; Apple is not involved in the payment.

## iPad
- The app is a universal iPhone + iPad target.
- Play uses the same stacked layout as iPhone, scaled to fill the iPad window. It scrolls if a short landscape window would otherwise crop controls.
- Please review on iPad Air 11-inch in portrait and landscape.

## Ads
- Rewarded ads are optional and skippable via the ad UI (AdMob, with AdsBitvex fallback).
- Boosts are applied only after our backend credits the completion (`mockCompleteBoost` / future S2S).
- Release / TestFlight builds use production AdMob units. There is no in-app Skip ads / Reset control in store builds.
- IAP product `com.adplay.app.adslot` adds +1 permanent ad-hold slot (max 5). It does not credit sats or Bitcoin. If the product is not yet live in App Store Connect, the Store buy button reports that purchases are unavailable. Store includes **Restore purchases**, which syncs the Apple ID and re-credits existing `com.adplay.app.adslot` transactions (idempotent on the server).

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
Account deletion: Settings → Delete account → confirm. Wipes the anonymous Firebase session and game data; a new empty session starts on-device.
