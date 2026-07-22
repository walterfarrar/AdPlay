import "dotenv/config";
import { nanoid } from "nanoid";
import { upsertUser } from "../src/lib/auth.js";
import { applyBoost } from "../src/game/engine.js";

const { userId } = upsertUser({ deviceId: `stack-${Date.now()}` });
const a = applyBoost(userId, "duration", `d_${nanoid()}`);
console.log("longer", a.fillRate, a.lastBoostType, a.speedBoostActive);
const b = applyBoost(userId, "speed", `s_${nanoid()}`);
console.log("faster stacked", b.fillRate, b.lastBoostType, b.speedBoostActive);
