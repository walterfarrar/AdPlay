import "dotenv/config";
import { nanoid } from "nanoid";
import { upsertUser } from "../src/lib/auth.js";
import { applyBoost, getState } from "../src/game/engine.js";
import { getDb } from "../src/db/index.js";

const { userId } = upsertUser({ deviceId: `faster-alone-${Date.now()}` });
let s = applyBoost(userId, "speed", `s_${nanoid()}`);
console.log("faster alone", {
  fillRate: s.fillRate,
  auto: s.autoFillActive,
  speed: s.speedBoostActive,
  amount: (getDb().prepare("SELECT speed_boost_amount, speed_boost_until, auto_fill_until, fill_rate FROM game_state WHERE user_id = ?").get(userId)),
});
s = getState(userId);
console.log("getState", s.fillRate, s.speedBoostActive);
