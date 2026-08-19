package com.adplay.app.notifications

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.adplay.app.MainActivity
import com.adplay.app.R
import com.adplay.app.data.GameState
import java.time.Instant
import kotlin.math.abs

/**
 * Local reminders keyed off Firebase server timestamps (autoFillUntil / nextAdChargeAt).
 * Device clock only affects *when the alarm fires*, not how much was earned.
 */
object GameReminderScheduler {
    const val CHANNEL_ID = "adplay_game"
    const val ACTION_FIRE = "com.adplay.app.REMINDER_FIRE"
    const val EXTRA_KIND = "kind"

    const val KIND_AUTO_ENDED = "auto_ended"
    const val KIND_ADS_AVAILABLE = "ads_available"

    private const val REQ_AUTO = 2001
    private const val REQ_ADS = 2002
    private const val NOTIF_AUTO = 1001
    private const val NOTIF_ADS = 1002

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val mgr = context.getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Game alerts",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "Auto timer and Boost Ad availability"
        }
        mgr.createNotificationChannel(channel)
    }

    fun clearAll(context: Context) {
        cancel(context, REQ_AUTO)
        cancel(context, REQ_ADS)
    }

    /** Reschedule from latest authoritative game state. */
    fun sync(context: Context, state: GameState) {
        val remindersOn = context.getSharedPreferences("adplay_player", Context.MODE_PRIVATE)
            .getBoolean("remindersEnabled", true)
        ensureChannel(context)
        cancel(context, REQ_AUTO)
        cancel(context, REQ_ADS)
        if (!remindersOn) return

        val now = System.currentTimeMillis()
        val autoAt = parseMillis(state.autoFillUntil)?.takeIf { state.autoFillActive }

        // Out of Boost Ads: notify when the next timed charge lands.
        val adsRefillAt = nextBoostAdRefillMs(state, now)

        val scheduleAuto = autoAt != null && autoAt > now + 2_000L
        val scheduleAds = adsRefillAt != null && adsRefillAt > now + 2_000L

        when {
            scheduleAuto && scheduleAds && abs(autoAt!! - adsRefillAt!!) < 1_500L -> {
                // Same moment — one combined alert
                schedule(
                    context = context,
                    requestCode = REQ_ADS,
                    triggerAtMs = adsRefillAt,
                    kind = KIND_ADS_AVAILABLE,
                )
            }
            else -> {
                if (scheduleAuto) {
                    schedule(context, REQ_AUTO, autoAt!!, KIND_AUTO_ENDED)
                }
                if (scheduleAds) {
                    schedule(context, REQ_ADS, adsRefillAt!!, KIND_ADS_AVAILABLE)
                }
            }
        }
    }

    /** Only when the bank is empty — first regen charge from 0 → 1. */
    private fun nextBoostAdRefillMs(state: GameState, nowMs: Long): Long? {
        if (state.adsRemainingToday > 0) return null
        parseMillis(state.nextAdChargeAt)?.let { return it }
        val regenLeft = state.adRegenSecondsLeft
        if (regenLeft <= 0) return null
        return nowMs + regenLeft * 1_000L
    }

    fun show(context: Context, kind: String) {
        ensureChannel(context)
        val (title, body, id) = when (kind) {
            KIND_AUTO_ENDED -> Triple(
                "Auto fill ended",
                "Your auto timer ran out.",
                NOTIF_AUTO,
            )
            KIND_ADS_AVAILABLE -> Triple(
                "Boost Ad ready",
                "A Boost Ad charged up — open AdPlay to use it.",
                NOTIF_ADS,
            )
            else -> return
        }

        val open = PendingIntent.getActivity(
            context,
            id,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_adplay)
            .setContentTitle(title)
            .setContentText(body)
            .setContentIntent(open)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()

        if (NotificationManagerCompat.from(context).areNotificationsEnabled()) {
            NotificationManagerCompat.from(context).notify(id, notification)
        }
    }

    private fun schedule(context: Context, requestCode: Int, triggerAtMs: Long, kind: String) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = pendingBroadcast(context, requestCode, kind)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
            } else {
                am.setExact(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
            }
        } catch (_: SecurityException) {
            // Exact alarms denied — fall back to inexact window
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pi)
        }
    }

    private fun cancel(context: Context, requestCode: Int) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val kind = if (requestCode == REQ_ADS) KIND_ADS_AVAILABLE else KIND_AUTO_ENDED
        am.cancel(pendingBroadcast(context, requestCode, kind))
    }

    private fun pendingBroadcast(context: Context, requestCode: Int, kind: String): PendingIntent {
        val intent = Intent(context, ReminderReceiver::class.java).apply {
            action = ACTION_FIRE
            putExtra(EXTRA_KIND, kind)
        }
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun parseMillis(iso: String?): Long? {
        if (iso.isNullOrBlank()) return null
        return try {
            Instant.parse(iso).toEpochMilli()
        } catch (_: Exception) {
            null
        }
    }
}
