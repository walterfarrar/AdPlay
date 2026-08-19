package com.adplay.app.data

import android.app.Activity
import android.content.Context
import android.content.Intent
import com.adplay.app.BuildConfig
import com.adplay.app.ads.AdFillResult
import com.adplay.app.ads.AdMobRewarded
import com.adplay.app.ads.AdsBitvexAdActivity
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.TimeoutCancellationException

/**
 * Partner abstraction.
 * Waterfall: AdMob rewarded, then AdsBitvex on no-fill.
 * Boost credit via mockCompleteBoost after a successful reward.
 */
interface AdServing {
    suspend fun showBoostAd(type: BoostType): AdCredit
}

private fun interface AdNetwork {
    suspend fun attempt(activity: Activity?): AdFillResult
}

class MockAdService(private val api: ApiClient) : AdServing {
    override suspend fun showBoostAd(type: BoostType): AdCredit {
        delay(1_200)
        return api.mockComplete(type)
    }
}

private class AdMobNetwork : AdNetwork {
    override suspend fun attempt(activity: Activity?): AdFillResult =
        AdMobRewarded.present(activity)
}

private class AdsBitvexNetwork(private val appContext: Context) : AdNetwork {
    override suspend fun attempt(activity: Activity?): AdFillResult {
        val deferred = CompletableDeferred<Boolean>()
        AdsBitvexAdActivity.pendingResult?.cancel()
        AdsBitvexAdActivity.pendingResult = deferred
        val intent = Intent(appContext, AdsBitvexAdActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        appContext.startActivity(intent)
        val ok = try {
            withTimeout(180_000) { deferred.await() }
        } catch (_: TimeoutCancellationException) {
            AdsBitvexAdActivity.pendingResult = null
            false
        }
        // WebView partner: treat failure as unavailable so waterfall can continue if more rungs exist.
        return if (ok) AdFillResult.EARNED else AdFillResult.UNAVAILABLE
    }
}

private class NetworkAdService(
    private val api: ApiClient,
    private val appContext: Context,
    private val network: AdNetwork,
) : AdServing {
    override suspend fun showBoostAd(type: BoostType): AdCredit {
        if (DebugAdBypass.isEnabled(appContext)) {
            return MockAdService(api).showBoostAd(type)
        }
        return when (network.attempt(null)) {
            AdFillResult.EARNED -> api.mockComplete(type)
            AdFillResult.DECLINED, AdFillResult.UNAVAILABLE ->
                throw ApiException(408, "Ad not completed")
        }
    }
}

private class WaterfallAdService(
    private val api: ApiClient,
    private val appContext: Context,
    private val networks: List<AdNetwork>,
) : AdServing {
    override suspend fun showBoostAd(type: BoostType): AdCredit {
        if (DebugAdBypass.isEnabled(appContext)) {
            return MockAdService(api).showBoostAd(type)
        }
        for ((index, network) in networks.withIndex()) {
            when (val result = network.attempt(null)) {
                AdFillResult.EARNED -> return api.mockComplete(type)
                AdFillResult.DECLINED -> throw ApiException(408, "Ad not completed")
                AdFillResult.UNAVAILABLE -> {
                    android.util.Log.i("AdPlayAds", "Waterfall rung $index unavailable, trying next")
                    continue
                }
            }
        }
        throw ApiException(408, "Ad not completed")
    }
}

object AdServiceFactory {
    fun make(api: ApiClient, provider: String, context: Context): AdServing {
        val app = context.applicationContext
        val key = provider.lowercase()
        android.util.Log.i("AdPlayAds", "AdServiceFactory provider=$key")
        return when (key) {
            // Never ship the mock provider in release — fall through to waterfall.
            "mock" -> if (BuildConfig.DEBUG) {
                MockAdService(api)
            } else {
                WaterfallAdService(
                    api,
                    app,
                    listOf(AdMobNetwork(), AdsBitvexNetwork(app)),
                )
            }
            "admob" -> NetworkAdService(api, app, AdMobNetwork())
            // Explicit Bitvex-only (skip AdMob). Prefer "waterfall" in production.
            "adsbitvex_only" -> NetworkAdService(api, app, AdsBitvexNetwork(app))
            // "adsbitvex" used to mean Bitvex-only; treat as waterfall so AdMob is tried first
            // even if an older backend still returns adProvider=adsbitvex.
            "waterfall", "adsbitvex" -> WaterfallAdService(
                api,
                app,
                listOf(AdMobNetwork(), AdsBitvexNetwork(app)),
            )
            else -> WaterfallAdService(
                api,
                app,
                listOf(AdMobNetwork(), AdsBitvexNetwork(app)),
            )
        }
    }

    /** Exposed for logs / UI. */
    fun configuredAppId(): String = BuildConfig.ADSBITVEX_APP_ID
}
