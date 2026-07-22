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

function left(until: string | null) {
  if (!until) return 0;
  return Math.round((new Date(until).getTime() - Date.now()) / 1000);
}

const { userId } = upsertUser({ deviceId: `first-${Date.now()}` });
let s = applyBoost(userId, "speed", nanoid());
console.log("first Faster", { rate: s.fillRate, left: left(s.autoFillUntil) });

clearCooldown(userId);
s = applyBoost(userId, "duration", nanoid());
console.log("then Longer", { rate: s.fillRate, left: left(s.autoFillUntil) });

clearCooldown(userId);
s = applyBoost(userId, "speed", nanoid());
console.log("then Faster", { rate: s.fillRate, left: left(s.autoFillUntil) });
