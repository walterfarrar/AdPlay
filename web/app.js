import { initializeApp } from "https://www.gstatic.com/firebasejs/11.10.0/firebase-app.js";
import {
  getAuth,
  signInAnonymously,
  onAuthStateChanged,
} from "https://www.gstatic.com/firebasejs/11.10.0/firebase-auth.js";
import {
  getFunctions,
  httpsCallable,
} from "https://www.gstatic.com/firebasejs/11.10.0/firebase-functions.js";

const firebaseConfig = {
  apiKey: "AIzaSyDltLIdTXx46kzwMIlQmKqCLxrJclQWZjQ",
  authDomain: "adplay-sats.firebaseapp.com",
  projectId: "adplay-sats",
  storageBucket: "adplay-sats.firebasestorage.app",
  messagingSenderId: "114161299929",
  appId: "1:114161299929:web:6827a406dd1788595229c8",
};

const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const functions = getFunctions(app, "us-central1");

const callGetState = httpsCallable(functions, "getState");
const callTap = httpsCallable(functions, "gameTap");
const callBoost = httpsCallable(functions, "mockCompleteBoost");
const callReset = httpsCallable(functions, "debugReset");
const callWithdraw = httpsCallable(functions, "requestWithdrawal");
const callMyWithdrawals = httpsCallable(functions, "myWithdrawals");

/** @type {any} */
let serverState = null;
/** Last fully-acked server snapshot (excludes optimistic taps still in flight). */
let confirmedState = null;
/** Manual taps shown locally but not yet confirmed by `gameTap`. */
let unackedTaps = 0;
let tapFlushPromise = null;
let tapFlushGeneration = 0;
/** @type {any} */
let tunables = null;
let playerProgress = null;
let anchorMs = 0;
let lastUpdatedAt = null;
let windowEndHandled = false;
let rafId = 0;
let refreshTimerId = null;
let loading = false;
let lastRenderedSats = null;
let wheelFlashUntil = 0;
let lastCelebrateAt = 0;

/** Local continuous / knocker clocks (mirror iOS SatEarnStage). */
let displayAnchorProgress = 0;
let displayAnchorMs = 0;
let knockerAnchorProgress = 0;
let knockerAnchorMs = 0;
let lastFillRate = 0;
let heldDisplay = 0;

const KNOCKER = {
  pivot: { x: 350, y: 78 },
  contact: { x: 317.1, y: 140.3 },
  strikePoint: { x: 312, y: 150 },
  sweepDeg: 42,
  bounce: 0.42,
  windUp: 0.07,
  impactFade: 0.16,
};

const DEFAULT_COMBO = {
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

function comboParams() {
  const merged = { ...DEFAULT_COMBO, ...(tunables || {}) };
  if (!(merged.comboAbsMax > 0)) merged.comboAbsMax = DEFAULT_COMBO.comboAbsMax;
  if (merged.comboRing0Max == null) merged.comboRing0Max = DEFAULT_COMBO.comboRing0Max;
  if (merged.comboRing1Max == null) merged.comboRing1Max = DEFAULT_COMBO.comboRing1Max;
  if (merged.comboRing2Max == null) merged.comboRing2Max = DEFAULT_COMBO.comboRing2Max;
  return merged;
}

function nice(n) {
  return Math.round(n * 1e8) / 1e8;
}

function clamp01(n) {
  if (!Number.isFinite(n) || n <= 0) return 0;
  if (n >= 1) return 1;
  return n;
}

function clampInt(n, lo, hi) {
  if (!Number.isFinite(n)) return lo;
  const x = Math.trunc(n);
  if (x < lo) return lo;
  if (x > hi) return hi;
  return x;
}

function stepOf(t) {
  return t.comboStep > 0 && Number.isFinite(t.comboStep) ? t.comboStep : 0.1;
}

function posMod(a, b) {
  if (!(b > 0) || !Number.isFinite(a)) return 0;
  const r = a % b;
  return r < 0 ? r + b : r;
}

function comboCaps(t) {
  const step = stepOf(t);
  const c0 = clampInt(t.comboTapsPerLevel, 1, 10000);
  const raw1 = Math.round(Math.max(0, Number(t.comboRing0Max) || 0) / step);
  const raw2 = Math.round(Math.max(0, Number(t.comboRing1Max) || 0) / step);
  const ring1Enabled = clampInt(raw1, 0, 100) > 0;
  const ring2Enabled = clampInt(raw2, 0, 100) > 0 && (Number(t.comboRing2Max) || 0) > 0;
  const c1 = ring1Enabled ? clampInt(raw1, 1, 100) : 1;
  const c2 = ring2Enabled ? clampInt(raw2, 1, 100) : 1;
  return { c0, c1, c2, maxTaps: c0 * c1 * c2, ring1Enabled, ring2Enabled };
}

function clampTaps(taps, t) {
  const max = comboCaps(t).maxTaps;
  if (!Number.isFinite(taps) || taps <= 0) return 0;
  return taps >= max ? max : taps;
}

function tapsFromPersisted(comboTaps, comboLevel, comboMeter, t) {
  if (typeof comboTaps === "number" && Number.isFinite(comboTaps)) {
    return clampTaps(comboTaps, t);
  }
  const c0 = comboCaps(t).c0;
  const level = Number.isFinite(comboLevel) ? Math.max(0, Math.floor(comboLevel)) : 0;
  return clampTaps(level * c0 + clamp01(comboMeter) * c0, t);
}

function comboMultiplier(state, t) {
  const caps = comboCaps(t);
  const taps = clampTaps(state.taps, t);
  const base = t.comboBase > 0 && Number.isFinite(t.comboBase) ? t.comboBase : 1;
  const abs = t.comboAbsMax > 0 && Number.isFinite(t.comboAbsMax) ? t.comboAbsMax : 3;
  const laps = Math.floor(taps / caps.c0);
  return nice(Math.min(abs, base + laps * stepOf(t)));
}

function formatComboMultiplier(m) {
  if (!(m > 1.001)) return "";
  const tenths = Math.round(m * 10) / 10;
  if (Math.abs(m - tenths) < 5e-4) return `×${tenths.toFixed(1)}`;
  const hundredths = Math.round(m * 100) / 100;
  if (Math.abs(m - hundredths) < 5e-5) return `×${hundredths.toFixed(2)}`;
  const thousandths = Math.round(m * 1000) / 1000;
  if (Math.abs(m - thousandths) < 5e-6) return `×${thousandths.toFixed(3)}`;
  return `×${(Math.round(m * 10000) / 10000).toFixed(4)}`;
}

function displayMeters(state, t) {
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

function displayTracks(state, t) {
  const caps = comboCaps(t);
  const taps = clampTaps(state.taps, t);
  return [
    taps > 1e-9,
    caps.ring1Enabled && taps >= caps.c0 - 1e-12,
    caps.ring2Enabled && taps >= caps.c0 * caps.c1 - 1e-12,
  ];
}

function persistCombo(state, t) {
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

function persistedCombo(s) {
  const t = comboParams();
  const last = s?.lastManualTapAt ? Date.parse(s.lastManualTapAt) : NaN;
  return {
    taps: tapsFromPersisted(s?.comboTaps, s?.comboLevel || 0, s?.comboMeter || 0, t),
    lastTapAtMs: Number.isFinite(last) ? last : null,
  };
}

function writeComboFields(next) {
  return {
    ...persistCombo(next, comboParams()),
    lastManualTapAt: next.lastTapAtMs == null ? null : new Date(next.lastTapAtMs).toISOString(),
  };
}

function comboAt(state, nowMs, t) {
  const taps = clampTaps(state.taps, t);
  const last = typeof state.lastTapAtMs === "number" && Number.isFinite(state.lastTapAtMs)
    ? state.lastTapAtMs
    : null;
  if (last == null) return { taps, lastTapAtMs: null };
  if (!Number.isFinite(nowMs) || nowMs <= last) return { taps, lastTapAtMs: last };
  const grace = Math.max(0, Number(t.comboIdleGraceSeconds) || 0);
  const dt = (nowMs - last) / 1000;
  if (dt <= grace) return { taps, lastTapAtMs: last };
  const rate = Math.max(0, Number(t.comboDrainPerSecondIdle) || 0) * comboCaps(t).c0;
  const drain = (dt - grace) * rate;
  if (!Number.isFinite(drain) || drain >= taps) return { taps: 0, lastTapAtMs: last };
  return { taps: clampTaps(taps - drain, t), lastTapAtMs: last };
}

function applyComboTap(state, nowMs, t) {
  const cur = comboAt(state, nowMs, t);
  const at = Number.isFinite(nowMs) ? nowMs : cur.lastTapAtMs;
  return { taps: clampTaps(cur.taps + 1, t), lastTapAtMs: at };
}

function minerTitle(lifetime) {
  if (lifetime >= 500) return "Rig Boss";
  if (lifetime >= 50) return "Farm Hand";
  if (lifetime >= 1) return "Satoshi Scout";
  return "Spark";
}

const $ = (id) => document.getElementById(id);

function setLoading(on) {
  loading = on;
  $("overlay").classList.toggle("hidden", !on);
}

function setError(msg) {
  const el = $("error");
  if (!msg) {
    el.hidden = true;
    el.textContent = "";
    return;
  }
  el.hidden = false;
  el.textContent = msg;
}

function parseMs(iso) {
  if (!iso) return null;
  const ms = Date.parse(iso);
  return Number.isFinite(ms) ? ms : null;
}

function formatCountdown(totalSeconds) {
  let rem = Math.max(0, Math.floor(totalSeconds));
  const d = Math.floor(rem / 86400);
  rem %= 86400;
  const h = Math.floor(rem / 3600);
  rem %= 3600;
  const m = Math.floor(rem / 60);
  const s = rem % 60;
  const parts = [];
  if (d > 0) parts.push(`${d}d`);
  if (h > 0 || d > 0) parts.push(`${h}h`);
  if (m > 0 || h > 0 || d > 0) parts.push(`${m}m`);
  parts.push(`${s}s`);
  return parts.join(" ");
}

function formatLongerAction(t) {
  const seconds = t?.durationBoostSeconds ?? 1800;
  const minutes = Math.floor(seconds / 60);
  if (minutes % 60 === 0 && minutes >= 60) return `Add ${minutes / 60}h`;
  return `Add ${minutes} min`;
}

function formatFasterAction(t) {
  const amount = t?.speedBoostAmount ?? 0.5;
  return `+${amount.toFixed(2)} taps/s`;
}

function formatStrongerAction(t) {
  const amount = t?.tapStrengthBoostAmount ?? 0.25;
  return `+${amount.toFixed(2)} power/tap`;
}

function formatSkipAction(t) {
  const seconds = t?.skipTimeSeconds ?? 60;
  const minutes = Math.floor(seconds / 60);
  if (minutes >= 1 && seconds % 60 === 0) return `Skip ${minutes} min`;
  return `Skip ${seconds}s`;
}

function tapsPerSecond(fillRate, tapPower) {
  const power = tapPower > 0 ? tapPower : 1;
  return fillRate / power;
}

/** Sats earned per hour from the current auto fill rate (0 when idle). */
function satsPerHour(fillRate, unitsPerSat, autoActive) {
  if (!autoActive || fillRate <= 0 || unitsPerSat <= 0) return 0;
  return (fillRate / unitsPerSat) * 3600;
}

function formatSatsPerHour(fillRate, unitsPerSat, autoActive) {
  const rate = satsPerHour(fillRate, unitsPerSat, autoActive);
  if (rate <= 0) return "0 sats/h";
  if (rate >= 100) return `${rate.toFixed(0)} sats/h`;
  return `${rate.toFixed(1)} sats/h`;
}

/** Fixed-point 1e-13 BTC quanta. 1 sat = 1e-8 BTC = 100_000 quanta. */
function btcQuanta(satsBalance, barProgress, unitsPerSat) {
  const units = Math.max(1, unitsPerSat | 0);
  const progressMilli = Math.round(
    Math.min(units, Math.max(0, barProgress)) * 1000,
  );
  const clamped = Math.min(units * 1000, Math.max(0, progressMilli));
  const denom = units * 1000;
  const fracQuanta = Math.floor((clamped * 100_000 + denom / 2) / denom);
  return BigInt(satsBalance) * 100_000n + BigInt(fracQuanta);
}

function formatBtcQuanta(quanta) {
  const whole = quanta / 10_000_000_000_000n;
  const frac = quanta % 10_000_000_000_000n;
  return `${whole}.${frac.toString().padStart(13, "0")}`;
}

function formatBtcAmount(satsBalance, barProgress, unitsPerSat) {
  return formatBtcQuanta(btcQuanta(satsBalance, barProgress, unitsPerSat));
}

/** Whole-sat balances as BTC (8 dp). */
function formatSatsAsBtc(sats) {
  return (Number(sats) * 1e-8).toFixed(8);
}

function parseBtcToSats(text) {
  const raw = String(text || "").trim();
  if (!raw) return null;
  const btc = Number(raw);
  if (!Number.isFinite(btc) || btc <= 0) return null;
  const sats = Math.round(btc * 1e8);
  if (sats <= 0 || !Number.isFinite(sats)) return null;
  return sats;
}

function filterBtcInput(raw) {
  let result = "";
  let sawDot = false;
  for (const ch of String(raw)) {
    if (ch >= "0" && ch <= "9") result += ch;
    else if (ch === "." && !sawDot) {
      sawDot = true;
      result += ch;
    }
  }
  const dot = result.indexOf(".");
  if (dot >= 0 && result.length - dot - 1 > 8) {
    result = result.slice(0, dot + 1 + 8);
  }
  return result;
}

function easeOutQuad(t) {
  const x = Math.min(1, Math.max(0, t));
  return 1 - (1 - x) * (1 - x);
}

function easeInOutCubic(t) {
  const x = Math.min(1, Math.max(0, t));
  return x < 0.5 ? 4 * x * x * x : 1 - (-2 * x + 2) ** 3 / 2;
}

function knockerStrikeDuration(tapPower) {
  return Math.max(0.07, 0.16 / Math.max(tapPower, 0.01));
}

function knockerImpactScale(tapPower) {
  const p = Math.min(Math.max(tapPower, 1), 10);
  return 1 + ((p - 1) / 9) * 1.25;
}

function knockerCyclePhase(elapsedSec, tapsPerSec, originUnits, tapPower) {
  if (tapsPerSec <= 0) return 0;
  const power = Math.max(tapPower, 0.01);
  const originFrac = originUnits / power;
  const frac = originFrac - Math.floor(originFrac);
  const raw = elapsedSec * tapsPerSec + frac;
  return raw - Math.floor(raw);
}

function holdMonotonicProgress(held, raw, wrapSlop = 5) {
  return raw + wrapSlop < held ? raw : Math.max(held, raw);
}

/** Strike cycle for the auto tapper — phase is wall-clock, not accumulated progress. */
function knockerPose(elapsedSec, originUnits, tapsPerSec, tapPower, autoActive) {
  if (!autoActive || tapsPerSec <= 0) return { arm: 0, impact: 0, phase: 0 };
  const period = 1 / tapsPerSec;
  const phase = knockerCyclePhase(elapsedSec, tapsPerSec, originUnits, tapPower);

  const strike = Math.min(0.34, Math.max(0.06, knockerStrikeDuration(tapPower) / period));
  const recoil = Math.min(0.2, Math.max(0.05, 0.07 / period));
  const windUp = Math.max(Math.min(0.09, (1 - strike - recoil) * 0.2), 0.0001);
  const reset = Math.max(1 - strike - recoil - windUp, 0.001);

  const fadeSec = Math.min(KNOCKER.impactFade, period * 0.55);
  const impact = Math.max(0, 1 - (phase * period) / fadeSec) ** 1.7;

  let arm;
  if (phase < recoil) {
    arm = 1 - KNOCKER.bounce * easeOutQuad(phase / recoil);
  } else if (phase < recoil + reset) {
    arm = (1 - KNOCKER.bounce) * (1 - easeInOutCubic((phase - recoil) / reset));
  } else if (phase < 1 - strike) {
    arm = -KNOCKER.windUp * easeOutQuad((phase - recoil - reset) / windUp);
  } else {
    const t = Math.min(1, (phase - (1 - strike)) / strike);
    arm = -KNOCKER.windUp + (1 + KNOCKER.windUp) * t ** 2.3;
  }
  return { arm, impact, phase };
}

function displayedBarProgress(progress, total, fillRate, autoActive, nowMs) {
  if (!autoActive || fillRate <= 0 || total <= 0) return progress;
  const elapsed = (nowMs - displayAnchorMs) / 1000;
  return Math.min(total, displayAnchorProgress + fillRate * elapsed);
}

function struckSyncedProgress(
  continuous,
  knockerProgress,
  tapPower,
  autoActive,
  fillRate,
  total,
) {
  if (!autoActive || fillRate <= 0) return continuous;
  const power = Math.max(tapPower, 0.01);
  const cap = total;
  if (knockerProgress > continuous + cap * 0.5 && knockerProgress > cap + power) {
    return Math.min(cap, continuous);
  }
  const knockerHits = Math.floor(Math.min(knockerProgress, cap + power) / power + 1e-9);
  const quantized = knockerHits * power;
  const extra = Math.max(0, continuous - knockerProgress);
  return Math.min(cap, quantized + extra);
}

function rebaseKnockerClock(oldFillRate, nowMs = Date.now()) {
  const rate = oldFillRate > 0 ? oldFillRate : 0;
  knockerAnchorProgress += rate * ((nowMs - knockerAnchorMs) / 1000);
  knockerAnchorMs = nowMs;
}

function syncDisplayAnchors(progress, { resetKnocker = false, wrap = false } = {}) {
  displayAnchorProgress = progress;
  displayAnchorMs = Date.now();
  if (wrap) {
    knockerAnchorProgress = progress;
    knockerAnchorMs = Date.now();
    heldDisplay = progress;
  } else if (resetKnocker) {
    // Auto start only — never yank the arm onto combo extras.
    knockerAnchorProgress = progress;
    knockerAnchorMs = Date.now();
  }
}

/** Local display of banked charges + regen countdown from the server anchor. */
function projectChargeBank(initialCharges, initialRegen, nextAt, maxCharges, nowMs) {
  const regenSec = tunables?.adRegenSeconds ?? 0;
  let charges = initialCharges;
  let regenLeft = initialRegen ?? 0;
  if (!(regenSec > 0) || charges >= maxCharges) {
    return { charges: Math.min(charges, maxCharges), regenLeft: 0 };
  }
  const nextMs = parseMs(nextAt);
  if (nextMs != null) {
    if (nowMs >= nextMs) {
      const gained = 1 + Math.floor((nowMs - nextMs) / 1000 / regenSec);
      charges = Math.min(maxCharges, initialCharges + gained);
      if (charges >= maxCharges) {
        regenLeft = 0;
      } else {
        const into = Math.floor(((nowMs - nextMs) / 1000) % regenSec);
        regenLeft = Math.max(0, regenSec - into);
      }
    } else {
      regenLeft = Math.max(0, Math.ceil((nextMs - nowMs) / 1000));
    }
  } else if (regenLeft > 0) {
    const elapsed = Math.max(0, nowMs - anchorMs) / 1000;
    const left = Math.ceil(regenLeft - elapsed);
    if (left <= 0) {
      const overdue = -left;
      const gained = 1 + Math.floor(overdue / regenSec);
      charges = Math.min(maxCharges, initialCharges + gained);
      regenLeft = charges >= maxCharges ? 0 : regenSec - (overdue % regenSec);
    } else {
      regenLeft = left;
    }
  }
  return { charges, regenLeft };
}

/** Project a server snapshot forward by wall-clock elapsed time (display only). */
function project(s, nowMs) {
  const elapsedSec = Math.max(0, nowMs - anchorMs) / 1000;
  const cooldown = Math.max(0, Math.ceil(s.adCooldownSecondsLeft - elapsedSec));
  const untilMs = parseMs(s.autoFillUntil);
  const autoActive = Boolean(s.autoFillActive && untilMs != null && untilMs > nowMs);
  const windowExpired = Boolean(s.autoFillActive && !autoActive);
  const maxCharges = tunables?.adsPerCycle ?? Math.max(s.adsRemainingToday ?? 0, 1);
  let adsLeft;
  let regenLeft;
  if (windowExpired) {
    adsLeft = maxCharges;
    regenLeft = 0;
  } else {
    const bank = projectChargeBank(
      s.adsRemainingToday ?? 0,
      s.adRegenSecondsLeft ?? 0,
      s.nextAdChargeAt,
      maxCharges,
      nowMs,
    );
    adsLeft = bank.charges;
    regenLeft = bank.regenLeft;
  }

  const skipMax = tunables?.skipAdsPerCycle;
  let skipLeft;
  let skipRegenLeft;
  if (typeof skipMax === "number" && skipMax < 0) {
    skipLeft = 0;
    skipRegenLeft = 0;
  } else if (windowExpired) {
    skipLeft = skipMax === 0 ? -1 : skipMax ?? s.skipAdsRemaining;
    skipRegenLeft = 0;
  } else if (skipMax === 0) {
    skipLeft = -1;
    skipRegenLeft = 0;
  } else {
    const maxSkip = skipMax ?? Math.max(s.skipAdsRemaining ?? 0, 0);
    if (maxSkip <= 0) {
      skipLeft = s.skipAdsRemaining ?? 0;
      skipRegenLeft = 0;
    } else {
      const bank = projectChargeBank(
        Math.max(0, s.skipAdsRemaining ?? 0),
        s.skipAdRegenSecondsLeft ?? 0,
        s.nextSkipAdChargeAt,
        maxSkip,
        nowMs,
      );
      skipLeft = bank.charges;
      skipRegenLeft = bank.regenLeft;
    }
  }

  if (!s.autoFillActive || s.fillRate <= 0 || s.unitsPerSat <= 0 || untilMs == null) {
    return {
      ...s,
      adCooldownSecondsLeft: cooldown,
      autoFillActive: autoActive,
      adsRemainingToday: adsLeft,
      adRegenSecondsLeft: regenLeft,
      nextAdChargeAt: windowExpired ? null : s.nextAdChargeAt,
      skipAdsRemaining: skipLeft,
      skipAdRegenSecondsLeft: skipRegenLeft,
      nextSkipAdChargeAt: windowExpired || skipLeft < 0 ? null : s.nextSkipAdChargeAt,
      durationBoostActive: autoActive ? s.durationBoostActive : false,
      speedBoostActive: autoActive ? s.speedBoostActive : false,
      tapStrengthActive: autoActive ? s.tapStrengthActive : false,
      durationBoostCount: autoActive ? s.durationBoostCount : 0,
      speedBoostCount: autoActive ? s.speedBoostCount : 0,
      tapStrengthBoostCount: autoActive ? s.tapStrengthBoostCount : 0,
    };
  }

  const earnUntil = Math.min(nowMs, untilMs);
  const earnSec = Math.max(0, earnUntil - anchorMs) / 1000;
  const total = s.progress + s.fillRate * earnSec;
  let bars = Math.max(0, Math.floor(total / s.unitsPerSat));
  const maxBars = Math.max(0, s.dailySatsEarnCap - s.satsEarnedToday);
  if (bars > maxBars) bars = maxBars;
  const newProgress = Math.min(
    s.unitsPerSat,
    Math.max(0, total - bars * s.unitsPerSat),
  );

  return {
    ...s,
    progress: newProgress,
    satsBalance: s.satsBalance + bars,
    satsEarnedToday: s.satsEarnedToday + bars,
    adCooldownSecondsLeft: cooldown,
    autoFillActive: autoActive,
    adsRemainingToday: adsLeft,
    adRegenSecondsLeft: regenLeft,
    nextAdChargeAt: windowExpired ? null : s.nextAdChargeAt,
    skipAdsRemaining: skipLeft,
    skipAdRegenSecondsLeft: skipRegenLeft,
    nextSkipAdChargeAt: windowExpired || skipLeft < 0 ? null : s.nextSkipAdChargeAt,
    durationBoostActive: autoActive ? s.durationBoostActive : false,
    speedBoostActive: autoActive ? s.speedBoostActive : false,
    tapStrengthActive: autoActive ? s.tapStrengthActive : false,
    durationBoostCount: autoActive ? s.durationBoostCount : 0,
    speedBoostCount: autoActive ? s.speedBoostCount : 0,
    tapStrengthBoostCount: autoActive ? s.tapStrengthBoostCount : 0,
  };
}

function applyingManualTap(s) {
  if (!s || s.tapsRemaining <= 0) return s;
  const units = Math.max(1, s.unitsPerSat || 1);
  const t = comboParams();
  const nowMs = Date.now();
  const nextCombo = applyComboTap(persistedCombo(s), nowMs, t);
  const power = (s.tapPower > 0 ? s.tapPower : 1) * comboMultiplier(nextCombo, t);
  let progress = s.progress + power;
  let earned = 0;
  const cap = s.dailySatsEarnCap || 0;
  while (progress >= units) {
    if (cap > 0 && s.satsEarnedToday + earned >= cap) {
      progress = units - 0.0001;
      break;
    }
    progress -= units;
    earned += 1;
  }
  return {
    ...s,
    tapsRemaining: s.tapsRemaining - 1,
    progress,
    satsBalance: s.satsBalance + earned,
    satsEarnedToday: s.satsEarnedToday + earned,
    ...writeComboFields(nextCombo),
    comboMultiplier: comboMultiplier(nextCombo, t),
  };
}

function overlayLiveTapUnits(server, local) {
  if (!server || !local) return server;
  return {
    ...server,
    progress: local.progress,
    satsBalance: local.satsBalance,
    satsEarnedToday: local.satsEarnedToday,
    comboTaps: local.comboTaps,
    comboMeter: local.comboMeter,
    comboLevel: local.comboLevel,
    comboContrib: local.comboContrib,
    comboMeter1: local.comboMeter1,
    comboLevel1: local.comboLevel1,
    comboContrib1: local.comboContrib1,
    comboMeter2: local.comboMeter2,
    comboLevel2: local.comboLevel2,
    comboContrib2: local.comboContrib2,
    lastManualTapAt: local.lastManualTapAt,
    comboMultiplier: local.comboMultiplier,
  };
}

function comboRecentlyTapped(s) {
  const last = Date.parse(s?.lastManualTapAt || "");
  return Number.isFinite(last) && Date.now() - last < 15_000;
}

function publishOptimisticTaps() {
  if (!confirmedState) return;
  let s = confirmedState;
  for (let i = 0; i < unackedTaps; i++) s = applyingManualTap(s);
  const prevProgress = serverState?.progress ?? s.progress;
  serverState = s;
  const projected = project(s, Date.now());
  // Anchor the wheel to projected progress (auto included) so extra = combo
  // units on top of the knocker clock, not snapshot-without-auto.
  if (projected.progress + 5 < prevProgress) {
    syncDisplayAnchors(projected.progress, { wrap: true });
  } else {
    syncDisplayAnchors(projected.progress);
  }
}

async function ensureTapFlush() {
  if (tapFlushPromise) return tapFlushPromise;
  const generation = tapFlushGeneration;
  tapFlushPromise = (async () => {
    while (unackedTaps > 0) {
      if (generation !== tapFlushGeneration) return;
      try {
        const result = await callTap();
        if (generation !== tapFlushGeneration) return;
        const next = result.data.state;
        if (result.data.progress) playerProgress = result.data.progress;
        if (next.updatedAt) lastUpdatedAt = next.updatedAt;
        const afterTap = applyingManualTap(confirmedState);
        // Keep Stronger × combo tap units; do not reset the auto-fill clock.
        confirmedState = overlayLiveTapUnits(next, afterTap);
        unackedTaps = Math.max(0, unackedTaps - 1);
        windowEndHandled = false;
      } catch {
        if (generation !== tapFlushGeneration) return;
        unackedTaps = 0;
        try {
          await refresh(true);
        } catch {
          /* ignore */
        }
        return;
      }
    }
  })().finally(() => {
    tapFlushPromise = null;
  });
  return tapFlushPromise;
}

function applyState(state, force = false) {
  const incoming = state.updatedAt ?? null;
  if (!force && incoming && lastUpdatedAt && incoming < lastUpdatedAt) return;
  if (incoming) lastUpdatedAt = incoming;
  const prev = serverState;
  const preserveLiveTaps = !force && comboRecentlyTapped(confirmedState);
  const adopted = preserveLiveTaps
    ? overlayLiveTapUnits(state, confirmedState)
    : state;
  tapFlushGeneration += 1;
  unackedTaps = 0;
  confirmedState = adopted;
  serverState = adopted;
  if (!preserveLiveTaps) {
    anchorMs = Date.now();
  }
  windowEndHandled = false;

  const wrap = Boolean(prev && adopted.progress + 5 < (prev.progress ?? 0));
  const fillChanged = Boolean(prev && prev.fillRate !== adopted.fillRate);
  const powerChanged = Boolean(prev && prev.tapPower !== adopted.tapPower);
  const autoStarted = Boolean(adopted.autoFillActive && (!prev || !prev.autoFillActive));
  if (fillChanged || powerChanged) {
    rebaseKnockerClock(prev?.fillRate ?? lastFillRate);
  }
  if (!preserveLiveTaps) {
    syncDisplayAnchors(adopted.progress, {
      resetKnocker: autoStarted || !prev,
      wrap,
    });
  }
  lastFillRate = adopted.fillRate ?? 0;

  if (lastRenderedSats != null && adopted.satsBalance > lastRenderedSats) {
    celebrateSatEarn(adopted.satsBalance - lastRenderedSats);
  }
  lastRenderedSats = adopted.satsBalance;
  ensureLoop();
}

function ensureLoop() {
  if (!rafId) {
    const tick = (now) => {
      rafId = requestAnimationFrame(tick);
      if (!serverState) return;
      const projected = project(serverState, Date.now());
      // Detect sat earn from local projection (auto fill completing a bar).
      if (lastRenderedSats != null && projected.satsBalance > lastRenderedSats) {
        celebrateSatEarn(projected.satsBalance - lastRenderedSats);
      }
      lastRenderedSats = projected.satsBalance;
      renderFrame(projected, now);
    };
    rafId = requestAnimationFrame(tick);
  }
  if (refreshTimerId == null) {
    refreshTimerId = window.setInterval(async () => {
      if (!serverState) return;
      const now = Date.now();
      if (serverState.autoFillActive && !windowEndHandled) {
        const untilMs = parseMs(serverState.autoFillUntil);
        if (untilMs != null && now >= untilMs) {
          windowEndHandled = true;
          try {
            await refresh(true);
          } catch {
            /* ignore */
          }
        }
      }
    }, 1000);
  }
}

function boostVisual(running, enabled) {
  if (running && enabled) return "running-ready";
  if (running && !enabled) return "running-locked locked";
  if (enabled) return "ready";
  return "locked";
}

function renderRateLine(autoActive, fillRate, tapPower) {
  const power = tapPower > 0 ? tapPower : 1;
  const el = $("rate-line");
  if (!autoActive || fillRate <= 0) {
    if (power > 1.000000001) {
      el.innerHTML =
        `<span class="muted-part">Idle</span>` +
        `<span class="muted-part"> · </span>` +
        `<span class="power-part">${power.toFixed(2)} power</span>`;
    } else {
      el.innerHTML = `<span class="muted-part">Idle</span>`;
    }
    return;
  }
  const tps = fillRate / power;
  el.innerHTML =
    `<span class="speed-part">${tps.toFixed(2)} taps/s</span>` +
    `<span class="muted-part"> × </span>` +
    `<span class="power-part">${power.toFixed(2)} power</span>` +
    `<span class="muted-part"> = </span>` +
    `<span class="fill-part">${fillRate.toFixed(2)}/s</span>`;
}

function updateKnocker(pose, tapPower, autoActive) {
  const knocker = $("knocker");
  knocker.classList.toggle("idle", !autoActive);
  const strikeAngle = Math.atan2(
    KNOCKER.contact.y - KNOCKER.pivot.y,
    KNOCKER.contact.x - KNOCKER.pivot.x,
  );
  const armAngle = strikeAngle - (KNOCKER.sweepDeg * Math.PI) / 180 * (1 - pose.arm);
  const hitScale = autoActive ? knockerImpactScale(tapPower) : 1;
  const impact = autoActive ? pose.impact : 0;
  const kickX = -Math.cos(strikeAngle) * impact * 3 * hitScale;
  const kickY = -Math.sin(strikeAngle) * impact * 3 * hitScale;

  const mount = $("knocker-mount");
  mount.setAttribute("transform", `translate(${kickX} ${kickY})`);

  const arm = $("knocker-arm");
  const deg = (armAngle * 180) / Math.PI;
  arm.setAttribute(
    "transform",
    `translate(${KNOCKER.pivot.x} ${KNOCKER.pivot.y}) rotate(${deg})`,
  );

  const gearDeg = pose.phase * 360;
  $("drive-gear").setAttribute(
    "transform",
    `translate(346 58) rotate(${gearDeg})`,
  );
  $("idler-gear").setAttribute(
    "transform",
    `translate(364 58) rotate(${-gearDeg * (11 / 7)})`,
  );

  const flash = $("impact-flash");
  const r = impact > 0.05 ? 6 + impact * 10 * hitScale : 0;
  flash.setAttribute("cx", String(KNOCKER.strikePoint.x));
  flash.setAttribute("cy", String(KNOCKER.strikePoint.y));
  flash.setAttribute("r", String(r));
  flash.style.opacity = String(impact * 0.85);
}

function celebrateSatEarn(gained) {
  const now = Date.now();
  if (now - lastCelebrateAt < 400) return;
  lastCelebrateAt = now;
  wheelFlashUntil = now + 700;
  $("btn-redeem").classList.add("glow");
  window.setTimeout(() => $("btn-redeem").classList.remove("glow"), 900);

  const wheel = $("sat-wheel");
  const redeem = $("btn-redeem");
  const wr = wheel.getBoundingClientRect();
  const rr = redeem.getBoundingClientRect();
  const fromX = wr.left + wr.width / 2;
  const fromY = wr.top + 12;
  const toX = rr.left + rr.width / 2;
  const toY = rr.top + rr.height / 2;
  const layer = $("sat-particles");
  const count = Math.min(8, Math.max(3, gained));
  for (let i = 0; i < count; i++) {
    const el = document.createElement("div");
    el.className = "sat-particle";
    const ox = (Math.random() - 0.5) * 24;
    const oy = (Math.random() - 0.5) * 16;
    el.style.left = `${fromX + ox}px`;
    el.style.top = `${fromY + oy}px`;
    const dx = toX - fromX - ox;
    const dy = toY - fromY - oy;
    el.animate(
      [
        { transform: "translate(0,0) scale(1)", opacity: 1 },
        {
          transform: `translate(${dx * 0.45}px, ${dy * 0.35 - 40}px) scale(1.1)`,
          opacity: 1,
          offset: 0.45,
        },
        { transform: `translate(${dx}px, ${dy}px) scale(0.35)`, opacity: 0 },
      ],
      { duration: 850 + i * 40, easing: "cubic-bezier(0.2, 0.7, 0.2, 1)", fill: "forwards" },
    );
    layer.appendChild(el);
    window.setTimeout(() => el.remove(), 1000);
  }
}

function adsFooterText(state) {
  const adsMax = tunables?.adsPerCycle ?? 10;
  const regenLeft = state.adRegenSecondsLeft ?? 0;
  const adRegenSeconds = tunables?.adRegenSeconds ?? 0;
  if (state.adsRemainingToday <= 0) {
    if (regenLeft > 0) return `Next Boost Ad in ${formatCountdown(regenLeft)}`;
    if (adRegenSeconds <= 0) return "Ads refill when Auto ends";
    return "No ads available";
  }
  if (state.adCooldownSecondsLeft > 0) {
    return `Next Boost Ad in ${state.adCooldownSecondsLeft}s · ${state.adsRemainingToday}/${adsMax} ads`;
  }
  if (state.adsRemainingToday < adsMax && regenLeft > 0) {
    return `${state.adsRemainingToday}/${adsMax} ads · +1 in ${formatCountdown(regenLeft)}`;
  }
  return `${state.adsRemainingToday}/${adsMax} ads`;
}

function renderFrame(state, _rafNow) {
  if (!state) return;
  const nowMs = Date.now();
  const t = tunables;
  const total = Math.max(1, state.unitsPerSat || 1);
  const fillRate = state.fillRate ?? 0;
  const tapPower = state.tapPower > 0 ? state.tapPower : 1;
  const autoActive = Boolean(state.autoFillActive);

  // Mirror iOS onChange(progress): re-anchor when the projected bar wraps.
  if (state.progress + 5 < displayAnchorProgress) {
    syncDisplayAnchors(state.progress, { wrap: true });
  }

  const continuous = displayedBarProgress(
    state.progress,
    total,
    fillRate,
    autoActive,
    nowMs,
  );
  const knockerElapsed =
    autoActive && fillRate > 0 ? (nowMs - knockerAnchorMs) / 1000 : 0;
  const knockerProgress = knockerAnchorProgress + fillRate * knockerElapsed;
  const rawDisplay = struckSyncedProgress(
    continuous,
    knockerProgress,
    tapPower,
    autoActive,
    fillRate,
    total,
  );
  const display = holdMonotonicProgress(heldDisplay, rawDisplay);
  heldDisplay = display;
  const fraction = Math.min(1, Math.max(0, display / total));
  const tps = tapsPerSecond(fillRate, tapPower);
  const pose = knockerPose(knockerElapsed, knockerAnchorProgress, tps, tapPower, autoActive);

  $("btc-amount").textContent = formatBtcAmount(state.satsBalance, display, total);
  $("sats-per-hour").textContent = formatSatsPerHour(fillRate, total, autoActive);
  $("tap-count").textContent = `${display.toFixed(1)} / ${total} taps`;
  renderRateLine(autoActive, fillRate, tapPower);

  const arc = $("wheel-arc");
  arc.setAttribute("stroke-dasharray", `${fraction * 100} 100`);
  $("wheel-face").style.transform = `rotate(${fraction * 360}deg)`;
  const comboT = comboParams();
  const comboLive = comboAt(persistedCombo(state), nowMs, comboT);
  const meters = displayMeters(comboLive, comboT);
  const tracks = displayTracks(comboLive, comboT);
  function paintComboArc(id, glowId, frac, showTrack, bandId) {
    const el = $(id);
    if (!el) return;
    const drawArc = frac > 0.001;
    const dash = drawArc ? Math.min(1, frac) * 100 : 0;
    el.setAttribute("stroke-dasharray", `${dash} 100`);
    el.classList.toggle("hidden", !drawArc);
    const glow = glowId ? $(glowId) : null;
    if (glow) {
      glow.setAttribute("stroke-dasharray", `${dash} 100`);
      glow.classList.toggle("hidden", !drawArc);
      glow.style.opacity = drawArc && frac < 0.18 ? "0.5" : "";
    }
    const band = bandId ? $(bandId) : null;
    if (band) band.classList.toggle("hidden", !showTrack && !drawArc);
  }
  paintComboArc("combo-arc", "combo-glow-0", meters[0] || 0, true, "combo-band-0");
  paintComboArc("combo-arc-1", "combo-glow-1", meters[1] || 0, !!tracks[1], "combo-band-1");
  paintComboArc("combo-arc-2", "combo-glow-2", meters[2] || 0, !!tracks[2], "combo-band-2");
  const innerR = (tracks[2] || (meters[2] || 0) > 0.001)
    ? 66
    : (tracks[1] || (meters[1] || 0) > 0.001) ? 76 : 86;
  const pegOrbit = Math.max(35, innerR - 4 - 3.5 - 2);
  const peg = $("hub-peg");
  const pegSeat = document.querySelector(".hub-peg-seat");
  if (peg) peg.setAttribute("cy", String(110 - pegOrbit));
  if (pegSeat) pegSeat.setAttribute("cy", String(110 - pegOrbit));
  const pegOrbitEl = $("hub-peg-orbit");
  if (pegOrbitEl) pegOrbitEl.style.transform = `rotate(${fraction * 360}deg)`;
  const gear = $("combo-gear");
  if (gear) {
    gear.classList.toggle("hidden", !(tracks[0] || (meters[0] || 0) > 0.001));
    const gearRing = gear.querySelector(".combo-gear-ring");
    if (gearRing) gearRing.setAttribute("r", String(innerR - 5));
  }
  const comboBadge = $("combo-badge");
  if (comboBadge) {
    comboBadge.textContent = formatComboMultiplier(comboMultiplier(comboLive, comboT));
  }
  const titleEl = $("player-title");
  if (titleEl) {
    titleEl.textContent = minerTitle(playerProgress?.lifetimeSatsEarned || 0);
  }

  const flashing = nowMs < wheelFlashUntil;
  $("sat-wheel").classList.toggle("flashing", flashing);
  $("wheel-flash").classList.toggle("hidden", !flashing);

  updateKnocker(pose, tapPower, autoActive);

  $("taps-left").textContent =
    state.tapsRemaining > 0
      ? `Tap the wheel · ${state.tapsRemaining} taps left today`
      : "0 taps left today";

  const canWatch =
    !loading && state.adsRemainingToday > 0 && state.adCooldownSecondsLeft === 0;
  const canActivate =
    !loading && !state.autoFillActive && state.adCooldownSecondsLeft === 0;
  const canWatchSecondary = canWatch && state.autoFillActive;

  $("boost-caption").textContent = state.autoFillActive
    ? "Watch an Ad for a Boost"
    : "Watch an Ad to activate Auto Tapper";
  $("boost-row-active").classList.toggle("hidden", !state.autoFillActive);
  $("boost-row-idle").classList.toggle("hidden", state.autoFillActive);

  $("action-longer").textContent = formatLongerAction(t);
  $("action-faster").textContent = formatFasterAction(t);
  $("action-stronger").textContent = formatStrongerAction(t);
  $("action-activate").textContent = formatLongerAction(t);
  $("count-longer").textContent = `(${state.durationBoostCount ?? 0})`;
  $("count-faster").textContent = `(${state.speedBoostCount ?? 0})`;
  $("count-stronger").textContent = `(${state.tapStrengthBoostCount ?? 0})`;

  const longer = $("boost-longer");
  const faster = $("boost-faster");
  const stronger = $("boost-stronger");
  const activate = $("boost-activate");
  for (const [btn, running, enabled] of [
    [longer, state.durationBoostActive, canWatch],
    [faster, state.speedBoostActive, canWatchSecondary],
    [stronger, state.tapStrengthActive, canWatchSecondary],
  ]) {
    btn.className = `boost ${boostVisual(running, enabled)}`;
    btn.disabled = !enabled;
  }
  activate.className = `boost ${boostVisual(false, canActivate)}`;
  activate.disabled = !canActivate;

  const untilMs = parseMs(state.autoFillUntil);
  const left =
    state.autoFillActive && untilMs != null
      ? Math.max(0, Math.ceil((untilMs - Date.now()) / 1000))
      : 0;
  $("auto-timer").textContent = left > 0 ? `Auto ${formatCountdown(left)}` : "\u00a0";

  $("ads-footer").textContent = adsFooterText(state);

  const skipRegenLeft = state.skipAdRegenSecondsLeft ?? 0;
  const skipEnabled = (t?.skipAdsPerCycle ?? 10) >= 0;
  const skipVisible =
    skipEnabled &&
    state.adsRemainingToday <= 0 &&
    state.autoFillActive &&
    (state.skipAdsRemaining < 0 || state.skipAdsRemaining > 0 || skipRegenLeft > 0);
  const skipBtn = $("btn-skip");
  skipBtn.classList.toggle("hidden", !skipVisible);
  if (skipVisible) {
    const canSkip =
      !loading &&
      state.adCooldownSecondsLeft === 0 &&
      (state.skipAdsRemaining < 0 || state.skipAdsRemaining > 0);
    skipBtn.disabled = !canSkip;
    $("skip-action").textContent = formatSkipAction(t);
    if (state.adCooldownSecondsLeft > 0) {
      $("skip-remaining").textContent = `Next in ${state.adCooldownSecondsLeft}s`;
    } else if (state.skipAdsRemaining === 0 && skipRegenLeft > 0) {
      $("skip-remaining").textContent = `Next in ${formatCountdown(skipRegenLeft)}`;
    } else if (state.skipAdsRemaining < 0) {
      $("skip-remaining").textContent = "Unlimited";
    } else {
      $("skip-remaining").textContent = `${state.skipAdsRemaining} left`;
    }
  }

  $("btn-reset").classList.toggle("hidden", !t?.debugReset);

  // Redeem panel live balance (when open).
  if ($("redeem-dialog").open) {
    $("redeem-balance").textContent = formatSatsAsBtc(state.satsBalance);
    $("redeem-min").textContent =
      `Minimum withdrawal: ${formatSatsAsBtc(state.minWithdrawSats ?? 100)} BTC`;
  }
}

async function refresh(force = false) {
  const result = await callGetState();
  const data = result.data;
  tunables = data.tunables ?? null;
  playerProgress = data.progress ?? playerProgress;
  applyState(data.state, force);
}

async function ensureAuth() {
  if (auth.currentUser) return;
  await signInAnonymously(auth);
}

async function withBusy(fn) {
  setLoading(true);
  setError(null);
  try {
    await fn();
  } catch (e) {
    setError(e?.message || String(e));
  } finally {
    setLoading(false);
  }
}

function doTap() {
  if (!confirmedState || !serverState) return;
  if (serverState.tapsRemaining <= 0) return;
  unackedTaps += 1;
  const prevProgress = serverState.progress;
  serverState = applyingManualTap(serverState);
  const projected = project(serverState, Date.now());
  if (projected.progress + 5 < prevProgress) {
    syncDisplayAnchors(projected.progress, { wrap: true });
  } else {
    syncDisplayAnchors(projected.progress);
  }
  void ensureTapFlush();
}

$("sat-wheel").addEventListener("click", doTap);

async function watchBoost(boostType) {
  await withBusy(async () => {
    const result = await callBoost({ boostType });
    applyState(result.data.state, true);
  });
}

for (const id of ["boost-activate", "boost-longer", "boost-faster", "boost-stronger"]) {
  $(id).addEventListener("click", () => {
    const boost = $(id).dataset.boost;
    watchBoost(boost);
  });
}

$("btn-skip").addEventListener("click", () => watchBoost("skip_time"));

$("btn-reset").addEventListener("click", async () => {
  await withBusy(async () => {
    const result = await callReset();
    applyState(result.data.state, true);
  });
});

async function loadRedeemHistory() {
  const host = $("redeem-history");
  try {
    const result = await callMyWithdrawals();
    const list = result.data?.withdrawals ?? result.data ?? [];
    const rows = Array.isArray(list) ? list : [];
    if (rows.length === 0) {
      host.innerHTML = `<p class="muted">No withdrawals yet</p>`;
      return;
    }
    host.innerHTML = rows
      .map((w) => {
        const sats = w.amountSats ?? w.amount_sats ?? w.sats ?? 0;
        const status = w.status ?? "unknown";
        const created = w.createdAt ?? w.created_at ?? "";
        return (
          `<div class="history-row">` +
          `<strong>${formatSatsAsBtc(sats)} BTC · ${status}</strong>` +
          (created ? `<span>${created}</span>` : "") +
          `</div>`
        );
      })
      .join("");
  } catch {
    host.innerHTML = `<p class="muted">Couldn’t load history</p>`;
  }
}

$("btn-redeem").addEventListener("click", () => {
  $("redeem-error").hidden = true;
  $("redeem-success").hidden = true;
  if (serverState) {
    $("redeem-balance").textContent = formatSatsAsBtc(serverState.satsBalance);
    $("redeem-min").textContent =
      `Minimum withdrawal: ${formatSatsAsBtc(serverState.minWithdrawSats ?? 100)} BTC`;
    if (!$("redeem-amount").value) {
      $("redeem-amount").value = formatSatsAsBtc(serverState.minWithdrawSats ?? 100);
    }
  }
  $("redeem-dialog").showModal();
  void loadRedeemHistory();
});

$("redeem-amount").addEventListener("input", () => {
  const filtered = filterBtcInput($("redeem-amount").value);
  if (filtered !== $("redeem-amount").value) $("redeem-amount").value = filtered;
});

$("btn-redeem-howto").addEventListener("click", () => {
  $("redeem-howto-dialog").showModal();
});

$("btn-redeem-howto-close").addEventListener("click", () => {
  $("redeem-howto-dialog").close();
});

$("redeem-form").addEventListener("submit", async (ev) => {
  const submitter = ev.submitter;
  if (submitter?.value === "cancel") return;
  ev.preventDefault();
  const amountSats = parseBtcToSats($("redeem-amount").value);
  const bolt11 = String($("redeem-bolt11").value || "").trim();
  const err = $("redeem-error");
  const ok = $("redeem-success");
  err.hidden = true;
  ok.hidden = true;
  if (amountSats == null) {
    err.hidden = false;
    err.textContent = "Enter a valid BTC amount";
    return;
  }
  try {
    setLoading(true);
    const result = await callWithdraw({ amountSats, bolt11 });
    applyState(result.data.state, true);
    $("redeem-bolt11").value = "";
    $("redeem-amount").value = "";
    ok.hidden = false;
    await loadRedeemHistory();
  } catch (e) {
    err.hidden = false;
    err.textContent = e?.message || String(e);
  } finally {
    setLoading(false);
  }
});

onAuthStateChanged(auth, async (user) => {
  if (!user) return;
  try {
    setLoading(true);
    await refresh(true);
  } catch (e) {
    setError(e?.message || String(e));
  } finally {
    setLoading(false);
  }
});

setLoading(true);
ensureAuth().catch((e) => {
  setLoading(false);
  setError(e?.message || String(e));
});
