# Codemagic — iOS (no Mac)

AdPlay’s Xcode project is generated with **XcodeGen** from `ios/project.yml` (`.xcodeproj` is gitignored).

Build numbers use Codemagic’s auto **`$PROJECT_BUILD_NUMBER`** (same pattern as Fully Versed / Prayer), via `agvtool` before the IPA build.

## One-time setup in Codemagic

1. Connect GitHub repo `walterfarrar/AdPlay`.
2. App Store Connect API integration named **`Codemagic`** (matches other apps).
3. Enable code signing for `com.adplay.app` (App Store distribution). The TestFlight job signs the IPA with the entitlements from that profile (including Sign in with Apple).
4. Ensure the workflow’s **build number** counter is on (Codemagic sets `PROJECT_BUILD_NUMBER`).
5. Run **iOS TestFlight Build**.

## 13-inch iPad screenshot (Simulator)

No Mac needed. This does **not** upload to TestFlight.

1. Codemagic → **Start new build** → workflow **iOS iPad screenshot**.
2. Wait for email / the build page.
3. Download `ipad-13-play.png` from **Artifacts**.
4. Upload it to App Store Connect → the version → **iPad 13" Display**.

The workflow boots an iPad Pro 13-inch simulator, builds a **signed Release** simulator app (so Skip ads / Reset are not in the shot and Firebase Auth can use the keychain), skips onboarding, suppresses permission sheets, waits until Play is ready, then captures. Auto tapper only appears if Auto is already running after launch; the listing shot is still the real SwiftUI UI.

If a run still shows a system alert or a keychain error, re-run **iOS iPad screenshot** — the capture is failed on purpose when Play never becomes ready.

## Local note

On a Mac: `cd ios && brew install xcodegen && xcodegen generate && open AdPlay.xcodeproj`
