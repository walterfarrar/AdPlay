import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { getBearerUser, upsertUser } from "../lib/auth.js";
import { getDb } from "../db/index.js";

const bodySchema = z.object({
  appleSub: z.string().min(1).optional(),
  deviceId: z.string().min(1).optional(),
  displayName: z.string().max(80).optional(),
  /** Identity token from Sign in with Apple — verified in production later */
  identityToken: z.string().optional(),
});

export async function authRoutes(app: FastifyInstance) {
  app.post("/auth/session", async (req, reply) => {
    const parsed = bodySchema.safeParse(req.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: parsed.error.flatten() });
    }
    const { appleSub, deviceId, displayName } = parsed.data;
    if (!appleSub && !deviceId) {
      return reply.code(400).send({ error: "appleSub or deviceId required" });
    }
    const session = upsertUser({ appleSub, deviceId, displayName });
    return { token: session.token, userId: session.userId };
  });

  /** Account deletion for store compliance */
  app.delete("/account", async (req, reply) => {
    const user = getBearerUser(req);
    if (!user) return reply.code(401).send({ error: "Unauthorized" });
    const db = getDb();
    db.exec("BEGIN");
    try {
      db.prepare("DELETE FROM withdrawals WHERE user_id = ?").run(user.id);
      db.prepare("DELETE FROM ad_events WHERE user_id = ?").run(user.id);
      db.prepare("DELETE FROM ledger_entries WHERE user_id = ?").run(user.id);
      db.prepare("DELETE FROM game_state WHERE user_id = ?").run(user.id);
      db.prepare("DELETE FROM users WHERE id = ?").run(user.id);
      db.exec("COMMIT");
    } catch (e) {
      db.exec("ROLLBACK");
      throw e;
    }
    return { ok: true };
  });
}
