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

    /** Local preview of one manual tap (matches server `applyManualTapInMemory`). */
    fun applyingManualTap(): GameState {
        if (tapsRemaining <= 0) return this
        val units = unitsPerSat.coerceAtLeast(1)
        var nextProgress = progress + tapPower.coerceAtLeast(0.0)
        var earned = 0
        while (nextProgress >= units) {
            if (dailySatsEarnCap > 0 && satsEarnedToday + earned >= dailySatsEarnCap) {
                nextProgress = units - 0.0001
                break
            }
            nextProgress -= units
            earned += 1
        }
        return copy(
            tapsRemaining = tapsRemaining - 1,
            progress = nextProgress,
            satsBalance = satsBalance + earned,
            satsEarnedToday = satsEarnedToday + earned,
        )
    }
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
    val adsPerCycle: Int = 5,
    /** Seconds between +1 ad charge. 0 = no timed regen. */
    val adRegenSeconds: Int = 1200,
    val skipTimeSeconds: Int = 60,
    /** 0 = unlimited; -1 = disabled (Skip Time hidden). */
    val skipAdsPerCycle: Int = 10,
    val dailySatsEarnCap: Int = 0,
    val minWithdrawSats: Int = 100,
    val resetHourUtc: Int = 0,
    val adProvider: String = "waterfall",
    val debugReset: Boolean = false,
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
data class AdBankBreakdown(
    val base: Int = 5,
    val dailyBonus: Int = 0,
    val streakBonus: Int = 0,
    val achievementBonus: Int = 0,
    val iapBonus: Int = 0,
    val max: Int = 5,
)

data class DailyGoal(
    val id: String = "",
    val title: String = "",
    val current: Int = 0,
    val target: Int = 1,
    val completed: Boolean = false,
    val rewardAds: Int = 1,
)

data class Achievement(
    val id: String = "",
    val title: String = "",
    val detail: String = "",
    val unlocked: Boolean = false,
    val grantsSlot: Boolean = false,
)

data class PlayerProgress(
    val adBank: AdBankBreakdown = AdBankBreakdown(),
    val loginStreak: Int = 0,
    val bestLoginStreak: Int = 0,
    val dailyGoals: List<DailyGoal> = emptyList(),
    val achievements: List<Achievement> = emptyList(),
    val iapAdsPurchased: Int = 0,
    val iapBonusAdsMax: Int = 5,
) {
    val displayedDailyGoals: List<DailyGoal> get() = ProgressCatalog.goals(dailyGoals)
    val displayedAchievements: List<Achievement> get() = ProgressCatalog.achievements(achievements)

    fun takingServer(server: PlayerProgress?): PlayerProgress {
        if (server == null || (server.dailyGoals.isEmpty() && server.achievements.isEmpty())) {
            return this
        }
        return server
    }

    fun syncedWith(state: GameState, tunables: Tunables?, adsWatched: Int): PlayerProgress {
        val cap = (tunables?.dailyTapCap ?: 500).coerceAtLeast(1)
        val tapsUsed = (cap - state.tapsRemaining).coerceAtLeast(0)
        val auto = if (state.autoFillActive || state.lastBoostType == "activate") 1 else 0
        val next = displayedDailyGoals.map { goal ->
            val derived = when (goal.id) {
                "taps", "taps_stretch" -> tapsUsed
                "sats" -> state.satsEarnedToday.coerceAtLeast(0)
                "auto" -> auto
                "ads" -> adsWatched
                else -> goal.current
            }
            goal.copy(current = derived, completed = derived >= goal.target)
        }
        val daily = next.count { it.completed }.coerceAtMost(5)
        return copy(
            dailyGoals = next,
            adBank = adBank.copy(
                dailyBonus = daily,
                max = adBank.base + maxOf(adBank.dailyBonus, daily) + adBank.streakBonus
                    + adBank.achievementBonus + adBank.iapBonus,
            ),
        )
    }
}

data class StreakMilestone(
    val day: Int,
    val caption: String,
) {
    val grantsHold: Boolean get() = caption.isNotEmpty()
    val isLongRun: Boolean get() = day >= 30
}

object ProgressCatalog {
    val streakMilestones: List<StreakMilestone> = listOf(
        StreakMilestone(1, "+1"),
        StreakMilestone(2, ""),
        StreakMilestone(3, "+1"),
        StreakMilestone(4, ""),
        StreakMilestone(5, "+1"),
        StreakMilestone(7, "+1"),
        StreakMilestone(30, "+1"),
    )

    private val streakEarlyDays = listOf(1, 2, 3, 4, 5, 7)
    private const val streakEarlySpan = 0.64f

    /** Days 1–7 sit in the first stretch; 7→30 is a long fill with no extra dots. */
    fun streakRailX(day: Int): Float {
        val index = streakEarlyDays.indexOf(day)
        if (index >= 0) return index.toFloat() / (streakEarlyDays.size - 1) * streakEarlySpan
        if (day >= 30) return 1f
        if (day > 7) return streakEarlySpan + (day - 7).toFloat() / 23f * (1f - streakEarlySpan)
        return 0f
    }

    fun streakTrackFill(days: Int): Float {
        if (days <= 0) return 0f
        if (days >= 30) return 1f
        var prev = 0
        var prevX = 0f
        for (day in streakMilestones.map { it.day }) {
            val x = streakRailX(day)
            if (days < day) {
                val span = (day - prev).coerceAtLeast(1)
                val local = (days - prev).toFloat() / span
                return prevX + local * (x - prevX)
            }
            prev = day
            prevX = x
        }
        return 1f
    }

    val dailyGoals: List<DailyGoal> = listOf(
        DailyGoal(id = "taps", title = "Use taps", target = 50),
        DailyGoal(id = "ads", title = "Watch boost ads", target = 3),
        DailyGoal(id = "sats", title = "Earn sats", target = 1),
        DailyGoal(id = "auto", title = "Start Auto Tapper", target = 1),
        DailyGoal(id = "taps_stretch", title = "Keep tapping", target = 200),
    )

    private val goalHowTo = mapOf(
        "taps" to "Tap the wheel 50 times today.",
        "ads" to "Watch 3 boost ads today (Activate, Longer, Faster, Stronger, or Skip Time).",
        "sats" to "Fill the wheel and earn 1 sat today.",
        "auto" to "Watch Activate to start Auto Tapper today.",
        "taps_stretch" to "Tap the wheel 200 times today.",
    )

    val achievements: List<Achievement> = listOf(
        Achievement("first_sat", "First sat", "Fill the wheel until it credits 1 sat.", false, true),
        Achievement("first_auto", "Auto Tapper", "Watch Activate to start Auto Tapper for the first time.", false, true),
        Achievement("first_redeem", "First payout", "Submit a Lightning redeem and wait until it is marked paid.", false, true),
        Achievement("lifetime_50", "50 sats", "Earn 50 sats over your lifetime.", false, true),
        Achievement("lifetime_500", "500 sats", "Earn 500 sats over your lifetime.", false, true),
    )

    fun howTo(goal: DailyGoal): String =
        goalHowTo[goal.id] ?: "Reach ${goal.target} to complete this goal."

    fun goals(live: List<DailyGoal>): List<DailyGoal> {
        val byId = live.associateBy { it.id }
        val seen = mutableSetOf<String>()
        val out = mutableListOf<DailyGoal>()
        for (template in dailyGoals) {
            seen += template.id
            val found = byId[template.id]
            out += if (found != null) {
                found.copy(
                    title = found.title.ifBlank { template.title },
                    target = if (found.target > 0) found.target else template.target,
                )
            } else {
                template
            }
        }
        live.filter { it.id !in seen }.forEach { out += it }
        return out
    }

    fun achievements(live: List<Achievement>): List<Achievement> {
        val byId = live.associateBy { it.id }
        val seen = mutableSetOf<String>()
        val out = mutableListOf<Achievement>()
        for (template in achievements) {
            seen += template.id
            val found = byId[template.id]
            out += if (found != null) {
                found.copy(
                    title = found.title.ifBlank { template.title },
                    detail = found.detail.ifBlank { template.detail },
                )
            } else {
                template
            }
        }
        live.filter { it.id !in seen }.forEach { out += it }
        return out
    }
}

data class AdCredit(
    val state: GameState,
    val progress: PlayerProgress? = null,
)

enum class BoostType(val apiValue: String) {
    ACTIVATE("activate"),
    DURATION("duration"),
    SPEED("speed"),
    TAP_STRENGTH("tap_strength"),
    SKIP_TIME("skip_time"),
}
