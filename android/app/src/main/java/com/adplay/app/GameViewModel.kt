package com.adplay.app

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.adplay.app.data.AdServiceFactory
import com.adplay.app.data.AdServing
import com.adplay.app.data.ApiClient
import com.adplay.app.data.BoostType
import com.adplay.app.data.DebugAdBypass
import com.adplay.app.data.GameState
import com.adplay.app.data.Tunables
import com.adplay.app.data.Withdrawal
import com.adplay.app.notifications.GameReminderScheduler
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.time.Instant
import kotlin.math.ceil
import kotlin.math.floor

data class UiState(
    val ready: Boolean = false,
    val loading: Boolean = false,
    val state: GameState = GameState(),
    val tunables: Tunables? = null,
    val error: String? = null,
    val withdrawals: List<Withdrawal> = emptyList(),
    val apiBaseUrl: String = "Firebase (adplay-sats)",
    /** Debug builds only — skip AdsBitvex and auto-credit boosts. */
    val bypassAdsAvailable: Boolean = DebugAdBypass.available,
    val bypassAds: Boolean = false,
)

class GameViewModel(app: Application) : AndroidViewModel(app) {
    private val api = ApiClient()
    private var ads: AdServing? = null
    private var tickerJob: Job? = null
    /** Drop stale responses that lost a race with a newer mutation. */
    private var lastUpdatedAt: String? = null
    private val appContext = app.applicationContext

    /**
     * Last authoritative snapshot from the server and the wall-clock instant it was
     * received. Everything shown while an auto window runs is projected locally from
     * this anchor, so we only hit Firebase on real changes — not on a timer.
     */
    private var serverState: GameState = GameState()
    private var anchorMs: Long = System.currentTimeMillis()
    private var windowEndHandled = false
    private var foreground = false

    private val _ui = MutableStateFlow(UiState())
    val ui: StateFlow<UiState> = _ui.asStateFlow()

    init {
        GameReminderScheduler.ensureChannel(appContext)
        _ui.update {
            it.copy(
                bypassAdsAvailable = DebugAdBypass.available,
                bypassAds = DebugAdBypass.isEnabled(appContext),
            )
        }
        start()
    }

    fun setBypassAds(enabled: Boolean) {
        if (!DebugAdBypass.available) return
        DebugAdBypass.setEnabled(appContext, enabled)
        _ui.update { it.copy(bypassAds = enabled) }
    }

    fun start() {
        viewModelScope.launch {
            _ui.update { it.copy(loading = true, error = null) }
            try {
                api.ensureSignedIn()
                refresh(force = true)
                _ui.update { it.copy(ready = true, loading = false) }
                foreground = true
                ensureTicker()
            } catch (e: Exception) {
                _ui.update {
                    it.copy(
                        loading = false,
                        error = e.message ?: "Failed to connect to Firebase",
                    )
                }
            }
        }
    }

    /** App came to the foreground: re-sync once with the server, then animate locally. */
    fun onForeground() {
        foreground = true
        if (!_ui.value.ready) return
        viewModelScope.launch { runCatching { refresh(force = true) } }
        ensureTicker()
    }

    /** App backgrounded: stop the local animation loop (no network was running anyway). */
    fun onBackground() {
        foreground = false
        tickerJob?.cancel()
    }

    fun clearError() {
        _ui.update { it.copy(error = null) }
    }

    fun tap() {
        if (_ui.value.state.tapsRemaining <= 0) return
        viewModelScope.launch {
            try {
                applyState(api.tap(), force = true)
            } catch (_: Exception) {
                // Out of taps / transient — stay quiet
            }
        }
    }

    fun watch(boost: BoostType) {
        viewModelScope.launch {
            _ui.update { it.copy(loading = true, error = null) }
            try {
                val service = ads ?: throw IllegalStateException("Ad service not ready")
                applyState(service.showBoostAd(boost), force = true)
                _ui.update { it.copy(loading = false) }
            } catch (e: Exception) {
                _ui.update { it.copy(loading = false, error = e.message) }
                runCatching { refresh(force = true) }
            }
        }
    }

    fun debugReset() {
        viewModelScope.launch {
            _ui.update { it.copy(loading = true, error = null) }
            try {
                applyState(api.debugReset(), force = true)
                _ui.update { it.copy(withdrawals = emptyList(), loading = false) }
            } catch (e: Exception) {
                _ui.update { it.copy(loading = false, error = e.message) }
            }
        }
    }

    fun withdraw(amountSats: Int, bolt11: String, onDone: (Boolean) -> Unit) {
        viewModelScope.launch {
            try {
                applyState(api.requestWithdrawal(amountSats, bolt11), force = true)
                val history = api.myWithdrawals()
                _ui.update { it.copy(withdrawals = history, error = null) }
                onDone(true)
            } catch (e: Exception) {
                _ui.update { it.copy(error = e.message) }
                onDone(false)
            }
        }
    }

    fun loadWithdrawals() {
        viewModelScope.launch {
            runCatching {
                val history = api.myWithdrawals()
                _ui.update { it.copy(withdrawals = history) }
            }
        }
    }

    private suspend fun refresh(force: Boolean = false) {
        val (state, tunables) = api.fetchState()
        ads = AdServiceFactory.make(api, tunables?.adProvider ?: "adsbitvex", appContext)
        applyState(state, force = force)
        _ui.update { it.copy(tunables = tunables, error = null) }
    }

    /**
     * Apply an authoritative server snapshot: it always wins over any locally
     * projected values, so a tampered client can never keep fake progress/balance.
     */
    private fun applyState(state: GameState, force: Boolean) {
        val incoming = state.updatedAt
        val prev = lastUpdatedAt
        if (!force && incoming != null && prev != null && incoming < prev) {
            return // stale response lost a race with a newer tap/boost
        }
        if (incoming != null) lastUpdatedAt = incoming
        serverState = state
        anchorMs = System.currentTimeMillis()
        windowEndHandled = false
        _ui.update { it.copy(state = state) }
        GameReminderScheduler.sync(appContext, state)
        ensureTicker()
    }

    /**
     * Local, network-free animation loop. While an auto window is running everything
     * is deterministic (progress = fillRate x elapsed, cooldown counts down), so we
     * project from the last server snapshot instead of polling. When the window ends
     * we hit the server exactly once to pull the authoritative reset (ads refilled).
     */
    private fun ensureTicker() {
        if (!foreground) return
        if (tickerJob?.isActive == true) return
        tickerJob = viewModelScope.launch {
            while (isActive && foreground) {
                val now = System.currentTimeMillis()
                val projected = project(serverState, now)
                _ui.update { it.copy(state = projected) }

                if (serverState.autoFillActive && !windowEndHandled) {
                    val untilMs = parseMs(serverState.autoFillUntil)
                    if (untilMs != null && now >= untilMs) {
                        windowEndHandled = true
                        runCatching { refresh(force = true) }
                    }
                }

                val shown = _ui.value.state
                if (!shown.autoFillActive && shown.adCooldownSecondsLeft <= 0) break
                delay(1_000)
            }
        }
    }

    /** Project a server snapshot forward by wall-clock elapsed time (display only). */
    private fun project(s: GameState, nowMs: Long): GameState {
        val elapsedSec = (nowMs - anchorMs).coerceAtLeast(0L) / 1000.0
        val cooldown = ceil(s.adCooldownSecondsLeft - elapsedSec).toInt().coerceAtLeast(0)
        val untilMs = parseMs(s.autoFillUntil)
        val autoActive = s.autoFillActive && untilMs != null && untilMs > nowMs

        if (!s.autoFillActive || s.fillRate <= 0.0 || s.unitsPerSat <= 0 || untilMs == null) {
            return s.copy(
                adCooldownSecondsLeft = cooldown,
                autoFillActive = autoActive,
                durationBoostActive = if (autoActive) s.durationBoostActive else false,
                speedBoostActive = if (autoActive) s.speedBoostActive else false,
                tapStrengthActive = if (autoActive) s.tapStrengthActive else false,
                durationBoostCount = if (autoActive) s.durationBoostCount else 0,
                speedBoostCount = if (autoActive) s.speedBoostCount else 0,
                tapStrengthBoostCount = if (autoActive) s.tapStrengthBoostCount else 0,
            )
        }

        val earnUntil = minOf(nowMs, untilMs)
        val earnSec = (earnUntil - anchorMs).coerceAtLeast(0L) / 1000.0
        val total = s.progress + s.fillRate * earnSec
        var bars = floor(total / s.unitsPerSat).toInt().coerceAtLeast(0)
        val maxBars = (s.dailySatsEarnCap - s.satsEarnedToday).coerceAtLeast(0)
        if (bars > maxBars) bars = maxBars
        val newProgress = (total - bars.toDouble() * s.unitsPerSat)
            .coerceIn(0.0, s.unitsPerSat.toDouble())

        return s.copy(
            progress = newProgress,
            satsBalance = s.satsBalance + bars,
            satsEarnedToday = s.satsEarnedToday + bars,
            adCooldownSecondsLeft = cooldown,
            autoFillActive = autoActive,
            durationBoostActive = if (autoActive) s.durationBoostActive else false,
            speedBoostActive = if (autoActive) s.speedBoostActive else false,
            tapStrengthActive = if (autoActive) s.tapStrengthActive else false,
            durationBoostCount = if (autoActive) s.durationBoostCount else 0,
            speedBoostCount = if (autoActive) s.speedBoostCount else 0,
            tapStrengthBoostCount = if (autoActive) s.tapStrengthBoostCount else 0,
        )
    }

    private fun parseMs(iso: String?): Long? =
        iso?.let { runCatching { Instant.parse(it).toEpochMilli() }.getOrNull() }
}
