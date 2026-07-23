package com.adplay.app.data

import android.content.Context
import com.adplay.app.BuildConfig

/**
 * Runtime ad bypass for debug builds. When enabled, boost buttons skip AdsBitvex
 * and credit via mockComplete (cooldown / timers still apply).
 *
 * Compile gate: only available when [BuildConfig.DEBUG_BYPASS_ADS] is true.
 * Preference defaults to on so debug installs skip ads until you turn it off in-app.
 */
object DebugAdBypass {
    private const val PREFS = "adplay_debug"
    private const val KEY = "bypass_ads"

    /** Feature compiled into this APK (debug builds). */
    val available: Boolean get() = BuildConfig.DEBUG_BYPASS_ADS

    fun isEnabled(context: Context): Boolean {
        if (!available) return false
        return prefs(context).getBoolean(KEY, true)
    }

    fun setEnabled(context: Context, enabled: Boolean) {
        if (!available) return
        prefs(context).edit().putBoolean(KEY, enabled).apply()
    }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
