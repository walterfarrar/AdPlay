import * as admin from "firebase-admin";
import {
  BoostType,
  GameStateDoc,
  PublicGameState,
  Tunables,
  DEFAULT_TUNABLES,
} from "./types";
import {
  extendIsoBySeconds,
  nowIso,
  parseIso,
  utcDayKey,
  freshGame,
} from "./util";

const db = () => admin.firestore();

export async function loadTunables(): Promise<Tunables> {
  const snap = await db().doc("config/tunables").get();
  if (!snap.exists) return { ...DEFAULT_TUNABLES };
  return { ...DEFAULT_TUNABLES, ...(snap.data() as Partial<Tunables>) };
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
  return g;
}

/** Apply timed +1 charge regen up to adsPerCycle. Mutates g. */
function applyAdRegen(g: GameStateDoc, t: Tunables, now: Date): void {
  const max = t.adsPerCycle;
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

function spendAdCharge(g: GameStateDoc, t: Tunables, now: Date): void {
  applyAdRegen(g, t, now);
  if (g.adCharges <= 0) {
    throw Object.assign(new Error("No ad charges — wait for the next one"), {
      code: "resource-exhausted",
    });
  }
  const wasFull = g.adCharges >= t.adsPerCycle;
  g.adCharges -= 1;
  g.adsUsed = (g.adsUsed || 0) + 1;
  if (wasFull) {
    g.adChargesAt = nowIso(now);
  }
}

function regenPublic(g: GameStateDoc, t: Tunables, now: Date): {
  adsRemaining: number;
  adRegenSecondsLeft: number;
  nextAdChargeAt: string | null;
} {
  applyAdRegen(g, t, now);
  const adsRemaining = Math.max(0, g.adCharges);
  if (t.adRegenSeconds <= 0 || adsRemaining >= t.adsPerCycle) {
    return { adsRemaining, adRegenSecondsLeft: 0, nextAdChargeAt: null };
  }
  const from = parseIso(g.adChargesAt) ?? now;
  const nextMs = from.getTime() + t.adRegenSeconds * 1000;
  const left = Math.max(0, Math.ceil((nextMs - now.getTime()) / 1000));
  return {
    adsRemaining,
    adRegenSecondsLeft: left,
    nextAdChargeAt: new Date(nextMs).toISOString(),
  };
}

function autoFillRate(g: GameStateDoc, t: Tunables): number {
  // Rate while the shared auto window is running (independent of "is it still active right now")
  if (g.speedBoostAmount > 0) return t.baseFillRate + g.speedBoostAmount;
  return t.baseFillRate;
}

function effectiveFillRate(g: GameStateDoc, t: Tunables, now: Date): number {
  const autoUntil = parseIso(g.autoFillUntil);
  if (!autoUntil || autoUntil <= now) return 0;
  // Stronger scales auto the same way it scales manual taps (taps/sec × tapPower).
  return autoFillRate(g, t) * effectiveTapPower(g, t, now);
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
  g.adCharges = Math.max(0, t.adsPerCycle);
  g.adChargesAt = nowIso(now);
  g.adsUsed = 0;
  g.skipAdsUsed = 0;
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
  const skipUsed = g.skipAdsUsed || 0;
  const skipRemaining =
    t.skipAdsPerCycle === 0 ? -1 : Math.max(0, t.skipAdsPerCycle - skipUsed);
  const regen = regenPublic(g, t, now);
  return {
    progress: Math.min(g.progress, t.unitsPerSat),
    unitsPerSat: t.unitsPerSat,
    satsBalance: g.satsBalance,
    tapsRemaining: g.tapsRemaining,
    adsRemainingToday: regen.adsRemaining,
    adRegenSecondsLeft: regen.adRegenSecondsLeft,
    nextAdChargeAt: regen.nextAdChargeAt,
    skipAdsRemaining: skipRemaining,
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

/** Advance auto-fill in memory only (no writes). */
function advanceInMemory(
  g: GameStateDoc,
  t: Tunables,
  at: Date,
): { earned: number; credits: LedgerCredit[] } {
  resetDaily(g, t, at);
  applyAdRegen(g, t, at);
  let credits: LedgerCredit[] = [];
  let earned = 0;

  const last = parseIso(g.lastTickAt) ?? at;
  const autoUntil = parseIso(g.autoFillUntil);
  // Offline catch-up only runs until the shared auto timer — never past autoFillUntil
  if (autoUntil && autoUntil > last) {
    const earnUntil = autoUntil < at ? autoUntil : at;
    const earnSec = Math.max(0, (earnUntil.getTime() - last.getTime()) / 1000);
    // Use tap power at earnUntil so Stronger applies to offline auto catch-up too.
    const rate = autoFillRate(g, t) * effectiveTapPower(g, t, earnUntil);
    if (earnSec > 0 && rate > 0) {
      const applied = applyProgressUnits(g, t, rate * earnSec);
      earned = applied.earned;
      credits = applied.credits;
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

  g.satsEarnedToday += earned;
  g.satsBalance += earned;
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
  const applied = applyProgressUnits(g, t, effectiveTapPower(g, t, at));
  g.satsEarnedToday += applied.earned;
  g.satsBalance += applied.earned;
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
  applyAdRegen(g, t, at);
  if (g.adCharges > 0) {
    throw Object.assign(new Error("Skip available only when ad charges are empty"), {
      code: "failed-precondition",
    });
  }
  if (t.skipAdsPerCycle > 0 && (g.skipAdsUsed || 0) >= t.skipAdsPerCycle) {
    throw Object.assign(new Error("Skip ad limit reached"), { code: "resource-exhausted" });
  }

  const remainingSec = Math.max(0, (autoUntil.getTime() - at.getTime()) / 1000);
  const skipSec = Math.min(t.skipTimeSeconds, remainingSec);
  if (skipSec <= 0) {
    throw Object.assign(new Error("No auto time left to skip"), { code: "failed-precondition" });
  }

  const rate = effectiveFillRate(g, t, at);
  const applied = applyProgressUnits(g, t, rate * skipSec);
  g.satsEarnedToday += applied.earned;
  g.satsBalance += applied.earned;

  const newUntil = new Date(autoUntil.getTime() - skipSec * 1000);
  g.autoFillUntil = nowIso(newUntil);
  if (g.tapStrengthBoostAmount > 0) {
    g.tapStrengthBoostUntil = g.autoFillUntil;
  }

  // Pull the ad-regen clock forward by the same skipped duration.
  const chargeFrom = parseIso(g.adChargesAt) ?? at;
  g.adChargesAt = nowIso(new Date(chargeFrom.getTime() - skipSec * 1000));
  applyAdRegen(g, t, at);

  g.skipAdsUsed = (g.skipAdsUsed || 0) + 1;

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
): Promise<PublicGameState> {
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
    return toPublic(g, t, now);
  });

  return result;
}

export async function getPublicState(uid: string): Promise<{
  state: PublicGameState;
  tunables: Tunables & { adProvider: string; debugReset: boolean };
}> {
  const state = await runGameTx(uid, () => []);
  const t = await loadTunables();
  return {
    state,
    tunables: { ...t, adProvider: "waterfall", debugReset: true },
  };
}

export async function tap(uid: string): Promise<PublicGameState> {
  return runGameTx(uid, (g, t, now) => applyManualTapInMemory(g, t, now));
}

export async function applyBoost(
  uid: string,
  boostType: BoostType,
  eventId: string,
): Promise<PublicGameState> {
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
      return toPublic(g, t, now);
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
      return toPublic(g, t, now);
    }

    spendAdCharge(g, t, now);

    const autoUntil = parseIso(g.autoFillUntil);
    const idle = !autoUntil || autoUntil <= now;

    if (boostType === "tap_strength") {
      // Like Faster: if auto is empty, start the shared window + base rate
      if (idle) {
        g.autoFillUntil = extendIsoBySeconds(null, t.durationBoostSeconds, now);
        g.speedBoostAmount = t.speedBoostAmount;
        g.speedBoostUntil = null;
      }
      g.tapStrengthBoostAmount = (g.tapStrengthBoostAmount || 0) + t.tapStrengthBoostAmount;
      g.tapStrengthBoostCount = (g.tapStrengthBoostCount || 0) + 1;
      // Stronger uses the shared auto clock (no separate timer)
      g.tapStrengthBoostUntil = g.autoFillUntil;
    } else if (idle) {
      // First Longer/Faster: start shared auto window + base Faster rate
      g.autoFillUntil = extendIsoBySeconds(null, t.durationBoostSeconds, now);
      g.speedBoostAmount = t.speedBoostAmount;
      g.speedBoostUntil = null;
      if (boostType === "duration") {
        g.durationBoostCount = (g.durationBoostCount || 0) + 1;
      } else {
        g.speedBoostCount = (g.speedBoostCount || 0) + 1;
      }
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
    return toPublic(g, t, now);
  });
}

export async function resetEverything(uid: string): Promise<PublicGameState> {
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

  return toPublic(g, t, new Date());
}

export { toPublic, gameRef };
