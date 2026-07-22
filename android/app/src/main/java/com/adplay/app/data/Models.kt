package com.adplay.app.data
data class GameState(
    val progress: Double = 0.0,
    val unitsPerSat: Int = 1000,
    val satsBalance: Int = 0,
    val tapsRemaining: Int = 0,
    val adsRemainingToday: Int = 0,
    val satsEarnedToday: Int = 0,
    val dailySatsEarnCap: Int = 200,
    val autoFillActive: Boolean = false,
    val autoFillUntil: String? = null,
    val fillRate: Double = 0.0,
    val speedBoostActive: Boolean = false,
    val speedBoostUntil: String? = null,
    val tapStrengthActive: Boolean = false,
    val tapStrengthUntil: String? = null,
    val tapPower: Int = 1,
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
    val tapStrengthBoostAmount: Int = 1,
    val tapStrengthBoostSeconds: Int = 1200,
    val adCooldownSeconds: Int = 10,
    val dailyAdCap: Int = 30,
    val adsPerCycle: Int = 30,
    val dailySatsEarnCap: Int = 400,
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
}
