# LDPlayer testing guide

Primary local test path for AdPlay (no Mac required).

## Backend: Firebase

Game state lives in **Firebase** project `adplay-sats` (Auth + Firestore + Cloud Functions).
The Android app talks to Firebase over HTTPS — **no LAN IP / local Node server** required for playtesting.

### One-time setup

1. **Blaze billing** on [adplay-sats](https://console.firebase.google.com/project/adplay-sats/usage/details) (required for Cloud Functions).
2. Enable **Anonymous** sign-in: [Authentication → Sign-in method](https://console.firebase.google.com/project/adplay-sats/authentication/providers).
3. Deploy functions + seed tunables:

```powershell
cd C:\git\AdPlay
npx -y firebase-tools@latest deploy --only functions,firestore --project adplay-sats
# After deploy, seed tunables (use your ADMIN_TOKEN secret — see docs/admin-redeem-email.md):
Invoke-RestMethod -Method Post -Uri "https://us-central1-adplay-sats.cloudfunctions.net/seedTunables?token=YOUR_ADMIN_TOKEN"
```

Redeem emails: **[docs/admin-redeem-email.md](admin-redeem-email.md)**

Firestore rules deny client writes to balances/tunables; mutations go through callables.

## Build and install to LDPlayer

1. Start LDPlayer and confirm ADB sees it.
2. From PowerShell:

```powershell
cd C:\git\AdPlay\android
.\install-ldplayer.ps1
```

Or manually:

```powershell
cd C:\git\AdPlay\android
.\gradlew.bat assembleDebug
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $adb install -r .\app\build\outputs\apk\debug\app-debug.apk
```

## Legacy local Node API (optional)

The `server/` folder still has the old Fastify + SQLite stack for reference. Prefer Firebase for LDPlayer and any shared testing.

Admin payouts: HTTP endpoints on the deployed functions (`adminListWithdrawals`, `adminMarkPaid`, `adminReject`) with header `x-admin-token`.

