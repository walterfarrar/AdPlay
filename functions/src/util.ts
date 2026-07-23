import type { Tunables } from "./types";

export function utcDayKey(resetHourUtc: number, date = new Date()): string {
  const shifted = new Date(date.getTime() - resetHourUtc * 3600_000);
  const y = shifted.getUTCFullYear();
  const m = String(shifted.getUTCMonth() + 1).padStart(2, "0");
  const d = String(shifted.getUTCDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

export function nowIso(date = new Date()): string {
  return date.toISOString();
}

export function parseIso(iso: string | null | undefined): Date | null {
  if (!iso) return null;
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? null : d;
}

export function extendIsoBySeconds(
  existing: string | null | undefined,
  seconds: number,
  now: Date = new Date(),
): string {
  const cur = parseIso(existing);
  const baseMs = cur && cur > now ? cur.getTime() : now.getTime();
  return new Date(baseMs + seconds * 1000).toISOString();
}

export function validateBolt11(invoice: string): { ok: true } | { ok: false; error: string } {
  const raw = invoice.trim().toLowerCase();
  if (!raw) return { ok: false, error: "Invoice is empty" };
  if (raw.includes(" ")) return { ok: false, error: "Invoice must be a single string" };
  if (!(raw.startsWith("lnbc") || raw.startsWith("lntb") || raw.startsWith("lntbs"))) {
    return { ok: false, error: "Invoice must start with lnbc, lntb, or lntbs" };
  }
  if (raw.length < 50) return { ok: false, error: "Invoice looks too short" };
  if (raw.length > 2000) return { ok: false, error: "Invoice looks too long" };
  if (!/^[a-z0-9]+$/.test(raw)) {
    return { ok: false, error: "Invoice has invalid characters" };
  }
  return { ok: true };
}

export function freshGame(t: Tunables, now = new Date()): import("./types").GameStateDoc {
  const day = utcDayKey(t.resetHourUtc, now);
  return {
    progress: 0,
    fillRate: 0,
    autoFillUntil: null,
    speedBoostUntil: null,
    speedBoostAmount: 0,
    tapStrengthBoostUntil: null,
    tapStrengthBoostAmount: 0,
    tapsRemaining: t.dailyTapCap,
    tapDay: day,
    adsUsed: 0,
    skipAdsUsed: 0,
    satsEarnedToday: 0,
    satsDay: day,
    lastAdAt: null,
    lastTickAt: nowIso(now),
    lastBoostType: null,
    satsBalance: 0,
  };
}
