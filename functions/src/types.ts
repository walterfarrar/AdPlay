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
  /**
   * @deprecated Computed per player as effective ads max. Kept so older clients
   * still read tunables.adsPerCycle. New configs should set baseAdsPerCycle.
   */
  adsPerCycle: number;
  /** Starting hold size for every player. */
  baseAdsPerCycle: number;
  /** Extra hold from completed daily goals today (cap). */
  dailyGoalBonusAdsMax: number;
  dailyGoalTapTarget: number;
  dailyGoalAdTarget: number;
  dailyGoalSatsTarget: number;
  dailyGoalTapStretchTarget: number;
  /** Extra hold from login streak (cap). */
  streakBonusAdsMax: number;
  /** @deprecated Streak holds are milestone days 1/3/5/7/30. Kept for config compat. */
  streakAdsEveryDays: number;
  /** Extra hold from slot-granting achievements (cap). */
  achievementBonusAdsMax: number;
  /** Extra hold from IAP (cap). */
  iapBonusAdsMax: number;
  /** Safety rail — default equals 5+5+5+5+5. Must not drop earned slots. */
  maxAdsPerCycle: number;
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
  /** Taps to fill one outermost combo cycle. */
  comboTapsPerLevel: number;
  /** Multiplier added each outer-ring complete. */
  comboStep: number;
  /**
   * Legacy single-ring cap. Ignored by the odometer engine (uses comboAbsMax).
   * Kept so existing Firestore docs still merge cleanly.
   */
  comboMax: number;
  /** Combo multiplier with empty rings. */
  comboBase: number;
  /** Hard cap on comboMultiplier (base + nested ring contributions). */
  comboAbsMax: number;
  /** Ring 1 capacity as contribution max (levels = max / step). */
  comboRing0Max: number;
  comboRing1Max: number;
  comboRing2Max: number;
  /** Seconds after the last tap before idle drain. */
  comboIdleGraceSeconds: number;
  /** Unused. Kept so existing Firestore docs still merge. */
  comboDrainPerSecondActive: number;
  /** Outer-ring units drained per second after the grace window. */
  comboDrainPerSecondIdle: number;
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
  adsPerCycle: 5,
  baseAdsPerCycle: 5,
  dailyGoalBonusAdsMax: 5,
  dailyGoalTapTarget: 50,
  dailyGoalAdTarget: 3,
  dailyGoalSatsTarget: 1,
  dailyGoalTapStretchTarget: 200,
  streakBonusAdsMax: 5,
  streakAdsEveryDays: 1,
  achievementBonusAdsMax: 5,
  iapBonusAdsMax: 5,
  maxAdsPerCycle: 25,
  adRegenSeconds: 20 * 60,
  skipTimeSeconds: 60,
  skipAdsPerCycle: 10,
  dailySatsEarnCap: 0,
  minWithdrawSats: 100,
  comboTapsPerLevel: 100,
  comboStep: 0.1,
  comboMax: 2.0,
  comboBase: 1.0,
  comboAbsMax: 3.0,
  comboRing0Max: 1.0,
  comboRing1Max: 1.0,
  comboRing2Max: 1.0,
  comboIdleGraceSeconds: 1.5,
  comboDrainPerSecondActive: 0.002,
  comboDrainPerSecondIdle: 0.5,
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
  loginDay: string;
  loginStreak: number;
  bestLoginStreak: number;
  iapAdsPurchased: number;
  unlockedAchievements: string[];
  lifetimeSatsEarned: number;
  adsWatchedDay: string;
  adsWatchedToday: number;
  hasActivatedAuto: boolean;
  hasActivatedToday: boolean;
  hasPaidRedeem: boolean;
  /** Last applied hold max; used to grant charges when the max grows. */
  adsHoldMax?: number;
  /** Source of truth: live-tap combo counter (fractional while draining). */
  comboTaps?: number;
  /** Ring 0 fill 0–1, captured at last manual tap. */
  comboMeter: number;
  /** Completed outer (ring 0) cycles. */
  comboLevel: number;
  /** Derived bonus written for old readers (ring 0 only). */
  comboContrib: number;
  /** Ring 1 fill 0–1. */
  comboMeter1: number;
  comboLevel1: number;
  comboContrib1: number;
  /** Ring 2 fill 0–1. */
  comboMeter2: number;
  comboLevel2: number;
  comboContrib2: number;
  /** ISO of last manual tap; null if the player has never tapped. */
  lastManualTapAt: string | null;
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
  /** Tap counter at last tap (clients drain locally for display). */
  comboTaps: number;
  /** Ring 0 fill 0–1 at last tap (clients drain locally for display). */
  comboMeter: number;
  comboLevel: number;
  comboContrib: number;
  comboMeter1: number;
  comboLevel1: number;
  comboContrib1: number;
  comboMeter2: number;
  comboLevel2: number;
  comboContrib2: number;
  lastManualTapAt: string | null;
  /** Combo multiplier drained to now (manual taps only; stacks with Stronger). */
  comboMultiplier: number;
  adCooldownSecondsLeft: number;
  lastBoostType: BoostType | null;
  minWithdrawSats: number;
  resetHourUtc: number;
  /** ISO timestamp of last authoritative state write — clients use this to drop stale polls. */
  updatedAt: string;
};

export type AdBankBreakdown = {
  base: number;
  dailyBonus: number;
  streakBonus: number;
  achievementBonus: number;
  iapBonus: number;
  max: number;
};

export type DailyGoalPublic = {
  id: string;
  title: string;
  current: number;
  target: number;
  completed: boolean;
  rewardAds: number;
};

export type AchievementPublic = {
  id: string;
  title: string;
  detail: string;
  unlocked: boolean;
  grantsSlot: boolean;
};

export type PlayerProgress = {
  adBank: AdBankBreakdown;
  loginStreak: number;
  bestLoginStreak: number;
  dailyGoals: DailyGoalPublic[];
  achievements: AchievementPublic[];
  iapAdsPurchased: number;
  iapBonusAdsMax: number;
  lifetimeSatsEarned: number;
};
