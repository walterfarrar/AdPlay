import * as admin from "firebase-admin";
import {
  BoostType,
  GameStateDoc,
  PublicGameState,
  Tunables,
  DEFAULT_TUNABLES,
} from "./types";
import {
  debugResetAllowed,
  extendIsoBySeconds,
  nowIso,
  parseIso,
  utcDayKey,
  utcDayStart,
  freshGame,
} from "./util";
import {
  effectiveAdsPerCycle,
  playerProgress,
  recordAutoActivated,
  recordBoostAdWatch,
  syncAdProgress,
} from "./adCurrency";
import {
  applyComboTap,
  comboAt,
  comboMultiplier,
  persistCombo,
  tapsFromPersisted,
  type ComboParams,
  type ComboState,
} from "./combo";
import type { PlayerProgress } from "./types";

const db = () => admin.firestore();

export async function loadTunables(): Promise<Tunables> {
  const snap = await db().doc("config/tunables").get();
  const t = snap.exists
    ? { ...DEFAULT_TUNABLES, ...(snap.data() as Partial<Tunables>) }
    : { ...DEFAULT_TUNABLES };
  // Stored caps must not sit below current defaults or new slot sources get clipped.
  t.achievementBonusAdsMax = Math.max(
    t.achievementBonusAdsMax,
    DEFAULT_TUNABLES.achievementBonusAdsMax,
  );
  t.maxAdsPerCycle = Math.max(t.maxAdsPerCycle, DEFAULT_TUNABLES.maxAdsPerCycle);
  // Legacy stored 0 was midnight UTC (evening in the US). Treat it as unset.
  if (!Number.isFinite(t.resetHourUtc) || t.resetHourUtc === 0) {
    t.resetHourUtc = DEFAULT_TUNABLES.resetHourUtc;
  } else {
    t.resetHourUtc = Math.max(1, Math.min(23, Math.trunc(t.resetHourUtc)));
  }
  return t;
}

function gameRef(uid: string) {
  return db().doc(`users/${uid}/game/state`);
}

function migrateGame(raw: admin.firestore.DocumentData | undefined, t: Tunables): GameStateDoc {
  if (!raw) return freshGame(t);
  const g = raw as GameStateDoc & {
    durationBoostApplied?: boolean;
    speedBoostApplied?: boolean;
  };
  if (g.tapStrengthBoostUntil === undefined) g.tapStrengthBoostUntil = null;
  if (g.tapStrengthBoostAmount === undefined) g.tapStrengthBoostAmount = 0;
  if (g.skipAdsUsed === undefined) g.skipAdsUsed = 0;
  // Migrate legacy booleans → counts (true ⇒ at least 1 this cycle).
  if (g.durationBoostCount === undefined) {
    g.durationBoostCount = g.durationBoostApplied ? 1 : 0;
  }
  if (g.speedBoostCount === undefined) {
    g.speedBoostCount = g.speedBoostApplied ? 1 : 0;
  }
  if (g.tapStrengthBoostCount === undefined) {
    if (g.tapStrengthBoostAmount > 0 && t.tapStrengthBoostAmount > 0) {
      g.tapStrengthBoostCount = Math.max(
        1,
        Math.round(g.tapStrengthBoostAmount / t.tapStrengthBoostAmount),
      );
    } else {
      g.tapStrengthBoostCount = 0;
    }
  }
  // Legacy adsUsed → banked adCharges.
  if (g.adCharges === undefined) {
    const used = typeof g.adsUsed === "number" ? g.adsUsed : 0;
    g.adCharges = Math.max(0, t.adsPerCycle - used);
    g.adChargesAt = g.lastTickAt || nowIso();
  }
  if (!g.adChargesAt) g.adChargesAt = g.lastTickAt || nowIso();
  // Legacy skipAdsUsed → banked skipAdCharges.
  if (g.skipAdCharges === undefined) {
    if (t.skipAdsPerCycle <= 0) {
      g.skipAdCharges = 0;
    } else {
      const used = typeof g.skipAdsUsed === "number" ? g.skipAdsUsed : 0;
      g.skipAdCharges = Math.max(0, t.skipAdsPerCycle - used);
    }
    g.skipAdChargesAt = g.adChargesAt || g.lastTickAt || nowIso();
  }
  if (!g.skipAdChargesAt) g.skipAdChargesAt = g.adChargesAt || g.lastTickAt || nowIso();
  if (typeof g.comboMeter !== "number" || Number.isNaN(g.comboMeter)) g.comboMeter = 0;
  if (typeof g.comboLevel !== "number" || Number.isNaN(g.comboLevel)) g.comboLevel = 0;
  if (typeof g.comboContrib !== "number" || Number.isNaN(g.comboContrib)) g.comboContrib = 0;
  if (typeof g.comboMeter1 !== "number" || Number.isNaN(g.comboMeter1)) g.comboMeter1 = 0;
  if (typeof g.comboLevel1 !== "number" || Number.isNaN(g.comboLevel1)) g.comboLevel1 = 0;
  if (typeof g.comboContrib1 !== "number" || Number.isNaN(g.comboContrib1)) g.comboContrib1 = 0;
  if (typeof g.comboMeter2 !== "number" || Number.isNaN(g.comboMeter2)) g.comboMeter2 = 0;
  if (typeof g.comboLevel2 !== "number" || Number.isNaN(g.comboLevel2)) g.comboLevel2 = 0;
  if (typeof g.comboContrib2 !== "number" || Number.isNaN(g.comboContrib2)) g.comboContrib2 = 0;
  if (typeof g.comboTaps === "number" && !Number.isFinite(g.comboTaps)) g.comboTaps = 0;
  if (g.lastManualTapAt === undefined) g.lastManualTapAt = null;
  return g;
}

function comboParams(t: Tunables): ComboParams {
  return {
    comboTapsPerLevel: t.comboTapsPerLevel ?? 100,
    comboStep: t.comboStep ?? 0.1,
    comboBase: t.comboBase ?? 1.0,
    comboAbsMax: t.comboAbsMax ?? 3.0,
    comboRing0Max: t.comboRing0Max ?? 1.0,
    comboRing1Max: t.comboRing1Max ?? 1.0,
    comboRing2Max: t.comboRing2Max ?? 1.0,
    comboIdleGraceSeconds: t.comboIdleGraceSeconds ?? 1.5,
    comboDrainPerSecondActive: t.comboDrainPerSecondActive ?? 0.002,
    comboDrainPerSecondIdle: t.comboDrainPerSecondIdle ?? 0.5,
  };
}

function persistedCombo(g: GameStateDoc, t: ComboParams): ComboState {
  return {
    taps: tapsFromPersisted(g.comboTaps, g.comboLevel || 0, g.comboMeter || 0, t),
    lastTapAtMs: parseIso(g.lastManualTapAt)?.getTime() ?? null,
  };
}

function writeCombo(g: GameStateDoc, next: ComboState, t: ComboParams): void {
  const p = persistCombo(next, t);
  g.comboTaps = p.comboTaps;
  g.comboMeter = p.comboMeter;
  g.comboLevel = p.comboLevel;
  g.comboContrib = p.comboContrib;
  g.comboMeter1 = p.comboMeter1;
  g.comboLevel1 = p.comboLevel1;
  g.comboContrib1 = p.comboContrib1;
  g.comboMeter2 = p.comboMeter2;
  g.comboLevel2 = p.comboLevel2;
  g.comboContrib2 = p.comboContrib2;
  g.lastManualTapAt =
    next.lastTapAtMs == null ? null : new Date(next.lastTapAtMs).toISOString();
}

function adsMax(g: GameStateDoc, t: Tunables): number {
  return effectiveAdsPerCycle(g, t);
}

/** Apply timed +1 charge regen up to adsPerCycle. Mutates g. */
function applyAdRegen(g: GameStateDoc, t: Tunables, now: Date): void {
  const max = adsMax(g, t);
  if (max <= 0) {
    g.adCharges = 0;
    return;
  }
  if (g.adCharges > max) g.adCharges = max;
  if (t.adRegenSeconds <= 0) return;
  if (g.adCharges >= max) return;

  const from = parseIso(g.adChargesAt) ?? now;
  const elapsed = Math.max(0, (now.getTime() - from.getTime()) / 1000);
  if (elapsed < t.adRegenSeconds) return;

  const gained = Math.floor(elapsed / t.adRegenSeconds);
  g.adCharges = Math.min(max, g.adCharges + gained);
  const remainderSec = elapsed % t.adRegenSeconds;
  g.adChargesAt = nowIso(new Date(now.getTime() - remainderSec * 1000));
  if (g.adCharges >= max) {
    g.adCharges = max;
    g.adChargesAt = nowIso(now);
  }
}

/** Apply timed +1 Skip charge regen up to skipAdsPerCycle (same interval as boost ads). */
function applySkipAdRegen(g: GameStateDoc, t: Tunables, now: Date): void {
  // <= 0: disabled (-1) or unlimited (0) — no bank / regen.
  if (t.skipAdsPerCycle <= 0) {
    g.skipAdCharges = 0;
    return;
  }
  const max = t.skipAdsPerCycle;
  if (g.skipAdCharges > max) g.skipAdCharges = max;
  if (t.adRegenSeconds <= 0) return;
  if (g.skipAdCharges >= max) return;

  const from = parseIso(g.skipAdChargesAt) ?? now;
  const elapsed = Math.max(0, (now.getTime() - from.getTime()) / 1000);
  if (elapsed < t.adRegenSeconds) return;

  const gained = Math.floor(elapsed / t.adRegenSeconds);
  g.skipAdCharges = Math.min(max, g.skipAdCharges + gained);
  const remainderSec = elapsed % t.adRegenSeconds;
  g.skipAdChargesAt = nowIso(new Date(now.getTime() - remainderSec * 1000));
  if (g.skipAdCharges >= max) {
    g.skipAdCharges = max;
    g.skipAdChargesAt = nowIso(now);
  }
}

function spendAdCharge(g: GameStateDoc, t: Tunables, now: Date): void {
  applyAdRegen(g, t, now);
  if (g.adCharges <= 0) {
    throw Object.assign(new Error("No ad charges — wait for the next one"), {
      code: "resource-exhausted",
    });
  }
  const wasFull = g.adCharges >= adsMax(g, t);
  g.adCharges -= 1;
  g.adsUsed = (g.adsUsed || 0) + 1;
  recordBoostAdWatch(g, t, now);
  if (wasFull) {
    g.adChargesAt = nowIso(now);
  }
}

function regenPublic(g: GameStateDoc, t: Tunables, now: Date): {
  adsRemaining: number;
  adRegenSecondsLeft: number;
  nextAdChargeAt: string | null;
  skipAdsRemaining: number;
  skipAdRegenSecondsLeft: number;
  nextSkipAdChargeAt: string | null;
} {
  applyAdRegen(g, t, now);
  applySkipAdRegen(g, t, now);

  const adsRemaining = Math.max(0, g.adCharges);
  let adRegenSecondsLeft = 0;
  let nextAdChargeAt: string | null = null;
  if (t.adRegenSeconds > 0 && adsRemaining < adsMax(g, t)) {
    const from = parseIso(g.adChargesAt) ?? now;
    const nextMs = from.getTime() + t.adRegenSeconds * 1000;
    adRegenSecondsLeft = Math.max(0, Math.ceil((nextMs - now.getTime()) / 1000));
    nextAdChargeAt = new Date(nextMs).toISOString();
  }

  // Disabled: no Skip Time surface.
  if (t.skipAdsPerCycle < 0) {
    return {
      adsRemaining,
      adRegenSecondsLeft,
      nextAdChargeAt,
      skipAdsRemaining: 0,
      skipAdRegenSecondsLeft: 0,
      nextSkipAdChargeAt: null,
    };
  }

  // Unlimited skip bank.
  if (t.skipAdsPerCycle === 0) {
    return {
      adsRemaining,
      adRegenSecondsLeft,
      nextAdChargeAt,
      skipAdsRemaining: -1,
      skipAdRegenSecondsLeft: 0,
      nextSkipAdChargeAt: null,
    };
  }

  const skipAdsRemaining = Math.max(0, g.skipAdCharges);
  let skipAdRegenSecondsLeft = 0;
  let nextSkipAdChargeAt: string | null = null;
  if (t.adRegenSeconds > 0 && skipAdsRemaining < t.skipAdsPerCycle) {
    const from = parseIso(g.skipAdChargesAt) ?? now;
    const nextMs = from.getTime() + t.adRegenSeconds * 1000;
    skipAdRegenSecondsLeft = Math.max(0, Math.ceil((nextMs - now.getTime()) / 1000));
    nextSkipAdChargeAt = new Date(nextMs).toISOString();
  }

  return {
    adsRemaining,
    adRegenSecondsLeft,
    nextAdChargeAt,
    skipAdsRemaining,
    skipAdRegenSecondsLeft,
    nextSkipAdChargeAt,
  };
}

function autoFillRate(g: GameStateDoc, t: Tunables): number {
  // Rate while the shared auto window is running (independent of "is it still active right now")
  if (g.speedBoostAmount > 0) return t.baseFillRate + g.speedBoostAmount;
  return t.baseFillRate;
}

/** Stronger only. Combo never applies to Auto Tapper or offline catch-up. */
function autoTapPower(g: GameStateDoc, t: Tunables, now: Date): number {
  return effectiveTapPower(g, t, now);
}

function effectiveFillRate(g: GameStateDoc, t: Tunables, now: Date): number {
  const autoUntil = parseIso(g.autoFillUntil);
  if (!autoUntil || autoUntil <= now) return 0;
  return autoFillRate(g, t) * autoTapPower(g, t, now);
}

function effectiveTapPower(g: GameStateDoc, t: Tunables, now: Date): number {
  let power = t.tapUnits;
  // Stronger lasts for the shared auto window (same clock as Longer/Faster).
  const autoUntil = parseIso(g.autoFillUntil);
  if (autoUntil && autoUntil > now && g.tapStrengthBoostAmount > 0) {
    power += g.tapStrengthBoostAmount;
  }
  return power;
}

function resetDaily(g: GameStateDoc, t: Tunables, now: Date): void {
  const day = utcDayKey(t.resetHourUtc, now);
  if (g.tapDay !== day) {
    g.tapDay = day;
    g.tapsRemaining = t.dailyTapCap;
  }
  if (g.satsDay !== day) {
    g.satsDay = day;
    g.satsEarnedToday = 0;
  }
  syncAdProgress(g, t, now);
}

/** When the shared auto window ends, clear boosts and refill the ad bank. */
function refreshAdCycleIfIdle(g: GameStateDoc, t: Tunables, now: Date): void {
  const autoUntil = parseIso(g.autoFillUntil);
  if (autoUntil && autoUntil > now) return;
  g.autoFillUntil = null;
  g.speedBoostUntil = null;
  g.speedBoostAmount = 0;
  g.tapStrengthBoostUntil = null;
  g.tapStrengthBoostAmount = 0;
  g.durationBoostCount = 0;
  g.speedBoostCount = 0;
  g.tapStrengthBoostCount = 0;
  // New run: restore the full ad + skip bank.
  g.adCharges = Math.max(0, adsMax(g, t));
  g.adChargesAt = nowIso(now);
  g.adsUsed = 0;
  g.skipAdsUsed = 0;
  g.skipAdCharges = t.skipAdsPerCycle > 0 ? t.skipAdsPerCycle : 0;
  g.skipAdChargesAt = nowIso(now);
}

function toPublic(g: GameStateDoc, t: Tunables, now: Date): PublicGameState {
  const autoUntil = parseIso(g.autoFillUntil);
  let cooldownLeft = 0;
  const lastAd = parseIso(g.lastAdAt);
  if (lastAd) {
    const elapsed = (now.getTime() - lastAd.getTime()) / 1000;
    cooldownLeft = Math.max(0, Math.ceil(t.adCooldownSeconds - elapsed));
  }
  const autoActive = !!(autoUntil && autoUntil > now);
  const durationCount = g.durationBoostCount || 0;
  const speedCount = g.speedBoostCount || 0;
  const tapCount = g.tapStrengthBoostCount || 0;
  const tapActive = autoActive && g.tapStrengthBoostAmount > 0;
  // Button "running" state: only after that boost type was actually watched.
  const speedActive = autoActive && speedCount > 0;
  const durationActive = autoActive && durationCount > 0;
  const regen = regenPublic(g, t, now);
  const comboT = comboParams(t);
  const persisted = persistedCombo(g, comboT);
  const liveCombo = comboAt(persisted, now.getTime(), comboT);
  return {
    progress: Math.min(g.progress, t.unitsPerSat),
    unitsPerSat: t.unitsPerSat,
    satsBalance: g.satsBalance,
    tapsRemaining: g.tapsRemaining,
    adsRemainingToday: regen.adsRemaining,
    adRegenSecondsLeft: regen.adRegenSecondsLeft,
    nextAdChargeAt: regen.nextAdChargeAt,
    skipAdsRemaining: regen.skipAdsRemaining,
    skipAdRegenSecondsLeft: regen.skipAdRegenSecondsLeft,
    nextSkipAdChargeAt: regen.nextSkipAdChargeAt,
    satsEarnedToday: g.satsEarnedToday,
    dailySatsEarnCap: t.dailySatsEarnCap,
    autoFillActive: autoActive,
    autoFillUntil: g.autoFillUntil,
    fillRate: effectiveFillRate(g, t, now),
    speedBoostActive: speedActive,
    // Same shared auto timer — Faster/Stronger have no separate clock
    speedBoostUntil: autoActive ? g.autoFillUntil : null,
    durationBoostActive: durationActive,
    durationBoostCount: durationCount,
    speedBoostCount: speedCount,
    tapStrengthBoostCount: tapCount,
    tapStrengthActive: tapActive,
    tapStrengthUntil: tapActive ? g.autoFillUntil : null,
    tapPower: effectiveTapPower(g, t, now),
    comboTaps: persisted.taps,
    comboMeter: g.comboMeter || 0,
    comboLevel: g.comboLevel || 0,
    comboContrib: g.comboContrib || 0,
    comboMeter1: g.comboMeter1 || 0,
    comboLevel1: g.comboLevel1 || 0,
    comboContrib1: g.comboContrib1 || 0,
    comboMeter2: g.comboMeter2 || 0,
    comboLevel2: g.comboLevel2 || 0,
    comboContrib2: g.comboContrib2 || 0,
    lastManualTapAt: g.lastManualTapAt || null,
    comboMultiplier: comboMultiplier(liveCombo, comboT),
    adCooldownSecondsLeft: cooldownLeft,
    lastBoostType: g.lastBoostType,
    minWithdrawSats: t.minWithdrawSats,
    resetHourUtc: t.resetHourUtc,
    updatedAt: g.lastTickAt,
  };
}

type LedgerCredit = { id: string; reason: string };

/** Apply progress units with bar completions (mutates g; returns credits + earned count). */
function applyProgressUnits(
  g: GameStateDoc,
  t: Tunables,
  units: number,
): { earned: number; credits: LedgerCredit[] } {
  const credits: LedgerCredit[] = [];
  let earned = 0;
  if (units <= 0) return { earned, credits };
  let progress = g.progress + units;
  while (progress >= t.unitsPerSat) {
    // dailySatsEarnCap <= 0 means unlimited
    if (t.dailySatsEarnCap > 0 && g.satsEarnedToday + earned >= t.dailySatsEarnCap) {
      progress = t.unitsPerSat - 0.0001;
      break;
    }
    progress -= t.unitsPerSat;
    earned += 1;
    credits.push({ id: db().collection("_").doc().id, reason: "bar_complete" });
  }
  g.progress = progress;
  return { earned, credits };
}

function catchUpSlice(
  g: GameStateDoc,
  t: Tunables,
  from: Date,
  to: Date,
): { earned: number; credits: LedgerCredit[] } {
  const earnSec = Math.max(0, (to.getTime() - from.getTime()) / 1000);
  // Offline / background auto uses Stronger only — never comboMultiplier.
  const rate = autoFillRate(g, t) * autoTapPower(g, t, to);
  if (earnSec <= 0 || rate <= 0) return { earned: 0, credits: [] };
  return applyProgressUnits(g, t, rate * earnSec);
}

/** Advance auto-fill in memory only (no writes). */
function advanceInMemory(
  g: GameStateDoc,
  t: Tunables,
  at: Date,
): { earned: number; credits: LedgerCredit[] } {
  resetDaily(g, t, at);
  applyAdRegen(g, t, at);
  applySkipAdRegen(g, t, at);
  let credits: LedgerCredit[] = [];
  let earned = 0;

  const last = parseIso(g.lastTickAt) ?? at;
  const autoUntil = parseIso(g.autoFillUntil);
  // Offline catch-up only runs until the shared auto timer — never past autoFillUntil.
  // Split at the UTC day start so leftover yesterday fill cannot complete today's sat goal.
  if (autoUntil && autoUntil > last) {
    const earnUntil = autoUntil < at ? autoUntil : at;
    const dayStart = utcDayStart(t.resetHourUtc, at);
    const priorEnd = earnUntil.getTime() < dayStart.getTime() ? earnUntil : dayStart;
    if (last.getTime() < priorEnd.getTime()) {
      const prior = catchUpSlice(g, t, last, priorEnd);
      earned += prior.earned;
      credits = credits.concat(prior.credits);
    }
    const todayFrom = last.getTime() > dayStart.getTime() ? last : dayStart;
    if (todayFrom.getTime() < earnUntil.getTime()) {
      const today = catchUpSlice(g, t, todayFrom, earnUntil);
      earned += today.earned;
      credits = credits.concat(today.credits);
      g.satsEarnedToday += today.earned;
    }
  }

  const autoAlive = !!(autoUntil && autoUntil > at);

  if (!autoAlive) {
    // Shared auto ended — clear boosts and refill ads for the next run
    refreshAdCycleIfIdle(g, t, at);
  } else if (g.tapStrengthBoostAmount > 0) {
    // Keep legacy field mirrored to the shared auto clock
    g.tapStrengthBoostUntil = g.autoFillUntil;
  }

  g.satsBalance += earned;
  g.lifetimeSatsEarned = (g.lifetimeSatsEarned || 0) + earned;
  g.fillRate = effectiveFillRate(g, t, at);
  g.lastTickAt = nowIso(at);
  return { earned, credits };
}

function applyManualTapInMemory(
  g: GameStateDoc,
  t: Tunables,
  at: Date,
): LedgerCredit[] {
  resetDaily(g, t, at);
  if (g.tapsRemaining <= 0) {
    throw Object.assign(new Error("No taps remaining today"), { code: "resource-exhausted" });
  }

  g.tapsRemaining -= 1;
  const comboT = comboParams(t);
  const nextCombo = applyComboTap(persistedCombo(g, comboT), at.getTime(), comboT);
  writeCombo(g, nextCombo, comboT);
  // Combo stacks with Stronger for this live tap only. Auto catch-up already
  // ran in runGameTx via advanceInMemory (no combo).
  const units = autoTapPower(g, t, at) * comboMultiplier(nextCombo, comboT);
  const applied = applyProgressUnits(g, t, units);
  g.satsEarnedToday += applied.earned;
  g.satsBalance += applied.earned;
  g.lifetimeSatsEarned = (g.lifetimeSatsEarned || 0) + applied.earned;
  g.fillRate = effectiveFillRate(g, t, at);
  g.lastTickAt = nowIso(at);
  return applied.credits;
}

/**
 * Skip Time: shorten auto by skipSec and credit fillRate × skipSec progress.
 * Mutates g; returns ledger credits for any completed bars.
 */
function applySkipTimeInMemory(
  g: GameStateDoc,
  t: Tunables,
  at: Date,
): LedgerCredit[] {
  const autoUntil = parseIso(g.autoFillUntil);
  if (!autoUntil || autoUntil <= at) {
    throw Object.assign(new Error("Auto is not running"), { code: "failed-precondition" });
  }
  if (t.skipAdsPerCycle < 0) {
    throw Object.assign(new Error("Skip Time is disabled"), { code: "failed-precondition" });
  }
  applyAdRegen(g, t, at);
  applySkipAdRegen(g, t, at);
  if (g.adCharges > 0) {
    throw Object.assign(new Error("Skip available only when ad charges are empty"), {
      code: "failed-precondition",
    });
  }
  if (t.skipAdsPerCycle > 0 && g.skipAdCharges <= 0) {
    throw Object.assign(new Error("No Skip charges — wait for the next one"), {
      code: "resource-exhausted",
    });
  }

  const remainingSec = Math.max(0, (autoUntil.getTime() - at.getTime()) / 1000);
  const skipSec = Math.min(t.skipTimeSeconds, remainingSec);
  if (skipSec <= 0) {
    throw Object.assign(new Error("No auto time left to skip"), { code: "failed-precondition" });
  }

  // Spend the Skip charge before advancing regen clocks via skipped time.
  if (t.skipAdsPerCycle > 0) {
    const wasFull = g.skipAdCharges >= t.skipAdsPerCycle;
    g.skipAdCharges -= 1;
    g.skipAdsUsed = (g.skipAdsUsed || 0) + 1;
    if (wasFull) g.skipAdChargesAt = nowIso(at);
  } else {
    g.skipAdsUsed = (g.skipAdsUsed || 0) + 1;
  }

  const rate = effectiveFillRate(g, t, at);
  const applied = applyProgressUnits(g, t, rate * skipSec);
  g.satsEarnedToday += applied.earned;
  g.satsBalance += applied.earned;
  g.lifetimeSatsEarned = (g.lifetimeSatsEarned || 0) + applied.earned;

  const newUntil = new Date(autoUntil.getTime() - skipSec * 1000);
  g.autoFillUntil = nowIso(newUntil);
  if (g.tapStrengthBoostAmount > 0) {
    g.tapStrengthBoostUntil = g.autoFillUntil;
  }

  // Pull boost + skip regen clocks forward by the same skipped duration.
  const chargeFrom = parseIso(g.adChargesAt) ?? at;
  g.adChargesAt = nowIso(new Date(chargeFrom.getTime() - skipSec * 1000));
  const skipFrom = parseIso(g.skipAdChargesAt) ?? at;
  g.skipAdChargesAt = nowIso(new Date(skipFrom.getTime() - skipSec * 1000));
  applyAdRegen(g, t, at);
  applySkipAdRegen(g, t, at);

  if (newUntil <= at) {
    refreshAdCycleIfIdle(g, t, at);
  }

  g.fillRate = effectiveFillRate(g, t, at);
  g.lastTickAt = nowIso(at);
  return applied.credits;
}

function writeCredits(
  tx: admin.firestore.Transaction,
  uid: string,
  credits: LedgerCredit[],
): void {
  for (const c of credits) {
    tx.set(db().doc(`users/${uid}/ledger/${c.id}`), {
      deltaSats: 1,
      reason: c.reason,
      createdAt: nowIso(),
    });
  }
}

/**
 * All game mutations go through a Firestore transaction so concurrent
 * getState (auto tick) and tap cannot clobber each other.
 */
async function runGameTx(
  uid: string,
  mutate: (
    g: GameStateDoc,
    t: Tunables,
    now: Date,
    tx: admin.firestore.Transaction,
  ) => LedgerCredit[],
): Promise<{ state: PublicGameState; progress: PlayerProgress }> {
  const t = await loadTunables();
  const now = new Date();
  const ref = gameRef(uid);

  const result = await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const created = !snap.exists;
    const g = migrateGame(snap.data(), t);
    if (created) {
      tx.set(db().doc(`users/${uid}`), { createdAt: nowIso(now) }, { merge: true });
    }

    const tickCredits = advanceInMemory(g, t, now);
    const extraCredits = mutate(g, t, now, tx);
    const credits = [...tickCredits.credits, ...extraCredits];

    writeCredits(tx, uid, credits);
    tx.set(ref, g);
    return { state: toPublic(g, t, now), progress: playerProgress(g, t) };
  });

  return result;
}

export async function getPublicState(uid: string): Promise<{
  state: PublicGameState;
  tunables: Tunables & { adProvider: string; debugReset: boolean; adsPerCycle: number };
  progress: PlayerProgress;
}> {
  const { state, progress } = await runGameTx(uid, () => []);
  const t = await loadTunables();
  return {
    state,
    progress,
    tunables: {
      ...t,
      adsPerCycle: progress.adBank.max,
      adProvider: process.env.AD_PROVIDER ?? "waterfall",
      debugReset: debugResetAllowed(),
    },
  };
}

export async function tap(uid: string): Promise<{
  state: PublicGameState;
  progress: PlayerProgress;
}> {
  return runGameTx(uid, (g, t, now) => applyManualTapInMemory(g, t, now));
}

export async function applyBoost(
  uid: string,
  boostType: BoostType,
  eventId: string,
): Promise<{ state: PublicGameState; progress: PlayerProgress }> {
  const t = await loadTunables();
  const eventRef = db().doc(`users/${uid}/adEvents/${eventId}`);
  const now = new Date();
  const ref = gameRef(uid);

  return db().runTransaction(async (tx) => {
    const eventSnap = await tx.get(eventRef);
    const snap = await tx.get(ref);
    const g = migrateGame(snap.data(), t);
    if (!snap.exists) {
      tx.set(db().doc(`users/${uid}`), { createdAt: nowIso(now) }, { merge: true });
    }

    if (eventSnap.exists) {
      const tickCredits = advanceInMemory(g, t, now);
      writeCredits(tx, uid, tickCredits.credits);
      tx.set(ref, g);
      return { state: toPublic(g, t, now), progress: playerProgress(g, t) };
    }

    const tickCredits = advanceInMemory(g, t, now);
    resetDaily(g, t, now);

    const lastAd = parseIso(g.lastAdAt);
    if (lastAd) {
      const elapsed = (now.getTime() - lastAd.getTime()) / 1000;
      if (elapsed < t.adCooldownSeconds) {
        throw Object.assign(new Error("Ad cooldown active"), { code: "resource-exhausted" });
      }
    }

    let skipCredits: LedgerCredit[] = [];

    if (boostType === "skip_time") {
      skipCredits = applySkipTimeInMemory(g, t, now);
      g.lastAdAt = nowIso(now);
      g.lastBoostType = boostType;
      writeCredits(tx, uid, [...tickCredits.credits, ...skipCredits]);
      tx.set(eventRef, { boostType, appliedAt: nowIso(now) });
      tx.set(ref, g);
      return { state: toPublic(g, t, now), progress: playerProgress(g, t) };
    }

    const autoUntil = parseIso(g.autoFillUntil);
    const idle = !autoUntil || autoUntil <= now;

    // Free starter ad: start Auto Tapper without spending the boost bank or counting as Longer.
    if (boostType === "activate") {
      if (!idle) {
        throw Object.assign(new Error("Auto Tapper already active"), {
          code: "failed-precondition",
        });
      }
      g.autoFillUntil = extendIsoBySeconds(null, t.durationBoostSeconds, now);
      g.speedBoostAmount = t.speedBoostAmount;
      g.speedBoostUntil = null;
      recordAutoActivated(g, t, now);
      recordBoostAdWatch(g, t, now);
      g.lastAdAt = nowIso(now);
      g.lastBoostType = boostType;
      g.fillRate = effectiveFillRate(g, t, now);
      g.lastTickAt = nowIso(now);
      writeCredits(tx, uid, tickCredits.credits);
      tx.set(eventRef, { boostType, appliedAt: nowIso(now) });
      tx.set(ref, g);
      return { state: toPublic(g, t, now), progress: playerProgress(g, t) };
    }

    // Faster / Stronger require an active Auto Tapper (via Activate or Longer).
    if ((boostType === "speed" || boostType === "tap_strength") && idle) {
      throw Object.assign(new Error("Activate Auto Tapper first"), {
        code: "failed-precondition",
      });
    }

    spendAdCharge(g, t, now);

    if (boostType === "tap_strength") {
      g.tapStrengthBoostAmount = (g.tapStrengthBoostAmount || 0) + t.tapStrengthBoostAmount;
      g.tapStrengthBoostCount = (g.tapStrengthBoostCount || 0) + 1;
      // Stronger uses the shared auto clock (no separate timer)
      g.tapStrengthBoostUntil = g.autoFillUntil;
    } else if (idle) {
      // First Longer (legacy / API): start shared auto window + base Faster rate
      g.autoFillUntil = extendIsoBySeconds(null, t.durationBoostSeconds, now);
      g.speedBoostAmount = t.speedBoostAmount;
      g.speedBoostUntil = null;
      g.durationBoostCount = (g.durationBoostCount || 0) + 1;
      recordAutoActivated(g, t, now);
    } else if (boostType === "duration") {
      // Longer: extend the shared auto timer only
      g.autoFillUntil = extendIsoBySeconds(g.autoFillUntil, t.durationBoostSeconds, now);
      g.durationBoostCount = (g.durationBoostCount || 0) + 1;
      if (g.tapStrengthBoostAmount > 0) {
        g.tapStrengthBoostUntil = g.autoFillUntil;
      }
    } else {
      // Faster: raise rate for the remaining shared auto window (no timer change)
      g.speedBoostAmount = g.speedBoostAmount + t.speedBoostAmount;
      g.speedBoostCount = (g.speedBoostCount || 0) + 1;
    }

    g.lastAdAt = nowIso(now);
    g.lastBoostType = boostType;
    g.fillRate = effectiveFillRate(g, t, now);
    g.lastTickAt = nowIso(now);

    writeCredits(tx, uid, tickCredits.credits);
    tx.set(eventRef, { boostType, appliedAt: nowIso(now) });
    tx.set(ref, g);
    return { state: toPublic(g, t, now), progress: playerProgress(g, t) };
  });
}

export async function resetEverything(uid: string): Promise<{
  state: PublicGameState;
  progress: PlayerProgress;
}> {
  const t = await loadTunables();
  const g = freshGame(t);
  const batch = db().batch();
  batch.set(gameRef(uid), g);

  const ledger = await db().collection(`users/${uid}/ledger`).listDocuments();
  ledger.forEach((d) => batch.delete(d));
  const ads = await db().collection(`users/${uid}/adEvents`).listDocuments();
  ads.forEach((d) => batch.delete(d));
  const wd = await db().collection(`users/${uid}/withdrawals`).listDocuments();
  wd.forEach((d) => batch.delete(d));
  await batch.commit();

  const now = new Date();
  syncAdProgress(g, t, now);
  return { state: toPublic(g, t, now), progress: playerProgress(g, t) };
}

/** Wipe every Firestore doc under `users/{uid}` (game, ledger, withdrawals, ads, IAP). */
export async function deleteAccountData(uid: string): Promise<void> {
  await db().recursiveDelete(db().doc(`users/${uid}`));
}

export async function purchaseAdSlot(
  uid: string,
  transactionId: string,
): Promise<{ state: PublicGameState; progress: PlayerProgress }> {
  const id = transactionId.trim();
  if (!id || id.length > 200) {
    throw Object.assign(new Error("Invalid transaction"), { code: "invalid-argument" });
  }
  const t = await loadTunables();
  const now = new Date();
  const ref = gameRef(uid);
  const iapRef = db().doc(`users/${uid}/iapPurchases/${id}`);

  return db().runTransaction(async (tx) => {
    const iapSnap = await tx.get(iapRef);
    const snap = await tx.get(ref);
    const g = migrateGame(snap.data(), t);
    if (!snap.exists) {
      tx.set(db().doc(`users/${uid}`), { createdAt: nowIso(now) }, { merge: true });
    }
    const tickCredits = advanceInMemory(g, t, now);
    writeCredits(tx, uid, tickCredits.credits);

    if (!iapSnap.exists) {
      if ((g.iapAdsPurchased || 0) >= t.iapBonusAdsMax) {
        throw Object.assign(new Error("Ad slot purchases are maxed"), {
          code: "failed-precondition",
        });
      }
      g.iapAdsPurchased = (g.iapAdsPurchased || 0) + 1;
      tx.set(iapRef, { purchasedAt: nowIso(now), productId: "com.adplay.app.adslot" });
    }
    syncAdProgress(g, t, now);
    tx.set(ref, g);
    return { state: toPublic(g, t, now), progress: playerProgress(g, t) };
  });
}

export async function markPaidRedeem(uid: string): Promise<void> {
  const ref = gameRef(uid);
  const snap = await ref.get();
  if (!snap.exists) return;
  await ref.set({ hasPaidRedeem: true }, { merge: true });
}

export { toPublic, gameRef };
