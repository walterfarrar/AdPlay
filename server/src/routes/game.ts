import type { FastifyInstance } from "fastify";
import { getBearerUser } from "../lib/auth.js";
import { getState, resetEverything, tap } from "../game/engine.js";
import { gameConfig } from "../config/game.js";

function debugResetAllowed(): boolean {
  const provider = process.env.AD_PROVIDER ?? "mock";
  return provider === "mock" || process.env.DEBUG_RESET === "1";
}

export async function gameRoutes(app: FastifyInstance) {
  app.get("/game/state", async (req, reply) => {
    const user = getBearerUser(req);
    if (!user) return reply.code(401).send({ error: "Unauthorized" });
    return { state: getState(user.id), tunables: publicTunables() };
  });

  app.post("/game/tap", async (req, reply) => {
    const user = getBearerUser(req);
    if (!user) return reply.code(401).send({ error: "Unauthorized" });
    try {
      return { state: tap(user.id) };
    } catch (e) {
      const err = e as Error & { statusCode?: number };
      return reply.code(err.statusCode ?? 500).send({ error: err.message });
    }
  });

  /** Wipe this user's game/ledger/ads/withdrawals. Mock/dev only. */
  app.post("/game/debug/reset", async (req, reply) => {
    if (!debugResetAllowed()) {
      return reply.code(403).send({ error: "Debug reset disabled" });
    }
    const user = getBearerUser(req);
    if (!user) return reply.code(401).send({ error: "Unauthorized" });
    return { state: resetEverything(user.id), tunables: publicTunables() };
  });
}

function publicTunables() {
  return {
    unitsPerSat: gameConfig.unitsPerSat,
    tapUnits: gameConfig.tapUnits,
    dailyTapCap: gameConfig.dailyTapCap,
    durationBoostSeconds: gameConfig.durationBoostSeconds,
    speedBoostAmount: gameConfig.speedBoostAmount,
    speedBoostSeconds: gameConfig.speedBoostSeconds,
    tapStrengthBoostAmount: gameConfig.tapStrengthBoostAmount,
    tapStrengthBoostSeconds: gameConfig.tapStrengthBoostSeconds,
    adCooldownSeconds: gameConfig.adCooldownSeconds,
    dailyAdCap: gameConfig.adsPerCycle,
    adsPerCycle: gameConfig.adsPerCycle,
    dailySatsEarnCap: gameConfig.dailySatsEarnCap,
    minWithdrawSats: gameConfig.minWithdrawSats,
    resetHourUtc: gameConfig.resetHourUtc,
    adProvider: process.env.AD_PROVIDER ?? "mock",
    debugReset: debugResetAllowed(),
  };
}
