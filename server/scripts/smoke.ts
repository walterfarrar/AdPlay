import "dotenv/config";
import { upsertUser } from "../src/lib/auth.js";
import { tap, getState, applyBoost } from "../src/game/engine.js";

const { userId, token } = upsertUser({ deviceId: "test-device-1" });
console.log("user", userId, token.slice(0, 24));
let s = tap(userId);
console.log("after tap", {
  progress: s.progress,
  taps: s.tapsRemaining,
  sats: s.satsBalance,
});
s = applyBoost(userId, "duration", "evt1");
console.log("after duration", {
  auto: s.autoFillActive,
  until: s.autoFillUntil,
  rate: s.fillRate,
});
s = applyBoost(userId, "speed", "evt2");
console.log("after speed", {
  speed: s.speedBoostActive,
  rate: s.fillRate,
});
console.log("final", getState(userId));
