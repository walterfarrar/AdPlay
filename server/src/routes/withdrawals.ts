import type { FastifyInstance } from "fastify";
import { nanoid } from "nanoid";
import { z } from "zod";
import { getBearerUser } from "../lib/auth.js";
import { getDb } from "../db/index.js";
import { validateBolt11 } from "../lib/bolt11.js";
import { gameConfig } from "../config/game.js";
import { getState } from "../game/engine.js";
import { nowIso } from "../lib/time.js";

export async function withdrawalRoutes(app: FastifyInstance) {
  app.get("/withdrawals/mine", async (req, reply) => {
    const user = getBearerUser(req);
    if (!user) return reply.code(401).send({ error: "Unauthorized" });
    const rows = getDb()
      .prepare(
        `SELECT id, amount_sats, bolt11, status, admin_note, created_at, updated_at
         FROM withdrawals WHERE user_id = ? ORDER BY created_at DESC LIMIT 50`,
      )
      .all(user.id);
    return { withdrawals: rows };
  });

  app.post("/withdrawals", async (req, reply) => {
    const user = getBearerUser(req);
    if (!user) return reply.code(401).send({ error: "Unauthorized" });

    const parsed = z
      .object({
        amountSats: z.number().int().positive(),
        bolt11: z.string().min(1),
      })
      .safeParse(req.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: parsed.error.flatten() });
    }

    const invoiceCheck = validateBolt11(parsed.data.bolt11);
    if (!invoiceCheck.ok) {
      return reply.code(400).send({ error: invoiceCheck.error });
    }

    const amount = parsed.data.amountSats;
    if (amount < gameConfig.minWithdrawSats) {
      return reply
        .code(400)
        .send({ error: `Minimum withdrawal is ${gameConfig.minWithdrawSats} sats` });
    }

    const state = getState(user.id);
    if (amount > state.satsBalance) {
      return reply.code(400).send({ error: "Insufficient balance" });
    }

    const pending = getDb()
      .prepare(
        `SELECT COUNT(*) AS c FROM withdrawals WHERE user_id = ? AND status = 'pending'`,
      )
      .get(user.id) as { c: number };
    if (pending.c > 0) {
      return reply.code(400).send({ error: "You already have a pending withdrawal" });
    }

    const id = nanoid();
    const db = getDb();
    db.exec("BEGIN");
    try {
      db.prepare(
        `INSERT INTO withdrawals (id, user_id, amount_sats, bolt11, status)
         VALUES (?, ?, ?, ?, 'pending')`,
      ).run(id, user.id, amount, parsed.data.bolt11.trim());
      db.prepare(
        `INSERT INTO ledger_entries (id, user_id, delta_sats, reason, meta)
         VALUES (?, ?, ?, 'withdraw_hold', ?)`,
      ).run(nanoid(), user.id, -amount, JSON.stringify({ withdrawalId: id }));
      db.exec("COMMIT");
    } catch (e) {
      db.exec("ROLLBACK");
      throw e;
    }

    return {
      withdrawal: {
        id,
        amountSats: amount,
        status: "pending",
      },
      state: getState(user.id),
    };
  });
}

export async function adminRoutes(app: FastifyInstance) {
  app.addHook("preHandler", async (req, reply) => {
    if (!req.url.startsWith("/admin/api")) return;
    const token = req.headers["x-admin-token"];
    if (token !== (process.env.ADMIN_TOKEN ?? "change-me-admin-token")) {
      return reply.code(401).send({ error: "Unauthorized" });
    }
  });

  app.get("/admin/api/withdrawals", async (req) => {
    const status = (req.query as { status?: string }).status ?? "pending";
    const rows = getDb()
      .prepare(
        `SELECT w.*, u.apple_sub, u.display_name
         FROM withdrawals w
         JOIN users u ON u.id = w.user_id
         WHERE w.status = ?
         ORDER BY w.created_at ASC`,
      )
      .all(status);
    return { withdrawals: rows };
  });

  app.post("/admin/api/withdrawals/:id/paid", async (req, reply) => {
    const { id } = req.params as { id: string };
    const note = z
      .object({ note: z.string().max(500).optional() })
      .safeParse(req.body ?? {}).data?.note;

    const db = getDb();
    const row = db
      .prepare("SELECT * FROM withdrawals WHERE id = ?")
      .get(id) as { id: string; status: string } | undefined;
    if (!row) return reply.code(404).send({ error: "Not found" });
    if (row.status !== "pending") {
      return reply.code(400).send({ error: `Already ${row.status}` });
    }

    db.prepare(
      `UPDATE withdrawals SET status = 'paid', admin_note = ?, updated_at = ? WHERE id = ?`,
    ).run(note ?? null, nowIso(), id);

    return { ok: true };
  });

  app.post("/admin/api/withdrawals/:id/reject", async (req, reply) => {
    const { id } = req.params as { id: string };
    const note = z
      .object({ note: z.string().max(500).optional() })
      .safeParse(req.body ?? {}).data?.note;

    const db = getDb();
    const row = db
      .prepare("SELECT * FROM withdrawals WHERE id = ?")
      .get(id) as
      | { id: string; status: string; user_id: string; amount_sats: number }
      | undefined;
    if (!row) return reply.code(404).send({ error: "Not found" });
    if (row.status !== "pending") {
      return reply.code(400).send({ error: `Already ${row.status}` });
    }

    db.exec("BEGIN");
    try {
      db.prepare(
        `UPDATE withdrawals SET status = 'rejected', admin_note = ?, updated_at = ? WHERE id = ?`,
      ).run(note ?? "Rejected", nowIso(), id);
      db.prepare(
        `INSERT INTO ledger_entries (id, user_id, delta_sats, reason, meta)
         VALUES (?, ?, ?, 'withdraw_refund', ?)`,
      ).run(
        nanoid(),
        row.user_id,
        row.amount_sats,
        JSON.stringify({ withdrawalId: id }),
      );
      db.exec("COMMIT");
    } catch (e) {
      db.exec("ROLLBACK");
      throw e;
    }

    return { ok: true };
  });
}
