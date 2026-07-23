export type BoostType = "duration" | "speed" | "tap_strength" | "skip_time";
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
  adsPerCycle: number;
  /** Seconds of auto time / progress to skip per Skip Time ad. */
  skipTimeSeconds: number;
  /**
   * Max Skip Time ads per run after regular ads are exhausted.
   * 0 = unlimited.
   */
  skipAdsPerCycle: number;
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
  adsPerCycle: 30,
  skipTimeSeconds: 60,
  skipAdsPerCycle: 10,
  dailySatsEarnCap: 400,
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
  adsUsed: number;
  /** Skip Time ads used this run (reset when auto cycle refreshes). */
  skipAdsUsed: number;
  satsEarnedToday: number;
  satsDay: string;
  lastAdAt: string | null;
  lastTickAt: string;
  lastBoostType: BoostType | null;
  satsBalance: number;
};
export type PublicGameState = {
  progress: number;
  unitsPerSat: number;
  satsBalance: number;
  tapsRemaining: number;
  adsRemainingToday: number;
  /**
   * Skip Time ads left this run. -1 means unlimited (skipAdsPerCycle === 0).
   */
  skipAdsRemaining: number;
  satsEarnedToday: number;
  dailySatsEarnCap: number;
  autoFillActive: boolean;
  autoFillUntil: string | null;
  fillRate: number;
  speedBoostActive: boolean;
  speedBoostUntil: string | null;
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
