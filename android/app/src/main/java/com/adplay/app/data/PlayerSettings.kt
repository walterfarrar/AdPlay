package com.adplay.app.data

import android.content.Context

class PlayerSettings(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    var remindersEnabled: Boolean
        get() = prefs.getBoolean(REMINDERS, true)
        set(value) { prefs.edit().putBoolean(REMINDERS, value).apply() }

    var hapticsEnabled: Boolean
        get() = prefs.getBoolean(HAPTICS, true)
        set(value) { prefs.edit().putBoolean(HAPTICS, value).apply() }

    var soundEnabled: Boolean
        get() = prefs.getBoolean(SOUND, true)
        set(value) { prefs.edit().putBoolean(SOUND, value).apply() }

    var hasCompletedOnboarding: Boolean
        get() = prefs.getBoolean(ONBOARDING, false)
        set(value) { prefs.edit().putBoolean(ONBOARDING, value).apply() }

    fun unseenCompletedGoalCount(goals: List<DailyGoal>): Int {
        val seen = if (seenDay() == utcDayKey()) seenIds() else emptySet()
        return goals.count { it.completed && it.id !in seen }
    }

    fun acknowledgeDailyGoals(goals: List<DailyGoal>) {
        prefs.edit()
            .putString(SEEN_GOAL_DAY, utcDayKey())
            .putStringSet(SEEN_GOAL_IDS, goals.filter { it.completed }.map { it.id }.toSet())
            .apply()
    }

    private fun seenDay(): String = prefs.getString(SEEN_GOAL_DAY, "") ?: ""

    private fun seenIds(): Set<String> = prefs.getStringSet(SEEN_GOAL_IDS, emptySet()) ?: emptySet()

    companion object {
        private const val PREFS = "adplay_player"
        const val REMINDERS = "remindersEnabled"
        private const val HAPTICS = "hapticsEnabled"
        private const val SOUND = "soundEnabled"
        private const val ONBOARDING = "hasCompletedOnboarding"
        private const val SEEN_GOAL_DAY = "seenDailyGoalDay"
        private const val SEEN_GOAL_IDS = "seenDailyGoalIds"

        fun utcDayKey(): String {
            val cal = java.util.Calendar.getInstance(java.util.TimeZone.getTimeZone("UTC"))
            return String.format(
                "%04d-%02d-%02d",
                cal.get(java.util.Calendar.YEAR),
                cal.get(java.util.Calendar.MONTH) + 1,
                cal.get(java.util.Calendar.DAY_OF_MONTH),
            )
        }
    }
}
