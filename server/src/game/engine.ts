import { nanoid } from "nanoid";
import { getDb } from "../db/index.js";
import { gameConfig, type BoostType } from "../config/game.js";
import { nowIso, parseIso, utcDayKey, extendIsoBySeconds } from "../lib/time.js";

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
  /** True only after the player watched a Faster ad this cycle. */
  speedBoostActive: boolean;
  speedBoostUntil: string | null;
  /** True only after the player watched a Longer ad this cycle. */
  durationBoostActive: boolean;
  durationBoostCount: number;
  speedBoostCount: number;
  tapStrengthBoostCount: number;
  tapStrengthActive: boolean;
  tapStrengthUntil: string | null;
  tapPower: number;
  adCooldownSecondsLeft: number;
  /** Most recent boost; used so the other type can be watched during cooldown. */
  lastBoostType: BoostType | null;
  minWithdrawSats: number;
  resetHourUtc: number;
};

type GameRow = {
  user_id: string;
  progress: number;
  fill_rate: number;
  auto_fill_until: string | null;
  speed_boost_until: string | null;
  speed_boost_amount: number;
  tap_strength_boost_until: string | null;
  tap_strength_boost_amount: number;
  duration_boost_count: number;
  speed_boost_count: number;
  tap_strength_boost_count: number;
  taps_remaining: number;
  tap_day: string;
  ads_used_today: number;
  ads_day: string;
  sats_earned_today: number;
  sats_day: string;
  last_ad_at: string | null;
  last_tick_at: string;
};

function getBalance(userId: string): number {
  const row = getDb()
    .prepare(
      "SELECT COALESCE(SUM(delta_sats), 0) AS balance FROM ledger_entries WHERE user_id = ?",
    )
    .get(userId) as { balance: number };
  return Number(row.balance);
}

function creditSat(userId: string, count: number, meta?: Record<string, unknown>): void {
  if (count <= 0) return;
  const db = getDb();
  const insert = db.prepare(
    "INSERT INTO ledger_entries (id, user_id, delta_sats, reason, meta) VALUES (?, ?, 1, 'bar_complete', ?)",
  );
  for (let i = 0; i < count; i++) {
    insert.run(nanoid(), userId, meta ? JSON.stringify(meta) : null);
  }
}

function loadRow(userId: string): GameRow {
  const row = getDb()
    .prepare("SELECT * FROM game_state WHERE user_id = ?")
    .get(userId) as GameRow & {
      duration_boost_applied?: number;
      speed_boost_applied?: number;
    };
  if (!row) throw new Error("game_state missing");
  if (row.duration_boost_count == null) {
    row.duration_boost_count = row.duration_boost_applied ? 1 : 0;
  }
  if (row.speed_boost_count == null) {
    row.speed_boost_count = row.speed_boost_applied ? 1 : 0;
  }
  if (row.tap_strength_boost_count == null) {
    row.tap_strength_boost_count = row.tap_strength_boost_amount > 0 ? 1 : 0;
  }
  return row;
}

function saveRow(row: GameRow): void {
  getDb()
    .prepare(
      `UPDATE game_state SET
        progress = ?, fill_rate = ?, auto_fill_until = ?, speed_boost_until = ?,
        speed_boost_amount = ?, tap_strength_boost_until = ?, tap_strength_boost_amount = ?,
        duration_boost_count = ?, speed_boost_count = ?, tap_strength_boost_count = ?,
        taps_remaining = ?, tap_day = ?,
        ads_used_today = ?, ads_day = ?, sats_earned_today = ?, sats_day = ?,
        last_ad_at = ?, last_tick_at = ?, updated_at = ?
      WHERE user_id = ?`,
    )
    .run(
      row.progress,
      row.fill_rate,
      row.auto_fill_until,
      row.speed_boost_until,
      row.speed_boost_amount,
      row.tap_strength_boost_until,
      row.tap_strength_boost_amount,
      row.duration_boost_count || 0,
      row.speed_boost_count || 0,
      row.tap_strength_boost_count || 0,
      row.taps_remaining,
      row.tap_day,
      row.ads_used_today,
      row.ads_day,
      row.sats_earned_today,
      row.sats_day,
      row.last_ad_at,
      row.last_tick_at,
      nowIso(),
      row.user_id,
    );
}

function resetDailyCounters(row: GameRow, now: Date): void {
  const day = utcDayKey(now);
  if (row.tap_day !== day) {
    row.tap_day = day;
    row.taps_remaining = gameConfig.dailyTapCap;
  }
  // Ads are not UTC-daily — see refreshAdCycleIfIdle
  if (row.sats_day !== day) {
    row.sats_day = day;
    row.sats_earned_today = 0;
  }
}

/** When the shared auto window is gone, clear boosts and refill ads. */
function refreshAdCycleIfIdle(row: GameRow, now: Date): void {
  const autoUntil = parseIso(row.auto_fill_until);
  if (autoUntil && autoUntil > now) return;

  row.auto_fill_until = null;
  row.speed_boost_until = null;
  row.speed_boost_amount = 0;
  row.tap_strength_boost_until = null;
  row.tap_strength_boost_amount = 0;
  row.duration_boost_count = 0;
  row.speed_boost_count = 0;
  row.tap_strength_boost_count = 0;
  row.ads_used_today = 0;
}

function autoFillRate(row: GameRow): number {
  if (row.speed_boost_amount > 0) return gameConfig.baseFillRate + row.speed_boost_amount;
  return gameConfig.baseFillRate;
}

function effectiveFillRate(row: GameRow, now: Date): number {
  const autoUntil = parseIso(row.auto_fill_until);
  if (!autoUntil || autoUntil <= now) return 0;
  return autoFillRate(row) * effectiveTapPower(row, now);
}

function effectiveTapPower(row: GameRow, now: Date): number {
  let power = gameConfig.tapUnits;
  const autoUntil = parseIso(row.auto_fill_until);
  if (autoUntil && autoUntil > now && row.tap_strength_boost_amount > 0) {
    power += row.tap_strength_boost_amount;
  }
  return power;
}

/** Advance progress from last_tick_at → now; credit sats for full bars. */
export function tickUser(userId: string, at = new Date()): PublicGameState {
  const row = loadRow(userId);
  resetDailyCounters(row, at);

  const last = parseIso(row.last_tick_at) ?? at;
  const autoUntil = parseIso(row.auto_fill_until);
  // Offline catch-up only until shared auto timer — never past auto_fill_until
  if (autoUntil && autoUntil > last) {
    const earnUntil = autoUntil < at ? autoUntil : at;
    const earnSec = Math.max(0, (earnUntil.getTime() - last.getTime()) / 1000);
    const rate = autoFillRate(row) * effectiveTapPower(row, earnUntil);
    if (earnSec > 0 && rate > 0) {
      let units = rate * earnSec;
      let progress = row.progress + units;
      let earned = 0;

      while (progress >= gameConfig.unitsPerSat) {
        if (row.sats_earned_today + earned >= gameConfig.dailySatsEarnCap) {
          progress = gameConfig.unitsPerSat - 0.0001;
          break;
        }
        progress -= gameConfig.unitsPerSat;
        earned += 1;
      }

      if (earned > 0) {
        creditSat(userId, earned);
        row.sats_earned_today += earned;
      }
      row.progress = progress;
    }
  }

  // Clear expired boosts / refill ad cycle when shared auto is done
  const autoAlive = !!(autoUntil && autoUntil > at);
  if (!autoAlive) {
    refreshAdCycleIfIdle(row, at);
  } else if (row.tap_strength_boost_amount > 0) {
    row.tap_strength_boost_until = row.auto_fill_until;
  }

  row.fill_rate = effectiveFillRate(row, at);
  row.last_tick_at = nowIso(at);
  saveRow(row);
  return toPublic(userId, row, at);
}

function toPublic(userId: string, row: GameRow, now: Date): PublicGameState {
  const autoUntil = parseIso(row.auto_fill_until);
  let cooldownLeft = 0;
  const lastAd = parseIso(row.last_ad_at);
  if (lastAd) {
    const elapsed = (now.getTime() - lastAd.getTime()) / 1000;
    cooldownLeft = Math.max(0, Math.ceil(gameConfig.adCooldownSeconds - elapsed));
  }

  const lastBoost = getDb()
    .prepare(
      `SELECT boost_type FROM ad_events WHERE user_id = ? ORDER BY applied_at DESC, rowid DESC LIMIT 1`,
    )
    .get(userId) as { boost_type: string } | undefined;

  const autoActive = !!(autoUntil && autoUntil > now);
  const durationCount = row.duration_boost_count || 0;
  const speedCount = row.speed_boost_count || 0;
  const tapCount = row.tap_strength_boost_count || 0;
  const tapActive = autoActive && row.tap_strength_boost_amount > 0;
  const speedActive = autoActive && speedCount > 0;
  const durationActive = autoActive && durationCount > 0;

  return {
    progress: Math.min(row.progress, gameConfig.unitsPerSat),
    unitsPerSat: gameConfig.unitsPerSat,
    satsBalance: getBalance(userId),
    tapsRemaining: row.taps_remaining,
    adsRemainingToday: Math.max(0, gameConfig.adsPerCycle - row.ads_used_today),
    satsEarnedToday: row.sats_earned_today,
    dailySatsEarnCap: gameConfig.dailySatsEarnCap,
    autoFillActive: autoActive,
    autoFillUntil: row.auto_fill_until,
    fillRate: effectiveFillRate(row, now),
    speedBoostActive: speedActive,
    speedBoostUntil: autoActive ? row.auto_fill_until : null,
    durationBoostActive: durationActive,
    durationBoostCount: durationCount,
    speedBoostCount: speedCount,
    tapStrengthBoostCount: tapCount,
    tapStrengthActive: tapActive,
    tapStrengthUntil: tapActive ? row.auto_fill_until : null,
    tapPower: effectiveTapPower(row, now),
    adCooldownSecondsLeft: cooldownLeft,
    lastBoostType:
      lastBoost?.boost_type === "duration" ||
      lastBoost?.boost_type === "speed" ||
      lastBoost?.boost_type === "tap_strength"
        ? lastBoost.boost_type
        : null,
    minWithdrawSats: gameConfig.minWithdrawSats,
    resetHourUtc: gameConfig.resetHourUtc,
  };
}

export function tap(userId: string): PublicGameState {
  const now = new Date();
  tickUser(userId, now);
  const row = loadRow(userId);
  resetDailyCounters(row, now);

  if (row.taps_remaining <= 0) {
    saveRow(row);
    throw Object.assign(new Error("No taps remaining today"), { statusCode: 429 });
  }

  row.taps_remaining -= 1;
  let progress = row.progress + effectiveTapPower(row, now);
  let earned = 0;

  while (progress >= gameConfig.unitsPerSat) {
    if (row.sats_earned_today + earned >= gameConfig.dailySatsEarnCap) {
      progress = gameConfig.unitsPerSat - 0.0001;
      break;
    }
    progress -= gameConfig.unitsPerSat;
    earned += 1;
  }
  if (earned > 0) {
    creditSat(userId, earned, { source: "tap" });
    row.sats_earned_today += earned;
  }
  row.progress = progress;
  row.last_tick_at = nowIso(now);
  row.fill_rate = effectiveFillRate(row, now);
  saveRow(row);
  return toPublic(userId, row, now);
}

export function applyBoost(
  userId: string,
  boostType: BoostType,
  eventId: string,
): PublicGameState {
  const db = getDb();
  const existing = db
    .prepare("SELECT id FROM ad_events WHERE event_id = ?")
    .get(eventId) as { id: string } | undefined;
  if (existing) {
    return tickUser(userId);
  }

  const now = new Date();
  tickUser(userId, now);
  const row = loadRow(userId);
  resetDailyCounters(row, now);

  if (row.ads_used_today >= gameConfig.adsPerCycle) {
    throw Object.assign(
      new Error("Ad limit reached — wait for auto time to run out"),
      { statusCode: 429 },
    );
  }

  const lastAd = parseIso(row.last_ad_at);
  if (lastAd) {
    const elapsed = (now.getTime() - lastAd.getTime()) / 1000;
    if (elapsed < gameConfig.adCooldownSeconds) {
      throw Object.assign(new Error("Ad cooldown active"), { statusCode: 429 });
    }
  }

  const autoUntil = parseIso(row.auto_fill_until);
  const idle = !autoUntil || autoUntil <= now;

  if (boostType === "tap_strength") {
    // Like Faster: if auto is empty, start the shared window + base rate
    if (idle) {
      row.auto_fill_until = extendIsoBySeconds(
        null,
        gameConfig.durationBoostSeconds,
        now,
      );
      row.speed_boost_amount = gameConfig.speedBoostAmount;
      row.speed_boost_until = null;
    }
    row.tap_strength_boost_amount =
      (row.tap_strength_boost_amount || 0) + gameConfig.tapStrengthBoostAmount;
    row.tap_strength_boost_count = (row.tap_strength_boost_count || 0) + 1;
    row.tap_strength_boost_until = row.auto_fill_until;
  } else if (idle) {
    // First Longer/Faster: shared auto window + base Faster rate
    row.auto_fill_until = extendIsoBySeconds(
      null,
      gameConfig.durationBoostSeconds,
      now,
    );
    row.speed_boost_amount = gameConfig.speedBoostAmount;
    row.speed_boost_until = null;
    if (boostType === "duration") {
      row.duration_boost_count = (row.duration_boost_count || 0) + 1;
    } else {
      row.speed_boost_count = (row.speed_boost_count || 0) + 1;
    }
  } else if (boostType === "duration") {
    row.auto_fill_until = extendIsoBySeconds(
      row.auto_fill_until,
      gameConfig.durationBoostSeconds,
      now,
    );
    row.duration_boost_count = (row.duration_boost_count || 0) + 1;
    if (row.tap_strength_boost_amount > 0) {
      row.tap_strength_boost_until = row.auto_fill_until;
    }
  } else {
    // Faster: rate only — does not change the shared auto timer
    row.speed_boost_amount = row.speed_boost_amount + gameConfig.speedBoostAmount;
    row.speed_boost_count = (row.speed_boost_count || 0) + 1;
  }

  row.ads_used_today += 1;
  row.last_ad_at = nowIso(now);
  row.fill_rate = effectiveFillRate(row, now);
  row.last_tick_at = nowIso(now);
  saveRow(row);

  db.prepare(
    "INSERT INTO ad_events (id, user_id, event_id, boost_type, applied_at) VALUES (?, ?, ?, ?, ?)",
  ).run(nanoid(), userId, eventId, boostType, nowIso(now));

  return toPublic(userId, row, now);
}

export function getState(userId: string): PublicGameState {
  return tickUser(userId);
}

/** Dev helper: wipe progress, boosts, ledger, ads, withdrawals for this user. */
export function resetEverything(userId: string): PublicGameState {
  const db = getDb();
  const day = utcDayKey();
  const now = nowIso();

  db.exec("BEGIN");
  try {
    db.prepare("DELETE FROM ledger_entries WHERE user_id = ?").run(userId);
    db.prepare("DELETE FROM ad_events WHERE user_id = ?").run(userId);
    db.prepare("DELETE FROM withdrawals WHERE user_id = ?").run(userId);
    db.prepare(
      `UPDATE game_state SET
        progress = 0,
        fill_rate = 0,
        auto_fill_until = NULL,
        speed_boost_until = NULL,
        speed_boost_amount = 0,
        tap_strength_boost_until = NULL,
        tap_strength_boost_amount = 0,
        duration_boost_count = 0,
        speed_boost_count = 0,
        tap_strength_boost_count = 0,
        taps_remaining = ?,
        tap_day = ?,
        ads_used_today = 0,
        ads_day = ?,
        sats_earned_today = 0,
        sats_day = ?,
        last_ad_at = NULL,
        last_tick_at = ?,
        updated_at = ?
      WHERE user_id = ?`,
    ).run(
      gameConfig.dailyTapCap,
      day,
      day,
      day,
      now,
      now,
      userId,
    );
    db.exec("COMMIT");
  } catch (e) {
    db.exec("ROLLBACK");
    throw e;
  }

  return getState(userId);
}
