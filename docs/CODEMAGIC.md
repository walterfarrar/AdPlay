# Codemagic — iOS (no Mac)

AdPlay’s Xcode project is generated with **XcodeGen** from `ios/project.yml` (`.xcodeproj` is gitignored).

Build numbers use Codemagic’s auto **`$PROJECT_BUILD_NUMBER`** (same pattern as Fully Versed / Prayer), via `agvtool` before the IPA build.

## One-time setup in Codemagic

1. Connect GitHub repo `walterfarrar/AdPlay`.
2. App Store Connect API integration named **`Codemagic`** (matches other apps).
3. Enable code signing for `com.adplay.app` (App Store distribution).
4. Ensure the workflow’s **build number** counter is on (Codemagic sets `PROJECT_BUILD_NUMBER`).
5. Run **iOS TestFlight Build**.

## Local note

On a Mac: `cd ios && brew install xcodegen && xcodegen generate && open AdPlay.xcodeproj`
