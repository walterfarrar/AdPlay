package com.adplay.app.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != GameReminderScheduler.ACTION_FIRE) return
        val kind = intent.getStringExtra(GameReminderScheduler.EXTRA_KIND) ?: return
        GameReminderScheduler.show(context, kind)
    }
}
