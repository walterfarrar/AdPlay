# AdPlay

Idle progress bar → earn sats → redeem via Lightning invoice (manual payout).

**Primary local test target:** Android on **LDPlayer** (see [docs/LDPLAYER.md](docs/LDPLAYER.md)).  
iOS builds without a Mac: **Codemagic** + [docs/CODEMAGIC.md](docs/CODEMAGIC.md).  
iOS uses the same **Firebase Auth + Cloud Functions** backend as Android (`ios/` via XcodeGen).

## Quick start

### Backend (Firebase — `adplay-sats`)

Authoritative game state runs on **Firebase Auth + Firestore + Cloud Functions** (no LAN IP for LDPlayer).

1. Upgrade the project to **Blaze** (needed for Functions): https://console.firebase.google.com/project/adplay-sats/usage/details  
2. Enable **Anonymous** auth: https://console.firebase.google.com/project/adplay-sats/authentication/providers  
3. Deploy:

```powershell
cd C:\git\AdPlay
npx -y firebase-tools@latest deploy --only functions,firestore --project adplay-sats
Invoke-RestMethod -Method Post -Uri "https://us-central1-adplay-sats.cloudfunctions.net/seedTunables?token=YOUR_ADMIN_TOKEN"
```

Legacy local Node API remains under `server/` for reference.

### Android (LDPlayer)

```powershell
cd android
.\install-ldplayer.ps1
```

Details: **[docs/LDPLAYER.md](docs/LDPLAYER.md)**

### iOS (later, on a Mac)

```bash
cd ios && xcodegen generate && open AdPlay.xcodeproj
```

## Game loop

1. Tap the bar (daily UTC tap cap).
2. Watch **Longer** (extend auto-fill) or **Faster** (raise fill rate) — mock ads in dev.
3. Full bar → **+1 sat** (server-authoritative).
4. Redeem → paste BOLT11 → email to admin → pay Lightning → Mark paid in email.

## Docs

| Doc | Purpose |
|---|---|
| [docs/CODEMAGIC.md](docs/CODEMAGIC.md) | iOS CI / TestFlight via Codemagic |
| [docs/LDPLAYER.md](docs/LDPLAYER.md) | Run on LDPlayer |
| [docs/partner-outreach.md](docs/partner-outreach.md) | Ad partner email / checklist |
| [docs/partner-sdk.md](docs/partner-sdk.md) | Mock → real S2S ads |
| [docs/game-tunables.md](docs/game-tunables.md) | Economy knobs |
| [docs/admin-redeem-email.md](docs/admin-redeem-email.md) | Gmail notify + Mark paid secrets |
| [docs/app-store/](docs/app-store/) | Privacy, age rating, Review Notes |

## Note on AdMob

Do **not** use AdMob (or AppLovin / Unity LevelPlay / ironSource) for this product — crypto cash-out + rewarded ads. Use a crypto-friendly **rewarded video** network after written approval; see [docs/partner-outreach.md](docs/partner-outreach.md). No offerwall.
