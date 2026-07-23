package com.adplay.app.data

import android.content.Context
import android.content.Intent
import com.adplay.app.BuildConfig
import com.adplay.app.ads.AdsBitvexAdActivity
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.TimeoutCancellationException

/**
 * Partner abstraction.
 * Mock: short delay then server credit.
 * AdsBitvex: WebView JS reward ad, then server credit (no S2S from partner).
 */
interface AdServing {
    suspend fun showBoostAd(type: BoostType): GameState
}

class MockAdService(private val api: ApiClient) : AdServing {
    override suspend fun showBoostAd(type: BoostType): GameState {
        delay(1_200)
        return api.mockComplete(type)
    }
}

class AdsBitvexAdService(
    private val api: ApiClient,
    private val appContext: Context,
) : AdServing {
    override suspend fun showBoostAd(type: BoostType): GameState {
        if (DebugAdBypass.isEnabled(appContext)) {
            return MockAdService(api).showBoostAd(type)
        }
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
        if (!ok) {
            throw ApiException(408, "Ad not completed")
        }
        return api.mockComplete(type)
    }
}

class PartnerAdService(private val api: ApiClient) : AdServing {
    override suspend fun showBoostAd(type: BoostType): GameState {
        throw ApiException(501, "Partner SDK not configured.")
    }
}

object AdServiceFactory {
    fun make(api: ApiClient, provider: String, context: Context): AdServing {
        return when (provider.lowercase()) {
            "mock" -> MockAdService(api)
            "adsbitvex" -> AdsBitvexAdService(api, context.applicationContext)
            else -> AdsBitvexAdService(api, context.applicationContext)
        }
    }

    /** Exposed for logs / UI. */
    fun configuredAppId(): String = BuildConfig.ADSBITVEX_APP_ID
}
