# TestFlight / store submission checklist

## Before upload (iOS — needs a Mac)

1. Organization Apple Developer account (LLC + D‑U‑N‑S).
2. Confirm AdPlay store pages are deployed on FullyVersedWebsite (`/adplay`, `/adplay/privacy`, `/adplay/support`) — unlinked from main site nav/footer.
3. Set production API URL in the iOS build (`ADPLAY_API_URL`).
4. Generate Xcode project: `cd ios && xcodegen generate` (requires [XcodeGen](https://github.com/yonaskolb/XcodeGen)).
5. Enable Sign in with Apple on App ID `com.adplay.app`, regenerate the AdPlay provisioning profile, and enable Apple in Firebase Authentication. Settings → Sign in with Apple links the anonymous session.
6. Paste [ReviewNotes.md](./ReviewNotes.md) into App Review Notes; use the Privacy / Support / Marketing URLs listed there in App Store Connect.
7. Archive → Upload → TestFlight internal → external → App Review.

## Android local QA (current path)

Use [LDPLAYER.md](../LDPLAYER.md). Store listing submission is out of scope until partner + legal review.

## Account deletion

Settings → Delete account (with a confirmation) calls the `deleteAccount` Cloud Function: recursive Firestore wipe under `users/{uid}` plus `auth.deleteUser`. The client then signs in anonymously again.
