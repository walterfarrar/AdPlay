export type BoostType =
  | "activate"
  | "duration"
  | "speed"
  | "tap_strength"
  | "skip_time";
export type Tunables = {
  unitsPerSat: number;
  tapUnits: number;
  dailyTapCap: number;
  resetHourUtc: number;
  baseFillRate: number;
  durationBoostSeconds: number;
  speedBoostAmount: number;
  speedBoostSeconds: number;
  /**
   * Additive tap power while Stronger is active (stacks). Applies to manual taps and
   * scales auto fill while the shared auto window is running (same clock as Longer/Faster).
   */
  tapStrengthBoostAmount: number;
  /** @deprecated Unused — Stronger uses the shared auto timer; kept for config compat */
  tapStrengthBoostSeconds: number;
  adCooldownSeconds: number;
  /** Max banked ad charges (burst pool). */
  adsPerCycle: number;
  /**
   * Seconds between +1 boost-ad / Skip charge while below max during an active run.
   * When the shared auto timer ends, both banks refill to max immediately.
   * 0 = no timed regen during a run.
   */
  adRegenSeconds: number;
  /** Seconds of auto time / progress to skip per Skip Time ad. */
  skipTimeSeconds: number;
  /**
   * Max Skip Time ads per run after regular ads are exhausted.
   * 0 = unlimited. -1 = disabled (Skip Time hidden / rejected).
   */
  skipAdsPerCycle: number;
  /** Max sats from bars per UTC day. 0 = unlimited. */
  dailySatsEarnCap: number;
  minWithdrawSats: number;
};
/** Defaults — also seeded to Firestore config/tunables (server-only writes). */
export const DEFAULT_TUNABLES: Tunables = {
  unitsPerSat: 1000,
  tapUnits: 1,
  dailyTapCap: 500,
  resetHourUtc: 0,
  baseFillRate: 0,
  durationBoostSeconds: 30 * 60,
  speedBoostAmount: 0.5,
  speedBoostSeconds: 20 * 60,
  tapStrengthBoostAmount: 0.25,
  tapStrengthBoostSeconds: 20 * 60,
  adCooldownSeconds: 10,
  adsPerCycle: 10,
  adRegenSeconds: 20 * 60,
  skipTimeSeconds: 60,
  skipAdsPerCycle: 10,
  dailySatsEarnCap: 0,
  minWithdrawSats: 100,
};
export type GameStateDoc = {
  progress: number;
  fillRate: number;
  autoFillUntil: string | null;
  speedBoostUntil: string | null;
  speedBoostAmount: number;
  tapStrengthBoostUntil: string | null;
  tapStrengthBoostAmount: number;
  tapsRemaining: number;
  tapDay: string;
  /** @deprecated Prefer adCharges; kept for mail / legacy migration. */
  adsUsed: number;
  /** Remaining watchable ad charges (0…adsPerCycle). */
  adCharges: number;
  /** Anchor for timed regen (ISO). */
  adChargesAt: string;
  /**
   * @deprecated Prefer skipAdCharges; kept for migration.
   * Skip Time ads used this run.
   */
  skipAdsUsed: number;
  /** Remaining Skip Time charges (0…skipAdsPerCycle). Unused when skipAdsPerCycle <= 0. */
  skipAdCharges: number;
  /** Anchor for Skip Time timed regen (ISO). */
  skipAdChargesAt: string;
  satsEarnedToday: number;
  satsDay: string;
  lastAdAt: string | null;
  lastTickAt: string;
  lastBoostType: BoostType | null;
  satsBalance: number;
  /** Times Longer was completed this auto cycle. */
  durationBoostCount: number;
  /** Times Faster was completed this auto cycle. */
  speedBoostCount: number;
  /** Times Stronger was completed this auto cycle. */
  tapStrengthBoostCount: number;
};
export type PublicGameState = {
  progress: number;
  unitsPerSat: number;
  satsBalance: number;
  tapsRemaining: number;
  /** Banked ad charges remaining. */
  adsRemainingToday: number;
  /** Seconds until the next regenerated charge. 0 if full or regen disabled. */
  adRegenSecondsLeft: number;
  /** ISO when the next charge lands; null if full / no regen. */
  nextAdChargeAt: string | null;
  /**
   * Skip Time ads left this run.
   * -1 = unlimited (skipAdsPerCycle === 0). 0 with skipAdsPerCycle < 0 = disabled.
   */
  skipAdsRemaining: number;
  /** Seconds until the next regenerated Skip charge. 0 if full / unlimited / no regen. */
  skipAdRegenSecondsLeft: number;
  /** ISO when the next Skip charge lands; null if full / unlimited / no regen. */
  nextSkipAdChargeAt: string | null;
  satsEarnedToday: number;
  dailySatsEarnCap: number;
  autoFillActive: boolean;
  autoFillUntil: string | null;
  fillRate: number;
  /** True only after the player watched a Faster ad this cycle (not starter rate from Longer/Stronger). */
  speedBoostActive: boolean;
  speedBoostUntil: string | null;
  /** True only after the player watched a Longer ad this cycle. */
  durationBoostActive: boolean;
  /** Longer ads completed this run (0 while idle / after Activate before first Longer). */
  durationBoostCount: number;
  /** Faster ads completed this run. */
  speedBoostCount: number;
  /** Stronger ads completed this run. */
  tapStrengthBoostCount: number;
  tapStrengthActive: boolean;
  tapStrengthUntil: string | null;
  /** Effective progress units per tap right now (also scales auto fill). */
  tapPower: number;
  adCooldownSecondsLeft: number;
  lastBoostType: BoostType | null;
  minWithdrawSats: number;
  resetHourUtc: number;
  /** ISO timestamp of last authoritative state write — clients use this to drop stale polls. */
  updatedAt: string;
};
