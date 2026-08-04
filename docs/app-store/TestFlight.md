# TestFlight / store submission checklist

## Before upload (iOS — needs a Mac)

1. Organization Apple Developer account (LLC + D‑U‑N‑S).
2. Confirm AdPlay store pages are deployed on FullyVersedWebsite (`/adplay`, `/adplay/privacy`, `/adplay/support`) — unlinked from main site nav/footer.
3. Set production API URL in the iOS build (`ADPLAY_API_URL`).
4. Generate Xcode project: `cd ios && xcodegen generate` (requires [XcodeGen](https://github.com/yonaskolb/XcodeGen)).
5. Enable Sign in with Apple for production auth (optional for internal TestFlight using device sessions).
6. Paste [ReviewNotes.md](./ReviewNotes.md) into App Review Notes; use the Privacy / Support / Marketing URLs listed there in App Store Connect.
7. Archive → Upload → TestFlight internal → external → App Review.

## Android local QA (current path)

Use [LDPLAYER.md](../LDPLAYER.md). Store listing submission is out of scope until partner + legal review.

## Account deletion

`DELETE /account` (authenticated) removes the user, game state, and related rows. Expose in Settings before public launch.
