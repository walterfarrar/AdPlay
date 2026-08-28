/** Manual-tap odometer combo. Keep in lockstep with iOS `ComboEngine.swift`,
 *  Android `Combo.kt`, and `web/app.js`.
 *
 *  One tap counter. Rings are place-value digits:
 *    ring 0 fills every C0 taps, then ticks ring 1, then ring 2.
 *  Never applied to Auto Tapper, Skip Time, or offline catch-up — live taps only.
 */

export const RING_COUNT = 3;

export type ComboParams = {
  /** Taps to fill one outermost (ring 0) cycle. */
  comboTapsPerLevel: number;
  /** Multiplier added each non-overflow ring complete (1.0 → 1.1 → 1.2 …). */
  comboStep: number;
  /** Starting multiplier with no rings completed. */
  comboBase: number;
  /** Hard cap on the live-tap multiplier. */
  comboAbsMax: number;
  /** How many outer completes fill ring 1 (max / step). */
  comboRing0Max: number;
  comboRing1Max: number;
  comboRing2Max: number;
  /** Seconds after a tap before idle drain kicks in. */
  comboIdleGraceSeconds: number;
  /** Unused. Kept so existing Firestore docs still merge. */
  comboDrainPerSecondActive: number;
  /** Outer-ring units drained per second after the grace window. */
  comboDrainPerSecondIdle: number;
};

export const DEFAULT_COMBO: ComboParams = {
  comboTapsPerLevel: 100,
  comboStep: 0.1,
  comboBase: 1.0,
  comboAbsMax: 3.0,
  comboRing0Max: 1.0,
  comboRing1Max: 1.0,
  comboRing2Max: 1.0,
  comboIdleGraceSeconds: 1.5,
  comboDrainPerSecondActive: 0.002,
  comboDrainPerSecondIdle: 0.5,
};

export type ComboCaps = {
  c0: number;
  c1: number;
  c2: number;
  /** maxLevels(ring 2); 0 if ring 2 is off. */
  ml2: number;
  maxTaps: number;
  ring1Enabled: boolean;
  ring2Enabled: boolean;
};

export type ComboState = {
  taps: number;
  lastTapAtMs: number | null;
};

export type ComboPersist = {
  comboTaps: number;
  comboMeter: number;
  comboLevel: number;
  comboContrib: number;
  comboMeter1: number;
  comboLevel1: number;
  comboContrib1: number;
  comboMeter2: number;
  comboLevel2: number;
  comboContrib2: number;
};

export function emptyCombo(): ComboState {
  return { taps: 0, lastTapAtMs: null };
}

function nice(n: number): number {
  return Math.round(n * 1e8) / 1e8;
}

function clamp01(n: number): number {
  if (!Number.isFinite(n) || n <= 0) return 0;
  if (n >= 1) return 1;
  return n;
}

function clampInt(n: number, lo: number, hi: number): number {
  if (!Number.isFinite(n)) return lo;
  const x = Math.trunc(n);
  if (x < lo) return lo;
  if (x > hi) return hi;
  return x;
}

function stepOf(t: ComboParams): number {
  return t.comboStep > 0 && Number.isFinite(t.comboStep) ? t.comboStep : 0.1;
}

function posMod(a: number, b: number): number {
  if (!(b > 0) || !Number.isFinite(a)) return 0;
  const r = a % b;
  return r < 0 ? r + b : r;
}

export function comboCaps(t: ComboParams): ComboCaps {
  const step = stepOf(t);
  const c0 = clampInt(t.comboTapsPerLevel, 1, 10000);
  const raw1 = Math.round(Math.max(0, Number(t.comboRing0Max) || 0) / step);
  const raw2 = Math.round(Math.max(0, Number(t.comboRing1Max) || 0) / step);
  const ring1Enabled = clampInt(raw1, 0, 100) > 0;
  const ring2Enabled =
    clampInt(raw2, 0, 100) > 0 && (Number(t.comboRing2Max) || 0) > 0;
  const c1 = ring1Enabled ? clampInt(raw1, 1, 100) : 1;
  const c2 = ring2Enabled ? clampInt(raw2, 1, 100) : 1;
  const raw3 = Math.round(Math.max(0, Number(t.comboRing2Max) || 0) / step);
  const ml2 = ring2Enabled ? clampInt(raw3, 1, 100) : 0;
  return {
    c0,
    c1,
    c2,
    ml2,
    maxTaps: c0 * c1 * c2,
    ring1Enabled,
    ring2Enabled,
  };
}

export function clampTaps(taps: number, t: ComboParams): number {
  const max = comboCaps(t).maxTaps;
  if (!Number.isFinite(taps) || taps <= 0) return 0;
  return taps >= max ? max : taps;
}

export function normalizeCombo(state: ComboState, t: ComboParams): ComboState {
  const last = state?.lastTapAtMs;
  return {
    taps: clampTaps(state?.taps ?? 0, t),
    lastTapAtMs: typeof last === "number" && Number.isFinite(last) ? last : null,
  };
}

/** Prefer `comboTaps`. Else reconstruct from ring-0 level + meter (old docs). */
export function tapsFromPersisted(
  comboTaps: number | null | undefined,
  comboLevel: number,
  comboMeter: number,
  t: ComboParams,
): number {
  if (typeof comboTaps === "number" && Number.isFinite(comboTaps)) {
    return clampTaps(comboTaps, t);
  }
  const c0 = comboCaps(t).c0;
  const level = Number.isFinite(comboLevel) ? Math.max(0, Math.floor(comboLevel)) : 0;
  return clampTaps(level * c0 + clamp01(comboMeter) * c0, t);
}

/**
 * Nested contribution + overflow, closed-form from outer completes.
 * Ring 0: +step until its cap, then overflow 0.01 / 0.001 / 0.0001 as
 * inner rings max. Each outer complete also ticks ring 1; ring 1 ticks ring 2.
 * Same sum as the old cascade engine, without peel loops.
 */
export function ringContributions(laps: number, t: ComboParams): [number, number, number] {
  const caps = comboCaps(t);
  const step = stepOf(t);
  const L = Number.isFinite(laps) && laps > 0 ? Math.floor(laps) : 0;
  if (L <= 0) return [0, 0, 0];

  const ml0 = caps.c1;
  const ml1 = caps.c2;
  const ml2 = caps.ml2;
  const ov = (innerMaxed: number) => nice(step / Math.pow(10, 1 + Math.max(0, innerMaxed)));

  const r1Levels = caps.ring1Enabled ? Math.floor(L / caps.c1) : 0;
  const r2Levels = caps.ring2Enabled ? Math.floor(L / (caps.c1 * caps.c2)) : 0;

  const r0Max1 = caps.ring1Enabled ? caps.c1 * ml1 : Number.POSITIVE_INFINITY;
  const r0Max2 =
    caps.ring2Enabled && ml2 > 0 ? caps.c1 * caps.c2 * ml2 : Number.POSITIVE_INFINITY;
  const c0 = ringBonus(L, ml0, step, [
    { until: r0Max1, innerMaxed: 0 },
    { until: r0Max2, innerMaxed: 1 },
    { until: Number.POSITIVE_INFINITY, innerMaxed: 2 },
  ], ov);

  const r1Max2 =
    caps.ring2Enabled && ml2 > 0 ? ml1 * ml2 : Number.POSITIVE_INFINITY;
  const c1 = caps.ring1Enabled
    ? ringBonus(r1Levels, ml1, step, [
        { until: r1Max2, innerMaxed: 0 },
        { until: Number.POSITIVE_INFINITY, innerMaxed: 1 },
      ], ov)
    : 0;

  const c2 = caps.ring2Enabled
    ? ringBonus(r2Levels, ml2, step, [{ until: Number.POSITIVE_INFINITY, innerMaxed: 0 }], ov)
    : 0;

  return applyBonusRoom([c0, c1, c2], t);
}

function ringBonus(
  levels: number,
  ml: number,
  step: number,
  bands: { until: number; innerMaxed: number }[],
  ov: (innerMaxed: number) => number,
): number {
  if (!(levels > 0) || !(ml > 0)) return 0;
  const normalLv = Math.min(levels, ml);
  let sum = normalLv * step;
  if (levels <= ml) return nice(sum);
  let from = ml;
  for (const band of bands) {
    if (from >= levels) break;
    const to = Math.min(levels, band.until);
    if (to > from) sum += (to - from) * ov(band.innerMaxed);
    from = Math.max(from, band.until);
  }
  return nice(sum);
}

function applyBonusRoom(parts: [number, number, number], t: ComboParams): [number, number, number] {
  const base = t.comboBase > 0 && Number.isFinite(t.comboBase) ? t.comboBase : 1;
  const abs = t.comboAbsMax > 0 && Number.isFinite(t.comboAbsMax) ? t.comboAbsMax : 3;
  let room = Math.max(0, abs - base);
  const out: [number, number, number] = [0, 0, 0];
  for (let i = 0; i < 3; i++) {
    const take = Math.min(Math.max(0, parts[i]), room);
    out[i] = nice(take);
    room = nice(room - take);
  }
  return out;
}

export function comboMultiplier(state: ComboState, t: ComboParams): number {
  const caps = comboCaps(t);
  const taps = clampTaps(state.taps, t);
  const base = t.comboBase > 0 && Number.isFinite(t.comboBase) ? t.comboBase : 1;
  const abs = t.comboAbsMax > 0 && Number.isFinite(t.comboAbsMax) ? t.comboAbsMax : 3;
  const laps = Math.floor(taps / caps.c0);
  const bonus = ringContributions(laps, t).reduce((n, x) => n + x, 0);
  return nice(Math.min(abs, base + bonus));
}

/** Hub label: one decimal on tenths, extra digits only if needed. */
export function formatComboMultiplier(m: number): string {
  if (!(m > 1.001)) return "";
  const tenths = Math.round(m * 10) / 10;
  if (Math.abs(m - tenths) < 5e-4) return `×${tenths.toFixed(1)}`;
  const hundredths = Math.round(m * 100) / 100;
  if (Math.abs(m - hundredths) < 5e-5) return `×${hundredths.toFixed(2)}`;
  const thousandths = Math.round(m * 1000) / 1000;
  if (Math.abs(m - thousandths) < 5e-6) return `×${thousandths.toFixed(3)}`;
  return `×${(Math.round(m * 10000) / 10000).toFixed(4)}`;
}

/** Visible fill is the current digit of each ring. */
export function displayMeters(state: ComboState, t: ComboParams): number[] {
  const caps = comboCaps(t);
  const taps = clampTaps(state.taps, t);
  if (taps >= caps.maxTaps - 1e-12) {
    return [1, caps.ring1Enabled ? 1 : 0, caps.ring2Enabled ? 1 : 0];
  }
  const m0 = posMod(taps, caps.c0) / caps.c0;
  const laps = Math.floor(taps / caps.c0);
  const m1 = caps.ring1Enabled ? posMod(laps, caps.c1) / caps.c1 : 0;
  const inner = Math.floor(taps / (caps.c0 * caps.c1));
  const m2 = caps.ring2Enabled ? posMod(inner, caps.c2) / caps.c2 : 0;
  return [clamp01(m0), clamp01(m1), clamp01(m2)];
}

/** Track stays up once that digit has started (and after wrap, while a higher digit is live). */
export function displayTracks(state: ComboState, t: ComboParams): boolean[] {
  const caps = comboCaps(t);
  const taps = clampTaps(state.taps, t);
  return [
    taps > 1e-9,
    caps.ring1Enabled && taps >= caps.c0 - 1e-12,
    caps.ring2Enabled && taps >= caps.c0 * caps.c1 - 1e-12,
  ];
}

/**
 * Tick-bezel turns from the live tap counter (not the stepped fill).
 * Ring 0: one turn per C0 taps. Inner rings move every tap, C1/C2 times slower.
 */
export function displaySpins(state: ComboState, t: ComboParams): number[] {
  const caps = comboCaps(t);
  const taps = clampTaps(state.taps, t);
  const c0 = caps.c0;
  const c1 = Math.max(1, caps.c1);
  const c2 = Math.max(1, caps.c2);
  return [
    taps / c0,
    caps.ring1Enabled ? taps / (c0 * c1) : 0,
    caps.ring2Enabled ? taps / (c0 * c1 * c2) : 0,
  ];
}

export function wouldCompleteOuter(state: ComboState, t: ComboParams): boolean {
  const caps = comboCaps(t);
  const taps = clampTaps(state.taps, t);
  if (taps >= caps.maxTaps - 1e-12) return false;
  return posMod(taps, caps.c0) + 1 >= caps.c0 - 1e-12;
}

/** Drain from the last tap to `nowMs` (O(1), idle only). */
export function comboAt(state: ComboState, nowMs: number, t: ComboParams): ComboState {
  const cur = normalizeCombo(state, t);
  if (cur.lastTapAtMs == null) return cur;
  if (!Number.isFinite(nowMs) || nowMs <= cur.lastTapAtMs) return cur;
  const grace = Math.max(0, Number(t.comboIdleGraceSeconds) || 0);
  const dt = (nowMs - cur.lastTapAtMs) / 1000;
  if (dt <= grace) return cur;
  const rate = Math.max(0, Number(t.comboDrainPerSecondIdle) || 0) * comboCaps(t).c0;
  const drain = (dt - grace) * rate;
  if (!Number.isFinite(drain) || drain >= cur.taps) {
    return { taps: 0, lastTapAtMs: cur.lastTapAtMs };
  }
  return { taps: clampTaps(cur.taps - drain, t), lastTapAtMs: cur.lastTapAtMs };
}

/** Drain to now, then add one tap. Caps at maxTaps. */
export function applyComboTap(state: ComboState, nowMs: number, t: ComboParams): ComboState {
  const cur = comboAt(state, nowMs, t);
  const at = Number.isFinite(nowMs) ? nowMs : cur.lastTapAtMs;
  return { taps: clampTaps(cur.taps + 1, t), lastTapAtMs: at };
}

/** Derived ring fields for old readers + `comboTaps` as the source of truth. */
export function persistCombo(state: ComboState, t: ComboParams): ComboPersist {
  const caps = comboCaps(t);
  const taps = clampTaps(state.taps, t);
  const meters = displayMeters({ taps, lastTapAtMs: state.lastTapAtMs }, t);
  const laps0 = Math.floor(taps / caps.c0);
  const laps1 = Math.floor(taps / (caps.c0 * caps.c1));
  const laps2 = Math.floor(taps / (caps.c0 * caps.c1 * caps.c2));
  const [c0, c1, c2] = ringContributions(laps0, t);
  return {
    comboTaps: nice(taps),
    comboMeter: meters[0],
    comboLevel: laps0,
    comboContrib: c0,
    comboMeter1: meters[1],
    comboLevel1: laps1,
    comboContrib1: c1,
    comboMeter2: meters[2],
    comboLevel2: laps2,
    comboContrib2: c2,
  };
}
