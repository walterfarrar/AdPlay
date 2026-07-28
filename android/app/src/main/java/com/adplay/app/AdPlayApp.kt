package com.adplay.app

import android.app.Activity
import android.app.Application
import android.os.Bundle
import com.adplay.app.ads.AdMobRewarded
import com.google.android.gms.ads.MobileAds
import java.lang.ref.WeakReference

class AdPlayApp : Application() {
    override fun onCreate() {
        super.onCreate()
        registerActivityLifecycleCallbacks(ActivityTracker)
        MobileAds.initialize(this) {
            AdMobRewarded.preload(this)
        }
    }

    companion object {
        fun currentActivity(): Activity? = ActivityTracker.current()
    }
}

private object ActivityTracker : Application.ActivityLifecycleCallbacks {
    private var ref: WeakReference<Activity>? = null

    fun current(): Activity? = ref?.get()?.takeUnless { it.isFinishing || it.isDestroyed }

    override fun onActivityResumed(activity: Activity) {
        ref = WeakReference(activity)
        if (activity is MainActivity) {
            AdMobRewarded.preload(activity)
        }
    }

    override fun onActivityPaused(activity: Activity) = Unit

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit
    override fun onActivityStarted(activity: Activity) = Unit
    override fun onActivityStopped(activity: Activity) = Unit
    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
    override fun onActivityDestroyed(activity: Activity) {
        if (ref?.get() === activity) ref = null
    }
}
