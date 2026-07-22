/**
 * Server-side game tunables.
 * Adjust after real eCPM data so sats paid out stay under net ad revenue.
 */
export const gameConfig = {
  /** Progress units required to credit 1 sat */
  unitsPerSat: 1000,

  /** Progress added per manual tap */
  tapUnits: 1,

  /** Max manual taps per UTC day */
  dailyTapCap: 500,

  /** UTC hour (0–23) when tap/ad/sats daily counters reset */
  resetHourUtc: Number(process.env.RESET_HOUR_UTC ?? 0),

  /**
   * Base fill rate (taps/sec) while auto-fill is active with no Faster stacks.
   * 0 so rate comes only from Faster ads (first Faster = 0.15 taps/s).
   */
  baseFillRate: 0,

  /** Duration ad: seconds of auto-fill added (+20 min, stacks onto remaining) */
  durationBoostSeconds: 30 * 60,

  /**
   * Speed ad: additive fill-rate boost (taps/sec); stacks additively.
   * Applies for the whole shared auto window (no separate Faster timer).
   */
  speedBoostAmount: 0.5,

  /** @deprecated Unused — Faster no longer has its own timer; kept for config compat */
  speedBoostSeconds: 20 * 60,

  /** Stronger ad: additive units per manual tap; stacks like Faster */
  tapStrengthBoostAmount: 1,

  /** How long each Stronger extends the tap-strength window */
  tapStrengthBoostSeconds: 20 * 60,

  /** Minimum seconds between rewarded ad grants per user */
  adCooldownSeconds: 10,

  /** Max rewarded ads per run; refreshes when auto duration fully expires */
  adsPerCycle: 30,

  /** Max sats earnable from bar completions per UTC day (~10 sats/ad headroom) */
  dailySatsEarnCap: 400,

  /** Minimum sats for a withdrawal request */
  minWithdrawSats: Number(process.env.MIN_WITHDRAW_SATS ?? 100),

  /** Economics notes (documentation only) */
  economicsNote:
    "Target ~10 sats expected value per completed rewarded ad (Longer or Faster alone). At ~$0.015 eCPM and ~$0.001/sat, that is aggressive — watch real revenue before raising further.",
} as const;

export type BoostType = "duration" | "speed" | "tap_strength";
