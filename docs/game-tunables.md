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
| `baseAdsPerCycle` | **5** | Starting ad-hold size |
| `dailyGoalBonusAdsMax` | 5 | Max extra hold from today’s daily goals |
| `dailyGoalTapTarget` | 50 | Taps to complete the tap goal |
| `dailyGoalAdTarget` | 3 | Boost ads to complete the ad goal |
| `dailyGoalSatsTarget` | 1 | Sats to complete the earn goal |
| `dailyGoalTapStretchTarget` | 200 | Second tap goal |
| `streakBonusAdsMax` | 5 | Max extra hold from login streak |
| `streakAdsEveryDays` | 1 | Streak days per +1 hold |
| `achievementBonusAdsMax` | 3 | Max extra hold from slot achievements |
| `iapBonusAdsMax` | 5 | Max extra hold from IAP |
| `maxAdsPerCycle` | **23** | Safety rail (5+5+5+3+5). Does not drop earned slots |
| `adsPerCycle` | computed | Effective hold returned to clients |
| `adRegenSeconds` | **1200** | Seconds between +1 charge (20 min). **0 = no regen** |
| `skipTimeSeconds` | 60 | Skip Time: seconds of auto to skip |
| `skipAdsPerCycle` | 10 | Skip ads after charges empty; **0 = unlimited**, **-1 = disabled** |
| `dailySatsEarnCap` | 0 | Max sats/day; **0 = unlimited** |
| `minWithdrawSats` | 100 | Min redeem request |
| `comboTapsPerLevel` | 100 | **int** — manual taps to fill one outermost (ring 0) cycle |
| `comboStep` | 0.1 | **double** — added each non-overflow completion (1.0 → 1.1 → …) |
| `comboMax` | 2.0 | **double** — legacy single-ring cap; nested engine ignores this |
| `comboBase` | 1.0 | **double** — multiplier with empty rings |
| `comboAbsMax` | 3.0 | **double** — hard cap on `comboMultiplier` (add in console; code default 3.0) |
| `comboRing0Max` | 1.0 | **double** — max contribution from outermost ring before overflow |
| `comboRing1Max` | 1.0 | **double** — max contribution from inner ring before overflow |
| `comboRing2Max` | 1.0 | **double** — max contribution from innermost ring before overflow |
| `comboIdleGraceSeconds` | 1.5 | **double** — after this with no tap, idle drain starts |
| `comboDrainPerSecondActive` | 0.002 | **double** — slow drain of the current meter while still tapping |
| `comboDrainPerSecondIdle` | 0.5 | **double** — faster LIFO drain after the grace window |

Manual combo applies only to **live taps at the wheel**. It does **not** apply to Auto Tapper, Skip Time, or offline catch-up. Effective live tap units = `tapPower × comboMultiplier`. Auto fill rate stays `taps/s × tapPower` (Stronger only).

Three concentric rings (outer → inner → core). Each time a ring completes a loop it adds `comboStep` (then overflow) **and** fills the next inner ring by `1 / (ringMax / step)` (10% if max 1.0 and step 0.1). After the first outer complete, ring 1 is visible at ~10%; after ~10 outer completes, ring 1 is full. Overflow steps are derived (`comboStep / 10 / 100 / 1000`). New keys work via `getState` merge **before** you add them in the console (code defaults).

Player-doc combo fields (not tunables): `comboMeter` / `comboLevel` / `comboContrib` (ring 0, backward compatible), plus `comboMeter1` / `comboLevel1` / `comboContrib1` and `comboMeter2` / `comboLevel2` / `comboContrib2`. Old docs with only ring 0 are treated as ring 0 only.

## Ad currency (hold bank)

`effective = base + dailyBonus + streakBonus + achievementBonus + iapBonus`  
clamped only by `maxAdsPerCycle` (default 23, the sum of the source caps).

- New players start with `baseAdsPerCycle` charges.
- Watching Longer / Faster / Stronger spends **1 charge**. Activate does not.
- Daily goals add hold **for that UTC day only**.
- Login streak adds hold **while the streak is alive**.
- Slot achievements and IAP add hold **permanently**.
- If effective max rises (daily goal, streak, achievement, IAP), that many charges are granted immediately so they can be used without waiting on regen.
- If effective max falls, current charges clamp down.
- While below max, +1 charge every `adRegenSeconds`.
- Skip Time only when charges are **0** and auto is still running.

## First ad vs stacks

When idle, **Activate** starts the shared auto window. Longer / Faster / Stronger then spend from the hold bank.

## Economy guardrail

Balance for a max of **23** stacked holds. Throttle via the source caps, `adRegenSeconds`, boost sizes, and cooldown. Keep expected sats paid out **below** net ad revenue.
