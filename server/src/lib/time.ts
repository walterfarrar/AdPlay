import { gameConfig } from "../config/game.js";

/** UTC calendar day key for counters, respecting reset hour. */
export function utcDayKey(date = new Date()): string {
  const shifted = new Date(date.getTime() - gameConfig.resetHourUtc * 3600_000);
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

export function maxIso(a: string | null | undefined, b: Date): string {
  const da = parseIso(a);
  if (!da || da < b) return b.toISOString();
  return da.toISOString();
}

/** Stack time: add `seconds` onto remaining duration (from max(now, existing)). */
export function extendIsoBySeconds(
  existing: string | null | undefined,
  seconds: number,
  now: Date = new Date(),
): string {
  const cur = parseIso(existing);
  const baseMs = cur && cur > now ? cur.getTime() : now.getTime();
  return new Date(baseMs + seconds * 1000).toISOString();
}
