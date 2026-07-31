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
let anchorMs = 0;
let lastUpdatedAt = null;
let windowEndHandled = false;
let tickerId = null;
let loading = false;

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
  // When the shared auto window just ended, show a full ad bank until refresh lands.
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
    // Disabled
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
  const power = s.tapPower > 0 ? s.tapPower : 1;
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
  };
}

function publishOptimisticTaps() {
  if (!confirmedState) return;
  let s = confirmedState;
  for (let i = 0; i < unackedTaps; i++) s = applyingManualTap(s);
  serverState = s;
  render(project(s, Date.now()));
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
        if (next.updatedAt) lastUpdatedAt = next.updatedAt;
        confirmedState = next;
        unackedTaps = Math.max(0, unackedTaps - 1);
        // Confirmed snapshot already includes auto catch-up through now.
        anchorMs = Date.now();
        windowEndHandled = false;
        publishOptimisticTaps();
        ensureTicker();
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
  tapFlushGeneration += 1;
  unackedTaps = 0;
  confirmedState = state;
  serverState = state;
  anchorMs = Date.now();
  windowEndHandled = false;
  render(project(serverState, Date.now()));
  ensureTicker();
}

function ensureTicker() {
  if (tickerId != null) return;
  tickerId = window.setInterval(async () => {
    if (!serverState) return;
    const now = Date.now();
    const projected = project(serverState, now);
    render(projected);

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

    if (!projected.autoFillActive && projected.adCooldownSecondsLeft <= 0) {
      window.clearInterval(tickerId);
      tickerId = null;
    }
  }, 1000);
}

function boostVisual(running, enabled) {
  if (running && enabled) return "running-ready";
  if (running && !enabled) return "running-locked locked";
  if (enabled) return "ready";
  return "locked";
}

function render(state) {
  if (!state) return;
  const t = tunables;
  const canWatch =
    !loading && state.adsRemainingToday > 0 && state.adCooldownSecondsLeft === 0;

  $("balance").textContent = `${state.satsBalance} sats`;
  $("sats-per-hour").textContent = formatSatsPerHour(
    state.fillRate,
    state.unitsPerSat,
    state.autoFillActive
  );
  $("bar-count").textContent = `${Math.floor(state.progress)} / ${state.unitsPerSat} taps`;

  const tps = tapsPerSecond(state.fillRate, state.tapPower);
  const rateEl = $("bar-rate");
  if (state.autoFillActive && tps > 0) {
    rateEl.textContent = `${tps.toFixed(2)} taps/s`;
    rateEl.style.color = "var(--speed)";
  } else {
    rateEl.textContent = "";
  }

  const frac = state.unitsPerSat > 0 ? state.progress / state.unitsPerSat : 0;
  $("progress-fill").style.width = `${Math.max(4, Math.min(100, frac * 100))}%`;

  $("taps-left").textContent =
    state.tapsRemaining > 0
      ? `Tap the bar · ${state.tapsRemaining} taps left today`
      : "0 taps left today";

  $("action-longer").textContent = formatLongerAction(t);
  $("action-faster").textContent = formatFasterAction(t);
  $("action-stronger").textContent = formatStrongerAction(t);
  $("count-longer").textContent = `(${state.durationBoostCount ?? 0})`;
  $("count-faster").textContent = `(${state.speedBoostCount ?? 0})`;
  $("count-stronger").textContent = `(${state.tapStrengthBoostCount ?? 0})`;

  const longer = $("boost-longer");
  const faster = $("boost-faster");
  const stronger = $("boost-stronger");
  for (const [btn, running] of [
    [longer, state.durationBoostActive],
    [faster, state.speedBoostActive],
    [stronger, state.tapStrengthActive],
  ]) {
    btn.className = `boost ${boostVisual(running, canWatch)}`;
    btn.disabled = !canWatch;
  }

  const untilMs = parseMs(state.autoFillUntil);
  const left =
    state.autoFillActive && untilMs != null
      ? Math.max(0, Math.ceil((untilMs - Date.now()) / 1000))
      : 0;
  $("auto-timer").textContent = left > 0 ? `Auto ${formatCountdown(left)}` : "\u00a0";

  const regenLeft = state.adRegenSecondsLeft ?? 0;
  const adRegenSeconds = t?.adRegenSeconds ?? 0;
  let footer;
  if (state.adsRemainingToday <= 0) {
    if (regenLeft > 0) {
      footer = `Next Boost Ad in ${formatCountdown(regenLeft)}`;
    } else if (adRegenSeconds <= 0) {
      footer = "Ads refill when Auto ends";
    } else {
      footer = "No ads available";
    }
  } else if (state.adCooldownSecondsLeft > 0) {
    footer = `Next Boost Ad in ${state.adCooldownSecondsLeft}s · ${state.adsRemainingToday} ads left`;
  } else {
    footer = `${state.adsRemainingToday} ads left this run`;
  }
  $("ads-footer").textContent = footer;

  const skipRegenLeft = state.skipAdRegenSecondsLeft ?? 0;
  // skipAdsPerCycle < 0 disables Skip Time entirely.
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
  $("redeem-amount").min = String(state.minWithdrawSats ?? 100);
  if (!$("redeem-amount").value) {
    $("redeem-amount").value = String(state.minWithdrawSats ?? 100);
  }
}

async function refresh(force = false) {
  const result = await callGetState();
  const data = result.data;
  tunables = data.tunables ?? null;
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

$("progress-bar").addEventListener("click", () => {
  if (!confirmedState) return;
  let probe = confirmedState;
  for (let i = 0; i < unackedTaps; i++) probe = applyingManualTap(probe);
  if (probe.tapsRemaining <= 0) return;
  unackedTaps += 1;
  publishOptimisticTaps();
  void ensureTapFlush();
});

async function watchBoost(boostType) {
  await withBusy(async () => {
    // Browser build uses mockCompleteBoost (same as Android debug bypass).
    const result = await callBoost({ boostType });
    applyState(result.data.state, true);
  });
}

for (const id of ["boost-longer", "boost-faster", "boost-stronger"]) {
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

$("btn-redeem").addEventListener("click", () => {
  $("redeem-error").hidden = true;
  $("redeem-dialog").showModal();
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
  const amountSats = Number($("redeem-amount").value);
  const bolt11 = String($("redeem-bolt11").value || "").trim();
  const err = $("redeem-error");
  err.hidden = true;
  try {
    setLoading(true);
    const result = await callWithdraw({ amountSats, bolt11 });
    applyState(result.data.state, true);
    $("redeem-dialog").close();
    $("redeem-bolt11").value = "";
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
