import type {
  AchievementPublic,
  AdBankBreakdown,
  DailyGoalPublic,
  GameStateDoc,
  PlayerProgress,
  Tunables,
} from "./types";
import { utcDayKey } from "./util";

export const SLOT_ACHIEVEMENTS = [
  "first_sat",
  "first_auto",
  "first_redeem",
  "streak_7",
  "streak_30",
] as const;

const ACHIEVEMENT_META: Record<
  string,
  { title: string; detail: string; grantsSlot: boolean }
> = {
  first_sat: {
    title: "First sat",
    detail: "Fill the wheel and earn your first sat.",
    grantsSlot: true,
  },
  first_auto: {
    title: "Auto Tapper",
    detail: "Start Auto Tapper for the first time.",
    grantsSlot: true,
  },
  first_redeem: {
    title: "First payout",
    detail: "A Lightning redeem is marked paid.",
    grantsSlot: true,
  },
  streak_7: {
    title: "Week streak",
    detail: "Log in 7 days in a row.",
    grantsSlot: true,
  },
  streak_30: {
    title: "Month streak",
    detail: "Log in 30 days in a row.",
    grantsSlot: true,
  },
  lifetime_10: {
    title: "10 sats",
    detail: "Earn 10 sats over your lifetime.",
    grantsSlot: false,
  },
  lifetime_100: {
    title: "100 sats",
    detail: "Earn 100 sats over your lifetime.",
    grantsSlot: false,
  },
};

export function previousUtcDayKey(resetHourUtc: number, day: string): string {
  const [y, m, d] = day.split("-").map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  dt.setUTCDate(dt.getUTCDate() - 1);
  return utcDayKey(resetHourUtc, new Date(dt.getTime() + resetHourUtc * 3600_000));
}

export function ensureProgressFields(g: GameStateDoc, t: Tunables, now: Date): void {
  const day = utcDayKey(t.resetHourUtc, now);
  if (g.loginDay === undefined) g.loginDay = "";
  if (typeof g.loginStreak !== "number") g.loginStreak = 0;
  if (typeof g.bestLoginStreak !== "number") g.bestLoginStreak = g.loginStreak;
  if (typeof g.iapAdsPurchased !== "number") g.iapAdsPurchased = 0;
  if (!Array.isArray(g.unlockedAchievements)) g.unlockedAchievements = [];
  if (typeof g.lifetimeSatsEarned !== "number") {
    g.lifetimeSatsEarned = Math.max(0, g.satsBalance || 0);
  }
  if (g.adsWatchedDay === undefined) g.adsWatchedDay = day;
  if (typeof g.adsWatchedToday !== "number") g.adsWatchedToday = 0;
  if (typeof g.hasActivatedAuto !== "boolean") g.hasActivatedAuto = false;
  if (typeof g.hasActivatedToday !== "boolean") g.hasActivatedToday = false;
  if (typeof g.hasPaidRedeem !== "boolean") g.hasPaidRedeem = false;
}

export function updateLoginStreak(g: GameStateDoc, t: Tunables, now: Date): void {
  const day = utcDayKey(t.resetHourUtc, now);
  if (g.loginDay === day) return;
  if (g.loginDay && g.loginDay === previousUtcDayKey(t.resetHourUtc, day)) {
    g.loginStreak = (g.loginStreak || 0) + 1;
  } else {
    g.loginStreak = 1;
  }
  g.loginDay = day;
  g.bestLoginStreak = Math.max(g.bestLoginStreak || 0, g.loginStreak);
}

export function resetDailyProgress(g: GameStateDoc, t: Tunables, now: Date): void {
  const day = utcDayKey(t.resetHourUtc, now);
  if (g.adsWatchedDay !== day) {
    g.adsWatchedDay = day;
    g.adsWatchedToday = 0;
    g.hasActivatedToday = false;
  }
}

export function recordBoostAdWatch(g: GameStateDoc, t: Tunables, now: Date): void {
  resetDailyProgress(g, t, now);
  g.adsWatchedToday = (g.adsWatchedToday || 0) + 1;
}

export function recordAutoActivated(g: GameStateDoc, t: Tunables, now: Date): void {
  resetDailyProgress(g, t, now);
  g.hasActivatedAuto = true;
  g.hasActivatedToday = true;
}

export function evaluateAchievements(g: GameStateDoc): void {
  const unlocked = new Set(g.unlockedAchievements || []);
  if ((g.lifetimeSatsEarned || 0) >= 1 || (g.satsBalance || 0) >= 1) {
    unlocked.add("first_sat");
  }
  if (g.hasActivatedAuto) unlocked.add("first_auto");
  if (g.hasPaidRedeem) unlocked.add("first_redeem");
  if ((g.loginStreak || 0) >= 7) unlocked.add("streak_7");
  if ((g.loginStreak || 0) >= 30) unlocked.add("streak_30");
  if ((g.lifetimeSatsEarned || 0) >= 10) unlocked.add("lifetime_10");
  if ((g.lifetimeSatsEarned || 0) >= 100) unlocked.add("lifetime_100");
  g.unlockedAchievements = [...unlocked];
}

function tapsUsedToday(g: GameStateDoc, t: Tunables): number {
  return Math.max(0, t.dailyTapCap - (g.tapsRemaining || 0));
}

export function dailyGoals(g: GameStateDoc, t: Tunables): DailyGoalPublic[] {
  const taps = tapsUsedToday(g, t);
  const ads = g.adsWatchedToday || 0;
  const sats = g.satsEarnedToday || 0;
  const auto = g.hasActivatedToday ? 1 : 0;
  return [
    goal("taps", "Use taps", taps, t.dailyGoalTapTarget),
    goal("ads", "Watch boost ads", ads, t.dailyGoalAdTarget),
    goal("sats", "Earn sats", sats, t.dailyGoalSatsTarget),
    goal("auto", "Start Auto Tapper", auto, 1),
    goal("taps_stretch", "Keep tapping", taps, t.dailyGoalTapStretchTarget),
  ];
}

function goal(
  id: string,
  title: string,
  current: number,
  target: number,
): DailyGoalPublic {
  const tgt = Math.max(1, target || 1);
  const cur = Math.max(0, current);
  return {
    id,
    title,
    current: cur,
    target: tgt,
    completed: cur >= tgt,
    rewardAds: 1,
  };
}

export function dailyBonus(g: GameStateDoc, t: Tunables): number {
  const done = dailyGoals(g, t).filter((x) => x.completed).length;
  return Math.min(t.dailyGoalBonusAdsMax, done);
}

export function streakBonus(g: GameStateDoc, t: Tunables): number {
  const every = Math.max(1, t.streakAdsEveryDays || 1);
  return Math.min(t.streakBonusAdsMax, Math.floor((g.loginStreak || 0) / every));
}

export function achievementBonus(g: GameStateDoc, t: Tunables): number {
  const unlocked = new Set(g.unlockedAchievements || []);
  let n = 0;
  for (const id of SLOT_ACHIEVEMENTS) {
    if (unlocked.has(id)) n += 1;
  }
  return Math.min(t.achievementBonusAdsMax, n);
}

export function iapBonus(g: GameStateDoc, t: Tunables): number {
  return Math.min(t.iapBonusAdsMax, Math.max(0, g.iapAdsPurchased || 0));
}

export function effectiveAdsPerCycle(g: GameStateDoc, t: Tunables): number {
  const raw =
    (t.baseAdsPerCycle || 0) +
    dailyBonus(g, t) +
    streakBonus(g, t) +
    achievementBonus(g, t) +
    iapBonus(g, t);
  const rail = t.maxAdsPerCycle > 0 ? t.maxAdsPerCycle : raw;
  return Math.max(0, Math.min(rail, raw));
}

export function adBankBreakdown(g: GameStateDoc, t: Tunables): AdBankBreakdown {
  return {
    base: t.baseAdsPerCycle || 0,
    dailyBonus: dailyBonus(g, t),
    streakBonus: streakBonus(g, t),
    achievementBonus: achievementBonus(g, t),
    iapBonus: iapBonus(g, t),
    max: effectiveAdsPerCycle(g, t),
  };
}

export function publicAchievements(g: GameStateDoc): AchievementPublic[] {
  const unlocked = new Set(g.unlockedAchievements || []);
  return Object.entries(ACHIEVEMENT_META).map(([id, meta]) => ({
    id,
    title: meta.title,
    detail: meta.detail,
    unlocked: unlocked.has(id),
    grantsSlot: meta.grantsSlot,
  }));
}

export function playerProgress(g: GameStateDoc, t: Tunables): PlayerProgress {
  return {
    adBank: adBankBreakdown(g, t),
    loginStreak: g.loginStreak || 0,
    bestLoginStreak: g.bestLoginStreak || 0,
    dailyGoals: dailyGoals(g, t),
    achievements: publicAchievements(g),
    iapAdsPurchased: g.iapAdsPurchased || 0,
    iapBonusAdsMax: t.iapBonusAdsMax,
  };
}

/** Call before regen / spend so the hold max matches today’s bonuses. */
export function syncAdProgress(g: GameStateDoc, t: Tunables, now: Date): number {
  ensureProgressFields(g, t, now);
  resetDailyProgress(g, t, now);
  updateLoginStreak(g, t, now);
  evaluateAchievements(g);
  const max = effectiveAdsPerCycle(g, t);
  if (typeof g.adsHoldMax !== "number") {
    g.adsHoldMax = max;
  } else if (max > g.adsHoldMax) {
    g.adCharges = Math.min(max, (g.adCharges || 0) + (max - g.adsHoldMax));
    g.adsHoldMax = max;
  } else {
    g.adsHoldMax = max;
  }
  if (g.adCharges > max) g.adCharges = max;
  return max;
}
