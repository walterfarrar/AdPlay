import { createHmac, timingSafeEqual } from "node:crypto";
import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { nanoid } from "nanoid";
import { getBearerUser } from "../lib/auth.js";
import { applyBoost } from "../game/engine.js";
import type { BoostType } from "../config/game.js";

function s2sSecret() {
  return process.env.AD_S2S_SECRET ?? "change-me-s2s-secret";
}

export function signS2S(payload: string): string {
  return createHmac("sha256", s2sSecret()).update(payload).digest("hex");
}

function verifySig(payload: string, sig: string): boolean {
  const expected = signS2S(payload);
  try {
    const a = Buffer.from(sig);
    const b = Buffer.from(expected);
    return a.length === b.length && timingSafeEqual(a, b);
  } catch {
    return false;
  }
}

const s2sSchema = z.object({
  userId: z.string().min(1),
  boostType: z.enum(["duration", "speed", "tap_strength"]),
  eventId: z.string().min(1),
  ts: z.number().int(),
  sig: z.string().min(1),
});

export async function adRoutes(app: FastifyInstance) {
  /** Partner S2S callback — only this path applies boosts in production. */
  app.post("/ads/s2s", async (req, reply) => {
    const parsed = s2sSchema.safeParse(req.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: parsed.error.flatten() });
    }
    const { userId, boostType, eventId, ts, sig } = parsed.data;
    const ageMs = Math.abs(Date.now() - ts);
    if (ageMs > 10 * 60_000) {
      return reply.code(400).send({ error: "Stale callback" });
    }
    const payload = `${userId}:${boostType}:${eventId}:${ts}`;
    if (!verifySig(payload, sig)) {
      return reply.code(401).send({ error: "Invalid signature" });
    }
    try {
      const state = applyBoost(userId, boostType as BoostType, eventId);
      return { ok: true, state };
    } catch (e) {
      const err = e as Error & { statusCode?: number };
      return reply.code(err.statusCode ?? 500).send({ error: err.message });
    }
  });

  /**
   * Mock rewarded completion for AD_PROVIDER=mock.
   * Client calls this after "watching" a fake ad; server signs and applies via same path.
   */
  app.post("/ads/mock/complete", async (req, reply) => {
    if ((process.env.AD_PROVIDER ?? "mock") !== "mock") {
      return reply.code(403).send({ error: "Mock ads disabled" });
    }
    const user = getBearerUser(req);
    if (!user) return reply.code(401).send({ error: "Unauthorized" });

    const body = z
      .object({ boostType: z.enum(["duration", "speed", "tap_strength"]) })
      .safeParse(req.body);
    if (!body.success) {
      return reply.code(400).send({ error: body.error.flatten() });
    }

    const eventId = `mock_${nanoid()}`;
    const ts = Date.now();
    const boostType = body.data.boostType;
    const payload = `${user.id}:${boostType}:${eventId}:${ts}`;
    const sig = signS2S(payload);

    try {
      const state = applyBoost(user.id, boostType, eventId);
      // Also record as if S2S arrived (already applied). Return mirror of S2S payload for debugging.
      return { ok: true, state, debug: { eventId, ts, sig, payload } };
    } catch (e) {
      const err = e as Error & { statusCode?: number };
      return reply.code(err.statusCode ?? 500).send({ error: err.message });
    }
  });
}
