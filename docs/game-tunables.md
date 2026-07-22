# Game tunables

Source of truth: [`server/src/config/game.ts`](../server/src/config/game.ts)

| Param | Default | Role |
|---|---|---|
| `unitsPerSat` | 100 | Taps toward 1 sat (UI calls these “taps”) |
| `tapUnits` | 1 | Taps added per manual tap |
| `dailyTapCap` | 500 | Manual taps per UTC day |
| `resetHourUtc` | 0 (`RESET_HOUR_UTC`) | Daily counter reset hour |
| `baseFillRate` | 0 taps/s | No fill without a Faster/first-ad starter |
| `durationBoostSeconds` | 1200 | +20 minutes auto-fill |
| `speedBoostAmount` | 0.15 taps/s | Faster additive rate (stacks) |
| `speedBoostSeconds` | 1200 | Faster extends speed window by 20 min |
| `adCooldownSeconds` | 10 | Shared cooldown after any rewarded ad |
| `adsPerCycle` | 30 | Max ads while auto is running; refills when duration hits 0 |
| `dailySatsEarnCap` | 400 | Max sats from bars / UTC day |
| `minWithdrawSats` | 100 (`MIN_WITHDRAW_SATS`) | Min redeem request |

## First ad vs stacks

When idle (no auto time and no speed boost), the **first** Longer or Faster grants both:
- **+20 min** auto-fill
- **0.15 taps/s**

After that:

| Ad | Effect |
|---|---|
| **Longer** | +20 min (also extends speed window if rate is active) |
| **Faster** | +0.15 taps/s and +20 min on speed window |

| Example | Rate | Time |
|---|---|---|
| 1× Longer or Faster (from idle) | 0.15 | 20 min |
| +1 Longer | 0.15 | 40 min |
| +1 Faster | 0.30 | speed window +20 |

## Economy guardrail

Keep expected sats paid out per day **below** net ad/offer revenue after partner fees. Raise cooldown / lower fill rates before raising sats caps.
