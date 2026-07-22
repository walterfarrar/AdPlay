# Admin redeem emails (Gmail)

On each player redeem, Cloud Functions emails **admin@fullyversed.com** with amount, BOLT11, user id, ad/ledger stats, and one-click **Mark paid** / **Reject** / **Refund** links.

| Action | Effect |
|---|---|
| Mark paid | You paid the invoice; status → `paid` |
| Reject | Deny (fishy); held sats stay forfeited → `rejected` |
| Refund | Return held sats to the player → `refunded` (also works after Reject) |

## Secrets (Firebase)

Set once (PowerShell). Never commit these values.

```powershell
cd C:\git\AdPlay

# Generated ADMIN_TOKEN (also used to sign email action links)
# Prefer writing to a file with no trailing newline, then:
# npx firebase-tools@latest functions:secrets:set ADMIN_TOKEN --data-file .\admin-token.txt --project adplay-sats
$adminToken = "YOUR_TOKEN"
[IO.File]::WriteAllBytes("$PWD\admin-token.txt", [Text.Encoding]::UTF8.GetBytes($adminToken))
npx -y firebase-tools@latest functions:secrets:set ADMIN_TOKEN --project adplay-sats --data-file "$PWD\admin-token.txt"
Remove-Item "$PWD\admin-token.txt"

# Gmail account that SENDS the mail (must have 2FA + App Password)
"admin@fullyversed.com" | npx -y firebase-tools@latest functions:secrets:set GMAIL_USER --project adplay-sats

# Google Account → Security → App passwords → Mail
"YOUR_16_CHAR_APP_PASSWORD" | npx -y firebase-tools@latest functions:secrets:set GMAIL_APP_PASSWORD --project adplay-sats

npx -y firebase-tools@latest deploy --only functions --project adplay-sats
```

Optional override for the recipient (defaults to `admin@fullyversed.com`):

```powershell
# In Google Cloud Console → Cloud Functions → each function → Edit → Runtime env vars:
# ADMIN_NOTIFY_EMAIL=admin@fullyversed.com
```

## Seed tunables

After rotating `ADMIN_TOKEN`:

```powershell
Invoke-RestMethod -Method Post -Uri "https://us-central1-adplay-sats.cloudfunctions.net/seedTunables?token=YOUR_TOKEN"
```

## Email actions

Links hit `adminEmailAction` and are HMAC-signed (7-day expiry). They do not expose the raw admin token.

HTTP equivalents (header `x-admin-token`): `adminMarkPaid`, `adminReject`, `adminRefund`.
