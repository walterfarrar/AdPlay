package com.adplay.app.data
data class GameState(
    val progress: Double = 0.0,
    val unitsPerSat: Int = 1000,
    val satsBalance: Int = 0,
    val tapsRemaining: Int = 0,
    val adsRemainingToday: Int = 0,
    /** Seconds until the next regenerated ad charge. 0 if full / no regen. */
    val adRegenSecondsLeft: Int = 0,
    /** ISO when the next charge lands. */
    val nextAdChargeAt: String? = null,
    /** -1 means unlimited skip ads this run. */
    val skipAdsRemaining: Int = 0,
    /** Seconds until the next regenerated Skip charge. */
    val skipAdRegenSecondsLeft: Int = 0,
    /** ISO when the next Skip charge lands. */
    val nextSkipAdChargeAt: String? = null,
    val satsEarnedToday: Int = 0,
    val dailySatsEarnCap: Int = 0,
    val autoFillActive: Boolean = false,
    val autoFillUntil: String? = null,
    val fillRate: Double = 0.0,
    val speedBoostActive: Boolean = false,
    val speedBoostUntil: String? = null,
    val durationBoostActive: Boolean = false,
    val durationBoostCount: Int = 0,
    val speedBoostCount: Int = 0,
    val tapStrengthBoostCount: Int = 0,
    val tapStrengthActive: Boolean = false,
    val tapStrengthUntil: String? = null,
    val tapPower: Double = 1.0,
    val adCooldownSecondsLeft: Int = 0,
    val lastBoostType: String? = null,
    val minWithdrawSats: Int = 100,
    val resetHourUtc: Int = 0,
    val updatedAt: String? = null,
) {
    val progressFraction: Float
        get() = if (unitsPerSat <= 0) 0f else (progress / unitsPerSat).toFloat().coerceIn(0f, 1f)
}
data class Tunables(
    val unitsPerSat: Int = 1000,
    val tapUnits: Int = 1,
    val dailyTapCap: Int = 500,
    val durationBoostSeconds: Int = 1800,
    val speedBoostAmount: Double = 0.5,
    val speedBoostSeconds: Int = 1200,
    val tapStrengthBoostAmount: Double = 0.25,
    val tapStrengthBoostSeconds: Int = 1200,
    val adCooldownSeconds: Int = 10,
    val dailyAdCap: Int = 30,
    val adsPerCycle: Int = 10,
    /** Seconds between +1 ad charge. 0 = no timed regen. */
    val adRegenSeconds: Int = 1200,
    val skipTimeSeconds: Int = 60,
    /** 0 = unlimited skip ads after regular ads are out. */
    val skipAdsPerCycle: Int = 10,
    val dailySatsEarnCap: Int = 0,
    val minWithdrawSats: Int = 100,
    val resetHourUtc: Int = 0,
    val adProvider: String = "mock",
    val debugReset: Boolean = true,
)
data class Withdrawal(
    val id: String,
    val amount_sats: Int? = null,
    val amountSats: Int? = null,
    val bolt11: String? = null,
    val status: String,
    val admin_note: String? = null,
    val created_at: String? = null,
) {
    val sats: Int get() = amountSats ?: amount_sats ?: 0
}
enum class BoostType(val apiValue: String) {
    DURATION("duration"),
    SPEED("speed"),
    TAP_STRENGTH("tap_strength"),
    SKIP_TIME("skip_time"),
}
