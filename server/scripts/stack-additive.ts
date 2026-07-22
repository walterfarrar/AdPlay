import "dotenv/config";
import { nanoid } from "nanoid";
import { upsertUser } from "../src/lib/auth.js";
import { applyBoost } from "../src/game/engine.js";
import { getDb } from "../src/db/index.js";

function clearCooldown(userId: string) {
  getDb()
    .prepare(`UPDATE game_state SET last_ad_at = ? WHERE user_id = ?`)
    .run(new Date(Date.now() - 120_000).toISOString(), userId);
}

function leftSec(until: string | null): number {
  if (!until) return 0;
  return Math.round((new Date(until).getTime() - Date.now()) / 1000);
}

const { userId } = upsertUser({ deviceId: `stack2-${Date.now()}` });

let s = applyBoost(userId, "duration", nanoid());
console.log("L1", { rate: s.fillRate, left: leftSec(s.autoFillUntil) });

clearCooldown(userId);
s = applyBoost(userId, "duration", nanoid());
console.log("L2 (expect ~1800s)", { rate: s.fillRate, left: leftSec(s.autoFillUntil) });

s = applyBoost(userId, "speed", nanoid());
console.log("F1 (expect ~3.3)", { rate: s.fillRate });

clearCooldown(userId);
s = applyBoost(userId, "speed", nanoid());
console.log("F2 (expect ~5.6)", { rate: s.fillRate });

clearCooldown(userId);
s = applyBoost(userId, "speed", nanoid());
console.log("F3 (expect ~7.8)", { rate: s.fillRate });
