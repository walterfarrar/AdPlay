import { createHmac, timingSafeEqual } from "crypto";

const DEFAULT_DEV = "dev-admin-token";

export function getAdminToken(): string {
  return (process.env.ADMIN_TOKEN || DEFAULT_DEV).trim();
}

export function isAdminTokenValid(token: string | string[] | undefined | null): boolean {
  const raw = Array.isArray(token) ? token[0] : token;
  if (!raw) return false;
  const expected = getAdminToken();
  const a = Buffer.from(String(raw));
  const b = Buffer.from(expected);
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

/** Signed email action links. Valid for `ttlSec` seconds. */
export type AdminEmailAction = "paid" | "reject" | "refund";

export function signAdminAction(
  action: AdminEmailAction,
  userId: string,
  withdrawalId: string,
  ttlSec = 7 * 24 * 3600,
): { exp: number; sig: string } {
  const exp = Math.floor(Date.now() / 1000) + ttlSec;
  const sig = createHmac("sha256", getAdminToken())
    .update(`${action}:${userId}:${withdrawalId}:${exp}`)
    .digest("hex");
  return { exp, sig };
}

export function verifyAdminAction(
  action: string,
  userId: string,
  withdrawalId: string,
  expRaw: string | undefined,
  sigRaw: string | undefined,
): { ok: true } | { ok: false; error: string } {
  const exp = Number(expRaw);
  if (!Number.isFinite(exp) || exp < Math.floor(Date.now() / 1000)) {
    return { ok: false, error: "Link expired" };
  }
  if (!sigRaw || !userId || !withdrawalId) {
    return { ok: false, error: "Missing signature" };
  }
  if (action !== "paid" && action !== "reject" && action !== "refund") {
    return { ok: false, error: "Invalid action" };
  }
  const expected = createHmac("sha256", getAdminToken())
    .update(`${action}:${userId}:${withdrawalId}:${exp}`)
    .digest("hex");
  const a = Buffer.from(sigRaw);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !timingSafeEqual(a, b)) {
    return { ok: false, error: "Invalid signature" };
  }
  return { ok: true };
}
