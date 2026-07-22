import "dotenv/config";
import { nanoid } from "nanoid";
import { upsertUser } from "../src/lib/auth.js";
import { applyBoost, getState } from "../src/game/engine.js";
import { getDb } from "../src/db/index.js";

const { userId } = upsertUser({ deviceId: `faster-debug-${Date.now()}` });
let s = applyBoost(userId, "duration", `d_${nanoid()}`);
console.log("after longer", {
  fillRate: s.fillRate,
  auto: s.autoFillActive,
  speed: s.speedBoostActive,
});
s = applyBoost(userId, "speed", `s_${nanoid()}`);
console.log("after faster", {
  fillRate: s.fillRate,
  auto: s.autoFillActive,
  speed: s.speedBoostActive,
  speedUntil: s.speedBoostUntil,
});
const row = getDb().prepare("SELECT * FROM game_state WHERE user_id = ?").get(userId);
console.log("db row", row);
s = getState(userId);
console.log("getState", { fillRate: s.fillRate, speed: s.speedBoostActive });
