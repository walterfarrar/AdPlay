# Codemagic — iOS (no Mac)

AdPlay’s Xcode project is generated with **XcodeGen** from `ios/project.yml` (`.xcodeproj` is gitignored).

## One-time setup in Codemagic

1. Connect the GitHub repo `walterfarrar/AdPlay`.
2. Add an **App Store Connect API** key integration (name it e.g. `codemagic`).
3. Create an environment group (optional) for signing secrets per [Codemagic iOS signing](https://docs.codemagic.io/yaml-code-signing/signing-ios/).
4. Set workflow vars if needed:
   - `APP_STORE_APPLE_ID` — numeric App ID from App Store Connect → App Information
   - Apple Team ID in the signing / integration UI
5. Start the `ios-testflight` workflow (or push to `main` once triggering is enabled).

## Local note

On a Mac: `cd ios && brew install xcodegen && xcodegen generate && open AdPlay.xcodeproj`
