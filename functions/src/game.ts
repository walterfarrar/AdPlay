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
  const g = raw as GameStateDoc;
  if (g.tapStrengthBoostUntil === undefined) g.tapStrengthBoostUntil = null;
  if (g.tapStrengthBoostAmount === undefined) g.tapStrengthBoostAmount = 0;
  return g;
}

function autoFillRate(g: GameStateDoc, t: Tunables): number {
  // Rate while the shared auto window is running (independent of "is it still active right now")
  if (g.speedBoostAmount > 0) return t.baseFillRate + g.speedBoostAmount;
  return t.baseFillRate;
}

function effectiveFillRate(g: GameStateDoc, t: Tunables, now: Date): number {
  const autoUntil = parseIso(g.autoFillUntil);
  if (!autoUntil || autoUntil <= now) return 0;
  return autoFillRate(g, t);
}

function effectiveTapPower(g: GameStateDoc, t: Tunables, now: Date): number {
  let power = t.tapUnits;
  const until = parseIso(g.tapStrengthBoostUntil);
  if (until && until > now && g.tapStrengthBoostAmount > 0) {
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

function refreshAdCycleIfIdle(g: GameStateDoc, now: Date): void {
  const autoUntil = parseIso(g.autoFillUntil);
  const tapUntil = parseIso(g.tapStrengthBoostUntil);
  if ((autoUntil && autoUntil > now) || (tapUntil && tapUntil > now)) return;
  g.autoFillUntil = null;
  g.speedBoostUntil = null;
  g.speedBoostAmount = 0;
  g.tapStrengthBoostUntil = null;
  g.tapStrengthBoostAmount = 0;
  g.adsUsed = 0;
}

function toPublic(g: GameStateDoc, t: Tunables, now: Date): PublicGameState {
  const autoUntil = parseIso(g.autoFillUntil);
  const tapUntil = parseIso(g.tapStrengthBoostUntil);
  let cooldownLeft = 0;
  const lastAd = parseIso(g.lastAdAt);
  if (lastAd) {
    const elapsed = (now.getTime() - lastAd.getTime()) / 1000;
    cooldownLeft = Math.max(0, Math.ceil(t.adCooldownSeconds - elapsed));
  }
  const autoActive = !!(autoUntil && autoUntil > now);
  const tapActive = !!(tapUntil && tapUntil > now && g.tapStrengthBoostAmount > 0);
  const speedActive = autoActive && g.speedBoostAmount > 0;
  return {
    progress: Math.min(g.progress, t.unitsPerSat),
    unitsPerSat: t.unitsPerSat,
    satsBalance: g.satsBalance,
    tapsRemaining: g.tapsRemaining,
    adsRemainingToday: Math.max(0, t.adsPerCycle - g.adsUsed),
    satsEarnedToday: g.satsEarnedToday,
    dailySatsEarnCap: t.dailySatsEarnCap,
    autoFillActive: autoActive,
    autoFillUntil: g.autoFillUntil,
    fillRate: effectiveFillRate(g, t, now),
    speedBoostActive: speedActive,
    // Same shared auto timer — Faster has no separate clock
    speedBoostUntil: autoActive ? g.autoFillUntil : null,
    tapStrengthActive: tapActive,
    tapStrengthUntil: g.tapStrengthBoostUntil,
    tapPower: effectiveTapPower(g, t, now),
    adCooldownSecondsLeft: cooldownLeft,
    lastBoostType: g.lastBoostType,
    minWithdrawSats: t.minWithdrawSats,
    resetHourUtc: t.resetHourUtc,
    updatedAt: g.lastTickAt,
  };
}

type LedgerCredit = { id: string; reason: string };

/** Advance auto-fill in memory only (no writes). */
function advanceInMemory(
  g: GameStateDoc,
  t: Tunables,
  at: Date,
): { earned: number; credits: LedgerCredit[] } {
  resetDaily(g, t, at);
  const credits: LedgerCredit[] = [];
  let earned = 0;

  const last = parseIso(g.lastTickAt) ?? at;
  const autoUntil = parseIso(g.autoFillUntil);
  // Offline catch-up only runs until the shared auto timer — never past autoFillUntil
  if (autoUntil && autoUntil > last) {
    const earnUntil = autoUntil < at ? autoUntil : at;
    const earnSec = Math.max(0, (earnUntil.getTime() - last.getTime()) / 1000);
    const rate = autoFillRate(g, t);
    if (earnSec > 0 && rate > 0) {
      let units = rate * earnSec;
      let progress = g.progress + units;
      while (progress >= t.unitsPerSat) {
        if (g.satsEarnedToday + earned >= t.dailySatsEarnCap) {
          progress = t.unitsPerSat - 0.0001;
          break;
        }
        progress -= t.unitsPerSat;
        earned += 1;
        credits.push({ id: db().collection("_").doc().id, reason: "bar_complete" });
      }
      g.progress = progress;
    }
  }

  const tapUntil = parseIso(g.tapStrengthBoostUntil);
  const autoAlive = !!(autoUntil && autoUntil > at);
  const tapAlive = !!(tapUntil && tapUntil > at);

  if (!autoAlive && !tapAlive) {
    refreshAdCycleIfIdle(g, at);
  } else if (!autoAlive) {
    g.autoFillUntil = null;
    g.speedBoostUntil = null;
    g.speedBoostAmount = 0;
  }
  if (!tapAlive) {
    g.tapStrengthBoostUntil = null;
    g.tapStrengthBoostAmount = 0;
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
  const credits: LedgerCredit[] = [];
  let earned = 0;
  let progress = g.progress + effectiveTapPower(g, t, at);
  while (progress >= t.unitsPerSat) {
    if (g.satsEarnedToday + earned >= t.dailySatsEarnCap) {
      progress = t.unitsPerSat - 0.0001;
      break;
    }
    progress -= t.unitsPerSat;
    earned += 1;
    credits.push({ id: db().collection("_").doc().id, reason: "bar_complete" });
  }
  g.progress = progress;
  g.satsEarnedToday += earned;
  g.satsBalance += earned;
  g.fillRate = effectiveFillRate(g, t, at);
  g.lastTickAt = nowIso(at);
  return credits;
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
    tunables: { ...t, adProvider: "adsbitvex", debugReset: true },
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

    if (g.adsUsed >= t.adsPerCycle) {
      throw Object.assign(new Error("Ad limit reached — wait for boosts to run out"), {
        code: "resource-exhausted",
      });
    }
    const lastAd = parseIso(g.lastAdAt);
    if (lastAd) {
      const elapsed = (now.getTime() - lastAd.getTime()) / 1000;
      if (elapsed < t.adCooldownSeconds) {
        throw Object.assign(new Error("Ad cooldown active"), { code: "resource-exhausted" });
      }
    }

    const autoUntil = parseIso(g.autoFillUntil);
    const idle = !autoUntil || autoUntil <= now;

    if (boostType === "tap_strength") {
      g.tapStrengthBoostAmount = (g.tapStrengthBoostAmount || 0) + t.tapStrengthBoostAmount;
      g.tapStrengthBoostUntil = extendIsoBySeconds(
        g.tapStrengthBoostUntil,
        t.tapStrengthBoostSeconds,
        now,
      );
    } else if (idle) {
      // First Longer/Faster: start shared auto window + base Faster rate
      g.autoFillUntil = extendIsoBySeconds(null, t.durationBoostSeconds, now);
      g.speedBoostAmount = t.speedBoostAmount;
      g.speedBoostUntil = null;
    } else if (boostType === "duration") {
      // Longer: extend the shared auto timer only
      g.autoFillUntil = extendIsoBySeconds(g.autoFillUntil, t.durationBoostSeconds, now);
    } else {
      // Faster: raise rate for the remaining shared auto window (no timer change)
      g.speedBoostAmount = g.speedBoostAmount + t.speedBoostAmount;
    }

    g.adsUsed += 1;
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
