/** Manual-tap nested combo. Keep in lockstep with iOS `ComboEngine.swift`,
 *  Android `Combo.kt`, and `web/app.js`.
 *  Never applied to Auto Tapper, Skip Time, or offline catch-up — live taps only.
 */

export const RING_COUNT = 3;

export type ComboParams = {
  /** Taps to fill one outermost (ring 0) cycle. */
  comboTapsPerLevel: number;
  /** Multiplier added each non-overflow completion (1.0 → 1.1 → 1.2 …). */
  comboStep: number;
  /** Starting multiplier with no rings completed. */
  comboBase: number;
  /** Hard cap on the live-tap multiplier. */
  comboAbsMax: number;
  /** Max contribution from ring 0 (outer). Overflow continues past this. */
  comboRing0Max: number;
  comboRing1Max: number;
  comboRing2Max: number;
  /** Seconds after a tap before idle drain kicks in. */
  comboIdleGraceSeconds: number;
  /** Ring units (0–1) drained per second while still tapping. */
  comboDrainPerSecondActive: number;
  /** Ring units drained per second after the grace window. */
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

export type ComboRingState = {
  meter: number;
  level: number;
  contribution: number;
};

export type ComboState = {
  rings: ComboRingState[];
  lastTapAtMs: number | null;
};

export function emptyCombo(): ComboState {
  return {
    rings: [0, 1, 2].map(() => ({ meter: 0, level: 0, contribution: 0 })),
    lastTapAtMs: null,
  };
}

export function normalizeCombo(state: ComboState, t: ComboParams): ComboState {
  const rings: ComboRingState[] = [];
  for (let i = 0; i < RING_COUNT; i++) {
    const r = state.rings[i] || { meter: 0, level: 0, contribution: 0 };
    const level = Math.max(0, Math.floor(r.level || 0));
    let contribution = Math.max(0, r.contribution || 0);
    if (contribution <= 0 && level > 0) {
      contribution = derivedContribution(level, i, t);
    }
    rings.push({
      meter: clamp01(r.meter || 0),
      level,
      contribution: nice(contribution),
    });
  }
  return { rings, lastTapAtMs: state.lastTapAtMs };
}

function nice(n: number): number {
  return Math.round(n * 1e8) / 1e8;
}

function clamp01(n: number): number {
  return Math.max(0, Math.min(1, n));
}

function stepOf(t: ComboParams): number {
  return t.comboStep > 0 ? t.comboStep : 0.1;
}

function ringMaxOf(ring: number, t: ComboParams): number {
  const raw = [t.comboRing0Max, t.comboRing1Max, t.comboRing2Max][ring] ?? 0;
  return Math.max(0, raw);
}

export function maxLevels(ring: number, t: ComboParams): number {
  const mx = ringMaxOf(ring, t);
  if (mx <= 0) return 0;
  return Math.max(0, Math.round(mx / stepOf(t)));
}

function fillsPerLevel(parentRing: number, t: ComboParams): number {
  return Math.max(1, maxLevels(parentRing, t));
}

function ringEnabled(ring: number, t: ComboParams): boolean {
  return maxLevels(ring, t) > 0;
}

function isAtMax(state: ComboState, ring: number, t: ComboParams): boolean {
  const ml = maxLevels(ring, t);
  if (ml <= 0) return false;
  return state.rings[ring].level >= ml;
}

function innerMaxedCount(state: ComboState, ring: number, t: ComboParams): number {
  let n = 0;
  for (let j = ring + 1; j < RING_COUNT; j++) {
    if (isAtMax(state, j, t)) n += 1;
  }
  return n;
}

/** Overflow quantum: 0.01, then 0.001 / 0.0001 as each inner ring maxes. */
function overflowStep(innerMaxed: number, t: ComboParams): number {
  const exp = 1 + Math.max(0, innerMaxed);
  return nice(stepOf(t) / Math.pow(10, exp));
}

function completionIncrement(state: ComboState, ring: number, t: ComboParams): number {
  const ml = maxLevels(ring, t);
  if (state.rings[ring].level < ml) return stepOf(t);
  return overflowStep(innerMaxedCount(state, ring, t), t);
}

function derivedContribution(level: number, ring: number, t: ComboParams): number {
  const step = stepOf(t);
  const ml = maxLevels(ring, t);
  const stepLv = Math.min(level, ml);
  const overflowLv = Math.max(0, level - ml);
  return nice(stepLv * step + overflowLv * overflowStep(0, t));
}

function totalBonus(state: ComboState): number {
  let n = 0;
  for (const r of state.rings) n += r.contribution;
  return n;
}

export function comboMultiplier(state: ComboState, t: ComboParams): number {
  const base = t.comboBase > 0 ? t.comboBase : 1;
  const abs = t.comboAbsMax > 0 ? t.comboAbsMax : 3;
  return nice(Math.min(abs, base + totalBonus(state)));
}

/** Hub label: one decimal on tenths, extra digits when overflow is in play. */
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

/** Visible fill: at contribution max stay full; otherwise the current meter. */
export function displayMeters(state: ComboState, t: ComboParams): number[] {
  return state.rings.map((r, i) => {
    if (!ringEnabled(i, t)) return 0;
    if (isAtMax(state, i, t)) return 1;
    return clamp01(r.meter);
  });
}

/** Track stays up once a ring has contribution/levels, even if meter wrapped to 0. */
export function displayTracks(state: ComboState, t: ComboParams): boolean[] {
  const meters = displayMeters(state, t);
  return state.rings.map((r, i) => {
    if (!ringEnabled(i, t)) return false;
    if (meters[i] > 0.001) return true;
    if (isAtMax(state, i, t)) return true;
    return r.level > 0 || r.contribution > 1e-12;
  });
}

function applyCompletion(state: ComboState, ring: number, t: ComboParams): void {
  const inc = completionIncrement(state, ring, t);
  const abs = t.comboAbsMax > 0 ? t.comboAbsMax : 3;
  const base = t.comboBase > 0 ? t.comboBase : 1;
  const room = Math.max(0, abs - base - totalBonus(state));
  const applied = Math.min(inc, room);
  state.rings[ring].level += 1;
  state.rings[ring].contribution = nice(state.rings[ring].contribution + applied);
  // Every wrap fills the next inner ring immediately (first outer complete → ring 1 at 10%).
  if (ring + 1 < RING_COUNT) {
    addFill(state, ring + 1, 1 / fillsPerLevel(ring, t), t);
  }
}

function addFill(state: ComboState, ring: number, amount: number, t: ComboParams): void {
  if (!ringEnabled(ring, t) || !(amount > 0)) return;
  state.rings[ring].meter = nice(state.rings[ring].meter + amount);
  while (state.rings[ring].meter >= 1 - 1e-12) {
    state.rings[ring].meter = nice(state.rings[ring].meter - 1);
    applyCompletion(state, ring, t);
  }
}

function reverseCompletion(state: ComboState, ring: number, t: ComboParams): void {
  const r = state.rings[ring];
  if (r.level <= 0) return;
  const ml = maxLevels(ring, t);
  const step = stepOf(t);
  const inc = r.level > ml ? overflowStep(innerMaxedCount(state, ring, t), t) : step;
  r.level -= 1;
  r.contribution = nice(Math.max(0, r.contribution - inc));
  if (r.level < ml) {
    r.contribution = nice(Math.min(r.contribution, r.level * step));
  } else if (r.level === ml) {
    r.contribution = nice(Math.min(r.contribution, ringMaxOf(ring, t)));
  }
  if (r.level <= 0) {
    r.level = 0;
    r.contribution = 0;
  }
  if (ring + 1 < RING_COUNT) {
    unwindFill(state, ring + 1, 1 / fillsPerLevel(ring, t), t);
  }
}

function unwindFill(state: ComboState, ring: number, amount: number, t: ComboParams): void {
  if (!ringEnabled(ring, t) || !(amount > 0)) return;
  state.rings[ring].meter = nice(state.rings[ring].meter - amount);
  while (state.rings[ring].meter < -1e-12) {
    if (state.rings[ring].level <= 0) {
      state.rings[ring].meter = 0;
      break;
    }
    reverseCompletion(state, ring, t);
    state.rings[ring].meter = nice(state.rings[ring].meter + 1);
  }
}

function peelRing(state: ComboState, ring: number, t: ComboParams): void {
  reverseCompletion(state, ring, t);
  state.rings[ring].meter = 1;
}

function drainAmount(dtSec: number, idle: boolean, t: ComboParams): number {
  const rate = idle ? t.comboDrainPerSecondIdle : t.comboDrainPerSecondActive;
  return Math.max(0, dtSec) * Math.max(0, rate);
}

export function applyDrain(state: ComboState, drain: number, t: ComboParams): ComboState {
  const next = normalizeCombo(state, t);
  let remain = Math.max(0, drain);
  while (remain > 1e-12) {
    let i = -1;
    for (let r = 0; r < RING_COUNT; r++) {
      if (next.rings[r].meter > 1e-12 || next.rings[r].level > 0) {
        i = r;
        break;
      }
    }
    if (i < 0) break;
    const ring = next.rings[i];
    if (ring.meter > 1e-12) {
      const take = Math.min(ring.meter, remain);
      ring.meter = nice(ring.meter - take);
      remain = nice(remain - take);
    } else if (ring.level > 0) {
      peelRing(next, i, t);
    } else {
      break;
    }
  }
  return next;
}

/** Drain from the last tap to `nowMs` (no fill). */
export function comboAt(state: ComboState, nowMs: number, t: ComboParams): ComboState {
  const cur = normalizeCombo(state, t);
  if (cur.lastTapAtMs == null) {
    // Missing timestamp: keep meter. Do not treat as idle (that used 0.5/s drain).
    return cur;
  }
  if (nowMs <= cur.lastTapAtMs) return cur;
  const grace = Math.max(0, t.comboIdleGraceSeconds);
  const dt = (nowMs - cur.lastTapAtMs) / 1000;
  if (dt <= grace) {
    return applyDrain(cur, drainAmount(dt, false, t), t);
  }
  const afterGrace = applyDrain(cur, drainAmount(grace, false, t), t);
  return applyDrain(afterGrace, drainAmount(dt - grace, true, t), t);
}

/** Drain to now, add one tap of fill on ring 0, cascade into inner rings. */
export function applyComboTap(state: ComboState, nowMs: number, t: ComboParams): ComboState {
  const cur = comboAt(state, nowMs, t);
  const per = Math.max(1, t.comboTapsPerLevel);
  addFill(cur, 0, 1 / per, t);
  return { rings: cur.rings, lastTapAtMs: nowMs };
}
