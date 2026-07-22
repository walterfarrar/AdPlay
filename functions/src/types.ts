export type BoostType = "duration" | "speed" | "tap_strength";
export type Tunables = {
  unitsPerSat: number;
  tapUnits: number;
  dailyTapCap: number;
  resetHourUtc: number;
  baseFillRate: number;
  durationBoostSeconds: number;
  speedBoostAmount: number;
  speedBoostSeconds: number;
  /** Additive units per manual tap while tap-strength boost is active (stacks). */
  tapStrengthBoostAmount: number;
  tapStrengthBoostSeconds: number;
  adCooldownSeconds: number;
  adsPerCycle: number;
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
  tapStrengthBoostAmount: 1,
  tapStrengthBoostSeconds: 20 * 60,
  adCooldownSeconds: 10,
  adsPerCycle: 30,
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
  satsEarnedToday: number;
  dailySatsEarnCap: number;
  autoFillActive: boolean;
  autoFillUntil: string | null;
  fillRate: number;
  speedBoostActive: boolean;
  speedBoostUntil: string | null;
  tapStrengthActive: boolean;
  tapStrengthUntil: string | null;
  /** Effective progress units per manual tap right now. */
  tapPower: number;
  adCooldownSecondsLeft: number;
  lastBoostType: BoostType | null;
  minWithdrawSats: number;
  resetHourUtc: number;
  /** ISO timestamp of last authoritative state write — clients use this to drop stale polls. */
  updatedAt: string;
};
