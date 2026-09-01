import * as admin from "firebase-admin";
import { HttpsError, onCall, onRequest } from "firebase-functions/v2/https";
import { setGlobalOptions } from "firebase-functions/v2";
import { defineSecret } from "firebase-functions/params";
import {
  applyBoost,
  getPublicState,
  loadTunables,
  markPaidRedeem,
  purchaseAdSlot,
  resetEverything,
  deleteAccountData,
  tap,
} from "./game";
import { validateBolt11, nowIso, debugResetAllowed } from "./util";
import { DEFAULT_TUNABLES, BoostType, sanitizeMinerStageThresholds } from "./types";
import { isAdminTokenValid, verifyAdminAction } from "./adminAuth";
import { notifyWithdrawalRequest } from "./mail";

setGlobalOptions({ region: "us-central1", maxInstances: 20 });

const adminTokenSecret = defineSecret("ADMIN_TOKEN");
const gmailUserSecret = defineSecret("GMAIL_USER");
const gmailAppPasswordSecret = defineSecret("GMAIL_APP_PASSWORD");

const mailSecrets = [adminTokenSecret, gmailUserSecret, gmailAppPasswordSecret];
const adminSecrets = [adminTokenSecret];

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

function requireAuth(uid: string | undefined): string {
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required");
  return uid;
}

function mapErr(e: unknown): never {
  const err = e as Error & { code?: string };
  if (err.code === "resource-exhausted") {
    throw new HttpsError("resource-exhausted", err.message);
  }
  if (err.code === "failed-precondition") {
    throw new HttpsError("failed-precondition", err.message);
  }
  if (err.code === "invalid-argument") {
    throw new HttpsError("invalid-argument", err.message);
  }
  throw new HttpsError("internal", err.message || "Error");
}

function requireAdminHeader(req: { get: (n: string) => string | undefined }): boolean {
  return isAdminTokenValid(req.get("x-admin-token"));
}

async function markWithdrawalPaid(
  userId: string,
  withdrawalId: string,
  note: string | null,
): Promise<void> {
  const ref = db.doc(`users/${userId}/withdrawals/${withdrawalId}`);
  const snap = await ref.get();
  if (!snap.exists) throw new Error("Not found");
  if (snap.data()?.status !== "pending") {
    throw new Error(`Already ${snap.data()?.status}`);
  }
  await ref.update({
    status: "paid",
    adminNote: note,
    updatedAt: nowIso(),
  });
  await markPaidRedeem(userId);
}

export const buyAdSlot = onCall(async (request) => {
  const uid = requireAuth(request.auth?.uid);
  const transactionId = String(request.data?.transactionId ?? "");
  try {
    return await purchaseAdSlot(uid, transactionId);
  } catch (e) {
    mapErr(e);
  }
});

async function rejectWithdrawal(
  userId: string,
  withdrawalId: string,
  note: string | null,
): Promise<void> {
  const ref = db.doc(`users/${userId}/withdrawals/${withdrawalId}`);
  const snap = await ref.get();
  if (!snap.exists) throw new Error("Not found");
  if (snap.data()?.status !== "pending") {
    throw new Error(`Already ${snap.data()?.status}`);
  }
  // No balance refund — held sats stay forfeited (fishy / denied payout).
  await ref.update({
    status: "rejected",
    adminNote: note ?? "Rejected",
    updatedAt: nowIso(),
  });
}

async function refundWithdrawal(
  userId: string,
  withdrawalId: string,
  note: string | null,
): Promise<void> {
  const ref = db.doc(`users/${userId}/withdrawals/${withdrawalId}`);
  const gameRef = db.doc(`users/${userId}/game/state`);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new Error("Not found");
    const data = snap.data()!;
    const status = data.status as string;
    if (status !== "pending" && status !== "rejected") {
      throw new Error(`Cannot refund when status is ${status}`);
    }
    const gSnap = await tx.get(gameRef);
    const bal = (gSnap.data()?.satsBalance as number) || 0;
    tx.update(ref, {
      status: "refunded",
      adminNote: note ?? "Refunded",
      updatedAt: nowIso(),
    });
    tx.update(gameRef, { satsBalance: bal + data.amountSats });
    tx.set(db.doc(`users/${userId}/ledger/${withdrawalId}_refund`), {
      deltaSats: data.amountSats,
      reason: "withdraw_refund",
      meta: { withdrawalId },
      createdAt: nowIso(),
    });
  });
}

function htmlPage(title: string, body: string, ok: boolean): string {
  const color = ok ? "#0a7a3e" : "#8a1f1f";
  return `<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title></head>
<body style="font-family:Segoe UI,Arial,sans-serif;max-width:480px;margin:48px auto;padding:0 16px;color:#111">
  <h1 style="color:${color};font-size:22px">${title}</h1>
  <p>${body}</p>
</body></html>`;
}

export const getState = onCall(async (request) => {
  const uid = requireAuth(request.auth?.uid);
  try {
    return await getPublicState(uid);
  } catch (e) {
    mapErr(e);
  }
});

export const gameTap = onCall(async (request) => {
  const uid = requireAuth(request.auth?.uid);
  try {
    return await tap(uid);
  } catch (e) {
    mapErr(e);
  }
});

export const mockCompleteBoost = onCall(async (request) => {
  const uid = requireAuth(request.auth?.uid);
  const boostType = request.data?.boostType as BoostType;
  if (
    boostType !== "activate" &&
    boostType !== "duration" &&
    boostType !== "speed" &&
    boostType !== "tap_strength" &&
    boostType !== "skip_time"
  ) {
    throw new HttpsError(
      "invalid-argument",
      "boostType must be activate|duration|speed|tap_strength|skip_time",
    );
  }
  const eventId = `mock_${db.collection("_").doc().id}`;
  try {
    return await applyBoost(uid, boostType, eventId);
  } catch (e) {
    mapErr(e);
  }
});

export const debugReset = onCall(async (request) => {
  if (!debugResetAllowed()) {
    throw new HttpsError("failed-precondition", "Debug reset disabled");
  }
  const uid = requireAuth(request.auth?.uid);
  try {
    return await resetEverything(uid);
  } catch (e) {
    mapErr(e);
  }
});

/** Authenticated player deletes their own Auth user and all Firestore game data. */
export const deleteAccount = onCall(async (request) => {
  const uid = requireAuth(request.auth?.uid);
  try {
    await deleteAccountData(uid);
  } catch (e) {
    mapErr(e);
  }
  try {
    await admin.auth().deleteUser(uid);
  } catch (e) {
    const err = e as { code?: string; message?: string };
    if (err.code !== "auth/user-not-found") {
      mapErr(e);
    }
  }
  return { ok: true };
});

export const requestWithdrawal = onCall(
  { secrets: mailSecrets },
  async (request) => {
    const uid = requireAuth(request.auth?.uid);
    const amountSats = Number(request.data?.amountSats);
    const bolt11 = String(request.data?.bolt11 ?? "");
    if (!Number.isInteger(amountSats) || amountSats <= 0) {
      throw new HttpsError("invalid-argument", "Invalid amount");
    }
    const check = validateBolt11(bolt11);
    if (!check.ok) throw new HttpsError("invalid-argument", check.error);

    const t = await loadTunables();
    if (amountSats < t.minWithdrawSats) {
      throw new HttpsError(
        "failed-precondition",
        `Minimum withdrawal is ${t.minWithdrawSats} sats`,
      );
    }

    try {
      const { state } = await getPublicState(uid);
      if (amountSats > state.satsBalance) {
        throw new HttpsError("failed-precondition", "Insufficient balance");
      }

      const pending = await db
        .collection(`users/${uid}/withdrawals`)
        .where("status", "==", "pending")
        .limit(1)
        .get();
      if (!pending.empty) {
        throw new HttpsError("failed-precondition", "You already have a pending withdrawal");
      }

      const id = db.collection("_").doc().id;
      const createdAt = nowIso();
      const gameRef = db.doc(`users/${uid}/game/state`);
      await db.runTransaction(async (tx) => {
        const gSnap = await tx.get(gameRef);
        const g = gSnap.data() as { satsBalance: number };
        if (g.satsBalance < amountSats) {
          throw new HttpsError("failed-precondition", "Insufficient balance");
        }
        tx.update(gameRef, { satsBalance: g.satsBalance - amountSats });
        tx.set(db.doc(`users/${uid}/withdrawals/${id}`), {
          amountSats,
          bolt11: bolt11.trim(),
          status: "pending",
          adminNote: null,
          createdAt,
          updatedAt: createdAt,
        });
        tx.set(db.doc(`users/${uid}/ledger/${id}_hold`), {
          deltaSats: -amountSats,
          reason: "withdraw_hold",
          meta: { withdrawalId: id },
          createdAt,
        });
      });

      const out = await getPublicState(uid);
      const [adSnap, ledgerSnap, gameSnap] = await Promise.all([
        db.collection(`users/${uid}/adEvents`).count().get(),
        db.collection(`users/${uid}/ledger`).limit(500).get(),
        gameRef.get(),
      ]);
      const ledgerCreditCount = ledgerSnap.docs.filter(
        (d) => Number(d.data().deltaSats) > 0,
      ).length;
      const adsUsedThisCycle = Number(gameSnap.data()?.adsUsed ?? 0);

      try {
        await notifyWithdrawalRequest({
          userId: uid,
          withdrawalId: id,
          amountSats,
          bolt11: bolt11.trim(),
          satsBalanceAfter: out.state.satsBalance,
          satsEarnedToday: out.state.satsEarnedToday,
          adEventCount: adSnap.data().count,
          adsUsedThisCycle,
          ledgerCreditCount,
          createdAt,
        });
      } catch (mailErr) {
        console.error("Withdraw email failed", mailErr);
      }

      return { withdrawal: { id, amountSats, status: "pending" }, state: out.state };
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      mapErr(e);
    }
  },
);

export const myWithdrawals = onCall(async (request) => {
  const uid = requireAuth(request.auth?.uid);
  const snap = await db
    .collection(`users/${uid}/withdrawals`)
    .orderBy("createdAt", "desc")
    .limit(50)
    .get();
  return {
    withdrawals: snap.docs.map((d) => ({
      id: d.id,
      ...d.data(),
      amount_sats: d.data().amountSats,
    })),
  };
});

/** Seed / refresh server-side tunables (idempotent). */
export const seedTunables = onRequest({ secrets: adminSecrets }, async (req, res) => {
  const token = req.get("x-admin-token") || req.query.token;
  if (!isAdminTokenValid(typeof token === "string" ? token : undefined)) {
    res.status(401).json({ error: "Unauthorized" });
    return;
  }
  const snap = await db.doc("config/tunables").get();
  const existing = snap.exists ? snap.data() ?? {} : {};
  const tunables = {
    ...DEFAULT_TUNABLES,
    ...existing,
    minerStageThresholds: sanitizeMinerStageThresholds(
      (existing as { minerStageThresholds?: unknown }).minerStageThresholds ??
        DEFAULT_TUNABLES.minerStageThresholds,
    ),
  };
  await db.doc("config/tunables").set(tunables);
  res.json({ ok: true, tunables });
});

export const adminListWithdrawals = onRequest({ secrets: adminSecrets }, async (req, res) => {
  if (!requireAdminHeader(req)) {
    res.status(401).json({ error: "Unauthorized" });
    return;
  }
  const status = String(req.query.status || "pending");
  const users = await db.collection("users").limit(200).get();
  const out: unknown[] = [];
  for (const u of users.docs) {
    const w = await db
      .collection(`users/${u.id}/withdrawals`)
      .where("status", "==", status)
      .get();
    w.docs.forEach((d) => {
      out.push({ id: d.id, user_id: u.id, ...d.data() });
    });
  }
  res.json({ withdrawals: out });
});

export const adminMarkPaid = onRequest({ secrets: adminSecrets }, async (req, res) => {
  if (!requireAdminHeader(req)) {
    res.status(401).json({ error: "Unauthorized" });
    return;
  }
  const { userId, withdrawalId, note } = req.body || {};
  if (!userId || !withdrawalId) {
    res.status(400).json({ error: "userId and withdrawalId required" });
    return;
  }
  try {
    await markWithdrawalPaid(userId, withdrawalId, note ?? null);
    res.json({ ok: true });
  } catch (e) {
    const msg = (e as Error).message;
    res.status(msg === "Not found" ? 404 : 400).json({ error: msg });
  }
});

export const adminReject = onRequest({ secrets: adminSecrets }, async (req, res) => {
  if (!requireAdminHeader(req)) {
    res.status(401).json({ error: "Unauthorized" });
    return;
  }
  const { userId, withdrawalId, note } = req.body || {};
  if (!userId || !withdrawalId) {
    res.status(400).json({ error: "userId and withdrawalId required" });
    return;
  }
  try {
    await rejectWithdrawal(userId, withdrawalId, note ?? null);
    res.json({ ok: true });
  } catch (e) {
    const msg = (e as Error).message;
    res.status(msg === "Not found" ? 404 : 400).json({ error: msg });
  }
});

export const adminRefund = onRequest({ secrets: adminSecrets }, async (req, res) => {
  if (!requireAdminHeader(req)) {
    res.status(401).json({ error: "Unauthorized" });
    return;
  }
  const { userId, withdrawalId, note } = req.body || {};
  if (!userId || !withdrawalId) {
    res.status(400).json({ error: "userId and withdrawalId required" });
    return;
  }
  try {
    await refundWithdrawal(userId, withdrawalId, note ?? null);
    res.json({ ok: true });
  } catch (e) {
    const msg = (e as Error).message;
    res.status(msg === "Not found" ? 404 : 400).json({ error: msg });
  }
});

/**
 * One-click Mark paid / Reject / Refund from the redeem notification email.
 * Auth: HMAC signed query (exp + sig), not the raw admin token in the URL.
 */
export const adminEmailAction = onRequest({ secrets: adminSecrets }, async (req, res) => {
  const action = String(req.query.action || "");
  const userId = String(req.query.userId || "");
  const withdrawalId = String(req.query.withdrawalId || "");
  const check = verifyAdminAction(
    action,
    userId,
    withdrawalId,
    typeof req.query.exp === "string" ? req.query.exp : undefined,
    typeof req.query.sig === "string" ? req.query.sig : undefined,
  );
  if (!check.ok) {
    res.status(403).send(htmlPage("Link invalid", check.error, false));
    return;
  }
  try {
    if (action === "paid") {
      await markWithdrawalPaid(userId, withdrawalId, "Marked paid via email");
      res
        .status(200)
        .send(
          htmlPage(
            "Marked paid",
            `Withdrawal <code>${withdrawalId}</code> for user <code>${userId}</code> is now paid.`,
            true,
          ),
        );
      return;
    }
    if (action === "reject") {
      await rejectWithdrawal(userId, withdrawalId, "Rejected via email");
      res
        .status(200)
        .send(
          htmlPage(
            "Rejected",
            `Withdrawal <code>${withdrawalId}</code> was rejected. Held sats were <strong>not</strong> returned.`,
            true,
          ),
        );
      return;
    }
    await refundWithdrawal(userId, withdrawalId, "Refunded via email");
    res
      .status(200)
      .send(
        htmlPage(
          "Refunded",
          `Withdrawal <code>${withdrawalId}</code> was refunded; sats returned to the player.`,
          true,
        ),
      );
  } catch (e) {
    const msg = (e as Error).message;
    res.status(400).send(htmlPage("Could not update", msg, false));
  }
});
