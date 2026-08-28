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
  /** Multiplier added each outer-ring complete (1.0 → 1.1 → 1.2 …). */
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
  return {
    c0,
    c1,
    c2,
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

export function comboMultiplier(state: ComboState, t: ComboParams): number {
  const caps = comboCaps(t);
  const taps = clampTaps(state.taps, t);
  const base = t.comboBase > 0 && Number.isFinite(t.comboBase) ? t.comboBase : 1;
  const abs = t.comboAbsMax > 0 && Number.isFinite(t.comboAbsMax) ? t.comboAbsMax : 3;
  const laps = Math.floor(taps / caps.c0);
  return nice(Math.min(abs, base + laps * stepOf(t)));
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
  const base = t.comboBase > 0 && Number.isFinite(t.comboBase) ? t.comboBase : 1;
  const abs = t.comboAbsMax > 0 && Number.isFinite(t.comboAbsMax) ? t.comboAbsMax : 3;
  const bonus = Math.min(Math.max(0, abs - base), laps0 * stepOf(t));
  return {
    comboTaps: nice(taps),
    comboMeter: meters[0],
    comboLevel: laps0,
    comboContrib: nice(bonus),
    comboMeter1: meters[1],
    comboLevel1: laps1,
    comboContrib1: 0,
    comboMeter2: meters[2],
    comboLevel2: laps2,
    comboContrib2: 0,
  };
}
