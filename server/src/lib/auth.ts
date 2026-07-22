import { createHmac, timingSafeEqual } from "node:crypto";
import { nanoid } from "nanoid";
import type { FastifyRequest } from "fastify";
import { getDb } from "../db/index.js";
import { gameConfig } from "../config/game.js";
import { nowIso, utcDayKey } from "./time.js";

const secret = () => process.env.JWT_DEV_SECRET ?? "dev-secret";

export type SessionUser = { id: string; appleSub: string | null };

function sign(payload: string): string {
  return createHmac("sha256", secret()).update(payload).digest("base64url");
}

export function issueToken(userId: string): string {
  const body = Buffer.from(JSON.stringify({ sub: userId, iat: Date.now() })).toString(
    "base64url",
  );
  return `${body}.${sign(body)}`;
}

export function verifyToken(token: string): string | null {
  const [body, sig] = token.split(".");
  if (!body || !sig) return null;
  const expected = sign(body);
  try {
    const a = Buffer.from(sig);
    const b = Buffer.from(expected);
    if (a.length !== b.length || !timingSafeEqual(a, b)) return null;
  } catch {
    return null;
  }
  try {
    const parsed = JSON.parse(Buffer.from(body, "base64url").toString("utf8")) as {
      sub?: string;
    };
    return parsed.sub ?? null;
  } catch {
    return null;
  }
}

export function getBearerUser(req: FastifyRequest): SessionUser | null {
  const header = req.headers.authorization;
  if (!header?.startsWith("Bearer ")) return null;
  const userId = verifyToken(header.slice(7));
  if (!userId) return null;
  const row = getDb()
    .prepare("SELECT id, apple_sub FROM users WHERE id = ?")
    .get(userId) as { id: string; apple_sub: string | null } | undefined;
  if (!row) return null;
  return { id: row.id, appleSub: row.apple_sub };
}

/** Dev / TestFlight: create or fetch user by Apple sub, or anonymous device id. */
export function upsertUser(opts: {
  appleSub?: string;
  deviceId?: string;
  displayName?: string;
}): { userId: string; token: string } {
  const db = getDb();
  if (opts.appleSub) {
    const existing = db
      .prepare("SELECT id FROM users WHERE apple_sub = ?")
      .get(opts.appleSub) as { id: string } | undefined;
    if (existing) {
      return { userId: existing.id, token: issueToken(existing.id) };
    }
    const id = nanoid();
    db.prepare(
      "INSERT INTO users (id, apple_sub, display_name) VALUES (?, ?, ?)",
    ).run(id, opts.appleSub, opts.displayName ?? null);
    ensureGameState(id);
    return { userId: id, token: issueToken(id) };
  }

  const deviceKey = opts.deviceId ?? nanoid();
  const appleSub = `dev:${deviceKey}`;
  const existing = db
    .prepare("SELECT id FROM users WHERE apple_sub = ?")
    .get(appleSub) as { id: string } | undefined;
  if (existing) {
    return { userId: existing.id, token: issueToken(existing.id) };
  }
  const id = nanoid();
  db.prepare(
    "INSERT INTO users (id, apple_sub, display_name) VALUES (?, ?, ?)",
  ).run(id, appleSub, opts.displayName ?? "Player");
  ensureGameState(id);
  return { userId: id, token: issueToken(id) };
}

export function ensureGameState(userId: string): void {
  const db = getDb();
  const row = db.prepare("SELECT user_id FROM game_state WHERE user_id = ?").get(userId);
  if (row) return;
  const day = utcDayKey();
  db.prepare(
    `INSERT INTO game_state (
      user_id, progress, fill_rate, taps_remaining, tap_day,
      ads_used_today, ads_day, sats_earned_today, sats_day, last_tick_at
    ) VALUES (?, 0, 0, ?, ?, 0, ?, 0, ?, ?)`,
  ).run(userId, gameConfig.dailyTapCap, day, day, day, nowIso());
}
