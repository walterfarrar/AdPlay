package com.adplay.app.ads

import android.app.Activity
import android.content.Context
import com.adplay.app.AdPlayApp
import com.adplay.app.BuildConfig
import com.google.android.gms.ads.AdError
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.FullScreenContentCallback
import com.google.android.gms.ads.LoadAdError
import com.google.android.gms.ads.rewarded.RewardedAd
import com.google.android.gms.ads.rewarded.RewardedAdLoadCallback
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume

/**
 * Preloads one AdMob rewarded ad so boost taps can show immediately when ready.
 */
object AdMobRewarded {
    @Volatile private var cached: RewardedAd? = null
    @Volatile private var loading = false
    private val loadWaiters = mutableListOf<CompletableDeferred<RewardedAd?>>()

    fun preload(context: Context) {
        if (loading || cached != null) return
        val appCtx = context.applicationContext
        loading = true
        android.util.Log.i("AdPlayAds", "AdMob preload start unit=${BuildConfig.ADMOB_REWARDED_UNIT_ID}")
        RewardedAd.load(
            appCtx,
            BuildConfig.ADMOB_REWARDED_UNIT_ID,
            AdRequest.Builder().build(),
            object : RewardedAdLoadCallback() {
                override fun onAdFailedToLoad(error: LoadAdError) {
                    android.util.Log.w(
                        "AdPlayAds",
                        "AdMob preload failed code=${error.code} msg=${error.message}",
                    )
                    loading = false
                    finishLoad(null)
                }

                override fun onAdLoaded(ad: RewardedAd) {
                    android.util.Log.i("AdPlayAds", "AdMob preloaded")
                    loading = false
                    if (cached == null) cached = ad
                    finishLoad(ad)
                }
            },
        )
    }

    private fun finishLoad(ad: RewardedAd?) {
        val waiters: List<CompletableDeferred<RewardedAd?>>
        synchronized(loadWaiters) {
            waiters = loadWaiters.toList()
            loadWaiters.clear()
        }
        waiters.forEach { it.complete(ad) }
    }

    suspend fun present(activity: Activity? = null): AdFillResult {
        val act = activity ?: AdPlayApp.currentActivity()
        if (act == null) {
            android.util.Log.w("AdPlayAds", "AdMob skipped: no Activity")
            return AdFillResult.UNAVAILABLE
        }
        return withContext(Dispatchers.Main.immediate) {
            presentOn(act)
        }
    }

    private suspend fun presentOn(activity: Activity): AdFillResult {
        var ad = takeCached()

        if (ad == null) {
            if (loading) {
                android.util.Log.i("AdPlayAds", "AdMob waiting for in-flight preload")
                awaitLoadDone()
                ad = takeCached()
            } else {
                android.util.Log.i("AdPlayAds", "AdMob loading on demand")
                ad = loadNow(activity)
            }
        } else {
            android.util.Log.i("AdPlayAds", "AdMob showing preloaded ad")
        }

        if (ad == null) {
            preload(activity)
            return AdFillResult.UNAVAILABLE
        }

        val result = show(activity, ad)
        preload(activity)
        return result
    }

    private fun takeCached(): RewardedAd? {
        synchronized(this) {
            val ad = cached
            cached = null
            return ad
        }
    }

    private suspend fun awaitLoadDone() {
        val deferred = CompletableDeferred<Unit>()
        synchronized(loadWaiters) {
            if (!loading) return
            val bridge = CompletableDeferred<RewardedAd?>()
            loadWaiters.add(bridge)
            // Convert ad-waiter into a done-signal without claiming the ad.
            bridge.invokeOnCompletion { deferred.complete(Unit) }
        }
        deferred.await()
    }

    private suspend fun loadNow(context: Context): RewardedAd? =
        suspendCancellableCoroutine { cont ->
            loading = true
            RewardedAd.load(
                context,
                BuildConfig.ADMOB_REWARDED_UNIT_ID,
                AdRequest.Builder().build(),
                object : RewardedAdLoadCallback() {
                    override fun onAdFailedToLoad(error: LoadAdError) {
                        android.util.Log.w(
                            "AdPlayAds",
                            "AdMob load failed code=${error.code} domain=${error.domain} msg=${error.message}",
                        )
                        loading = false
                        finishLoad(null)
                        if (cont.isActive) cont.resume(null)
                    }

                    override fun onAdLoaded(ad: RewardedAd) {
                        loading = false
                        finishLoad(ad)
                        if (cont.isActive) cont.resume(ad)
                    }
                },
            )
            cont.invokeOnCancellation { /* SDK callback still fires; ignore */ }
        }

    private suspend fun show(activity: Activity, ad: RewardedAd): AdFillResult =
        suspendCancellableCoroutine { cont ->
            var earned = false
            var didPresent = false
            var finished = false

            fun finish(result: AdFillResult) {
                if (finished) return
                finished = true
                android.util.Log.i("AdPlayAds", "AdMob result=$result")
                if (cont.isActive) cont.resume(result)
            }

            ad.fullScreenContentCallback = object : FullScreenContentCallback() {
                override fun onAdShowedFullScreenContent() {
                    didPresent = true
                }

                override fun onAdDismissedFullScreenContent() {
                    finish(
                        when {
                            earned -> AdFillResult.EARNED
                            didPresent -> AdFillResult.DECLINED
                            else -> AdFillResult.UNAVAILABLE
                        },
                    )
                }

                override fun onAdFailedToShowFullScreenContent(error: AdError) {
                    android.util.Log.w(
                        "AdPlayAds",
                        "AdMob show failed code=${error.code} msg=${error.message}",
                    )
                    finish(AdFillResult.UNAVAILABLE)
                }
            }
            ad.show(activity) { earned = true }
            cont.invokeOnCancellation { finished = true }
        }
}
