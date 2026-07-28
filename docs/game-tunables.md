# Game tunables

Source of truth (defaults): [`functions/src/types.ts`](../functions/src/types.ts) `DEFAULT_TUNABLES`  
Live values: Firestore `config/tunables`

| Param | Default | Role |
|---|---|---|
| `unitsPerSat` | 1000 | Progress units toward 1 sat |
| `tapUnits` | 1 | Progress per manual tap |
| `dailyTapCap` | 500 | Manual taps per UTC day |
| `resetHourUtc` | 0 | Daily counter reset hour |
| `baseFillRate` | 0 | No fill without a boost starter |
| `durationBoostSeconds` | 1800 | Longer: +auto seconds |
| `speedBoostAmount` | 0.5 | Faster: additive taps/s |
| `tapStrengthBoostAmount` | 0.25 | Stronger: additive tap power |
| `adCooldownSeconds` | 10 | Short anti-spam between watches |
| `adsPerCycle` | **10** | Max **banked** ad charges |
| `adRegenSeconds` | **1200** | Seconds between +1 charge (20 min). **0 = no regen** |
| `skipTimeSeconds` | 60 | Skip Time: seconds of auto to skip |
| `skipAdsPerCycle` | 10 | Skip ads after charges empty; 0 = unlimited |
| `dailySatsEarnCap` | 0 | Max sats/day; **0 = unlimited** |
| `minWithdrawSats` | 100 | Min redeem request |

## Ad charge bank

- New players start with a full bank (`adsPerCycle` charges).
- Watching Longer / Faster / Stronger spends **1 charge**.
- Charges **do not** refill when auto ends.
- While below max, +1 charge every `adRegenSeconds` (always, including idle).
- Skip Time only when charges are **0** and auto is still running.
- Skip Time also advances the **ad regen** clock by `skipTimeSeconds` (same as auto skip).

## First ad vs stacks

When idle, the **first** Longer / Faster / Stronger starts the shared auto window + base Faster rate. Button “active” state lights only after that boost type was watched this cycle.

## Economy guardrail

Throttle via `adsPerCycle`, `adRegenSeconds`, boost sizes, and cooldown. Keep expected sats paid out **below** net ad revenue.
