package com.adplay.app

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.adplay.app.ads.AdMobRewarded
import com.adplay.app.data.AdServiceFactory
import com.adplay.app.data.AdServing
import com.adplay.app.data.ApiClient
import com.adplay.app.data.BoostType
import com.adplay.app.data.DebugAdBypass
import com.adplay.app.data.GameState
import com.adplay.app.data.PlayerProgress
import com.adplay.app.data.PlayerSettings
import com.adplay.app.data.Tunables
import com.adplay.app.data.Withdrawal
import com.adplay.app.data.parseIso8601Millis
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
import kotlin.math.roundToInt

data class UiState(
    val ready: Boolean = false,
    val loading: Boolean = false,
    val state: GameState = GameState(),
    val tunables: Tunables? = null,
    val error: String? = null,
    val withdrawals: List<Withdrawal> = emptyList(),
    val apiBaseUrl: String = "Firebase (adplay-sats)",
    /** Debug builds only — skip live ads and auto-credit boosts. */
    val bypassAdsAvailable: Boolean = DebugAdBypass.available,
    val bypassAds: Boolean = false,
    val progress: PlayerProgress = PlayerProgress(),
    val hasCompletedOnboarding: Boolean = false,
    val remindersEnabled: Boolean = true,
    val hapticsEnabled: Boolean = true,
    val soundEnabled: Boolean = true,
    val playerId: String = "",
    val unseenDailyGoalCount: Int = 0,
    /** Rewarded ad is presenting — keep boost buttons disabled without a spinner overlay. */
    val watchingAd: Boolean = false,
)

class GameViewModel(app: Application) : AndroidViewModel(app) {
    private val api = ApiClient()
    private var ads: AdServing? = null
    private var tickerJob: Job? = null
    /** Drop stale responses that lost a race with a newer mutation. */
    private var lastUpdatedAt: String? = null
    private val appContext = app.applicationContext
    private val settings = PlayerSettings(appContext)

    /**
     * Last authoritative snapshot from the server and the wall-clock instant it was
     * received. Everything shown while an auto window runs is projected locally from
     * this anchor, so we only hit Firebase on real changes — not on a timer.
     */
    private var serverState: GameState = GameState()
    /** Last fully-acked server snapshot (excludes optimistic taps still in flight). */
    private var confirmedState: GameState = GameState()
    /** Manual taps shown locally but not yet confirmed by `gameTap`. */
    private var unackedTaps = 0
    private var tapFlushJob: Job? = null
    private var tapFlushGeneration = 0
    /** True while tapFlushJob is sending gameTap calls (avoids refresh joining itself). */
    private var flushingTaps = false
    private var anchorMs: Long = System.currentTimeMillis()
    private var windowEndHandled = false
    private var foreground = false
    private var skipAnimating = false
    private var adsWatchedToday = 0
    /** True while a rewarded ad is on screen — skip lifecycle refresh so the watch is not dropped. */
    @Volatile private var watchingAd = false

    companion object {
        private const val SKIP_LERP_MS = 3_000L
    }

    private val _ui = MutableStateFlow(UiState())
    val ui: StateFlow<UiState> = _ui.asStateFlow()

    init {
        GameReminderScheduler.ensureChannel(appContext)
        _ui.update {
            it.copy(
                bypassAdsAvailable = DebugAdBypass.available,
                bypassAds = DebugAdBypass.isEnabled(appContext),
                hasCompletedOnboarding = settings.hasCompletedOnboarding,
                remindersEnabled = settings.remindersEnabled,
                hapticsEnabled = settings.hapticsEnabled,
                soundEnabled = settings.soundEnabled,
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
                _ui.update {
                    it.copy(
                        ready = true,
                        loading = false,
                        playerId = api.playerId.orEmpty(),
                    )
                }
                foreground = true
                AdMobRewarded.preload(appContext)
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
        if (watchingAd) return
        viewModelScope.launch { runCatching { refresh(force = true) } }
        ensureTicker()
    }

    /** App backgrounded: stop the local animation loop (no network was running anyway). */
    fun onBackground() {
        if (watchingAd) return
        foreground = false
        tickerJob?.cancel()
        // Keep Boost Ad refill / auto-end reminders aligned when leaving the app.
        GameReminderScheduler.sync(appContext, project(serverState, System.currentTimeMillis()))
    }

    fun clearError() {
        _ui.update { it.copy(error = null) }
    }

    /** Instant local feedback; Firebase catch-up is serialized in the background. */
    fun tap() {
        if (skipAnimating) return
        if (serverState.tapsRemaining <= 0) return

        unackedTaps += 1
        serverState = serverState.applyingManualTap(_ui.value.tunables)
        _ui.update { it.copy(state = project(serverState, System.currentTimeMillis())) }
        syncProgress()
        ensureTapFlush()
    }

    /** Recompute display from confirmed server state + unacked optimistic taps. */
    private fun publishOptimisticTaps() {
        var s = confirmedState
        repeat(unackedTaps) { s = s.applyingManualTap(_ui.value.tunables) }
        // Keep the auto-fill clock; only progress / taps change.
        serverState = s
        _ui.update { it.copy(state = project(s, System.currentTimeMillis())) }
    }

    /** Finish uploading optimistic taps so the next getState includes them. */
    private suspend fun drainPendingTaps() {
        if (flushingTaps) return
        tapFlushJob?.join()
    }

    private fun ensureTapFlush() {
        if (tapFlushJob?.isActive == true) return
        val generation = tapFlushGeneration
        tapFlushJob = viewModelScope.launch {
            flushingTaps = true
            try {
            while (unackedTaps > 0) {
                if (generation != tapFlushGeneration) return@launch
                try {
                    val credit = api.tap()
                    if (generation != tapFlushGeneration) return@launch
                    credit.state.updatedAt?.let { lastUpdatedAt = it }
                    val nowMs = System.currentTimeMillis()
                    // Combo ring + live-tap units (Stronger × combo) must survive gameTap
                    // ACKs. Deployed functions may still credit tapPower only; keep the
                    // optimistic tap math. Do not reset the auto-fill anchor — project()
                    // still owns auto catch-up (no combo) from the existing clock.
                    val afterTap = confirmedState.applyingManualTap(_ui.value.tunables, nowMs)
                    confirmedState = credit.state.takingLiveTapUnits(afterTap)
                    unackedTaps = (unackedTaps - 1).coerceAtLeast(0)
                    windowEndHandled = false
                    _ui.update { it.copy(state = project(serverState, nowMs)) }
                    applyProgress(credit.progress)
                    ensureTicker()
                } catch (_: Exception) {
                    if (generation != tapFlushGeneration) return@launch
                    unackedTaps = 0
                    runCatching { refresh(force = true) }
                    return@launch
                }
            }
            } finally {
                flushingTaps = false
            }
        }
    }

    fun watch(boost: BoostType) {
        if (watchingAd) return
        watchingAd = true
        viewModelScope.launch {
            _ui.update { it.copy(watchingAd = true, error = null) }
            try {
                val service = ads ?: throw IllegalStateException("Ad service not ready")
                val from = _ui.value.state
                val credit = service.showBoostAd(boost)
                val to = credit.state
                adsWatchedToday += 1
                if (boost == BoostType.SKIP_TIME) {
                    playSkipLerp(from, to)
                } else {
                    applyState(to, force = true)
                }
                applyProgress(credit.progress)
            } catch (e: Exception) {
                _ui.update { it.copy(loading = false, error = e.message) }
                runCatching { refresh(force = true) }
            } finally {
                watchingAd = false
                _ui.update { it.copy(watchingAd = false) }
            }
        }
    }

    /** Lerp progress / sats / auto timer / regen over a few seconds after Skip Time. */
    private suspend fun playSkipLerp(from: GameState, to: GameState) {
        skipAnimating = true
        tickerJob?.cancel()
        tickerJob = null

        val incoming = to.updatedAt
        if (incoming != null) lastUpdatedAt = incoming
        tapFlushGeneration += 1
        unackedTaps = 0
        confirmedState = to
        serverState = to
        GameReminderScheduler.sync(appContext, to)

        val durationMs = SKIP_LERP_MS
        val startMs = System.currentTimeMillis()
        val units = maxOf(1, to.unitsPerSat)
        val fromAbs = from.satsBalance.toDouble() * units + from.progress
        val toAbs = to.satsBalance.toDouble() * units + to.progress
        val fromAuto = remainingSecondsDouble(from.autoFillUntil)
        val toAuto = remainingSecondsDouble(to.autoFillUntil)
        val fromRegen = from.adRegenSecondsLeft.toDouble()
        val toRegen = to.adRegenSecondsLeft.toDouble()
        val fromAds = from.adsRemainingToday
        val toAds = to.adsRemainingToday
        val fromSkip = from.skipAdsRemaining
        val toSkip = to.skipAdsRemaining
        val fromSkipRegen = from.skipAdRegenSecondsLeft.toDouble()
        val toSkipRegen = to.skipAdRegenSecondsLeft.toDouble()

        while (true) {
            val elapsed = System.currentTimeMillis() - startMs
            val u = (elapsed.toDouble() / durationMs).coerceIn(0.0, 1.0)
            val e = 1.0 - (1.0 - u).let { it * it * it } // ease-out cubic

            val absProg = fromAbs + (toAbs - fromAbs) * e
            val sats = floor(absProg / units).toInt()
            var prog = absProg - sats.toDouble() * units
            if (prog < 0) prog = 0.0
            if (prog >= units) prog = units - 0.0001

            val autoLeft = (fromAuto + (toAuto - fromAuto) * e).coerceAtLeast(0.0)
            val regenLeft = (fromRegen + (toRegen - fromRegen) * e).coerceAtLeast(0.0)
            val skipRegenLeft = (fromSkipRegen + (toSkipRegen - fromSkipRegen) * e).coerceAtLeast(0.0)
            val now = System.currentTimeMillis()
            val autoUntil = if (autoLeft > 0.05) {
                Instant.ofEpochMilli(now + (autoLeft * 1000).toLong()).toString()
            } else {
                to.autoFillUntil
            }
            val nextCharge = if (regenLeft > 0.5) {
                Instant.ofEpochMilli(now + (regenLeft * 1000).toLong()).toString()
            } else {
                to.nextAdChargeAt
            }
            val nextSkipCharge = if (skipRegenLeft > 0.5) {
                Instant.ofEpochMilli(now + (skipRegenLeft * 1000).toLong()).toString()
            } else {
                to.nextSkipAdChargeAt
            }
            val skipLeft = if (fromSkip >= 0 && toSkip >= 0) {
                if (e < 0.85) fromSkip else toSkip
            } else {
                toSkip
            }

            val display = to.copy(
                fillRate = 0.0,
                satsBalance = sats,
                progress = prog,
                satsEarnedToday = from.satsEarnedToday + maxOf(0, sats - from.satsBalance),
                autoFillActive = autoLeft > 0.05 || (to.autoFillActive && toAuto > 0),
                autoFillUntil = autoUntil,
                adRegenSecondsLeft = regenLeft.roundToInt(),
                nextAdChargeAt = nextCharge,
                adsRemainingToday = if (e < 0.85) fromAds else toAds,
                skipAdsRemaining = skipLeft,
                skipAdRegenSecondsLeft = skipRegenLeft.roundToInt(),
                nextSkipAdChargeAt = nextSkipCharge,
            )
            _ui.update { it.copy(state = display) }
            if (u >= 1.0) break
            delay(16)
        }

        skipAnimating = false
        anchorMs = System.currentTimeMillis()
        windowEndHandled = false
        _ui.update { it.copy(state = project(to, System.currentTimeMillis())) }
        ensureTicker()
    }

    private fun remainingSecondsDouble(untilIso: String?): Double {
        val untilMs = parseMs(untilIso) ?: return 0.0
        return ((untilMs - System.currentTimeMillis()) / 1000.0).coerceAtLeast(0.0)
    }

    fun debugReset() {
        if (_ui.value.tunables?.debugReset != true) return
        viewModelScope.launch {
            _ui.update { it.copy(loading = true, error = null) }
            try {
                val credit = api.debugReset()
                adsWatchedToday = 0
                applyState(credit.state, force = true, keepCombo = false)
                applyProgress(credit.progress)
                _ui.update { it.copy(withdrawals = emptyList(), loading = false) }
            } catch (e: Exception) {
                _ui.update { it.copy(loading = false, error = e.message) }
            }
        }
    }

    fun deleteAccount(onDone: (Boolean) -> Unit) {
        viewModelScope.launch {
            _ui.update { it.copy(loading = true, error = null) }
            tapFlushGeneration += 1
            unackedTaps = 0
            tapFlushJob?.cancel()
            tapFlushJob = null
            flushingTaps = false
            try {
                api.deleteAccount()
                GameReminderScheduler.clearAll(appContext)
                serverState = GameState()
                confirmedState = GameState()
                lastUpdatedAt = null
                adsWatchedToday = 0
                api.ensureSignedIn()
                refresh(force = true)
                _ui.update {
                    it.copy(
                        loading = false,
                        playerId = api.playerId.orEmpty(),
                        withdrawals = emptyList(),
                        error = null,
                    )
                }
                onDone(true)
            } catch (e: Exception) {
                _ui.update { it.copy(loading = false, error = e.message) }
                onDone(false)
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
        // Daily Goals (and other getState pulls) must not race in-flight taps.
        drainPendingTaps()
        val (state, tunables, progress) = api.fetchState()
        ads = AdServiceFactory.make(api, tunables?.adProvider ?: "waterfall", appContext)
        applyState(state, force = force, discardOptimisticTaps = false)
        _ui.update {
            it.copy(
                tunables = tunables,
                playerId = api.playerId.orEmpty(),
                error = null,
            )
        }
        applyProgress(progress)
    }

    fun completeOnboarding() {
        settings.hasCompletedOnboarding = true
        _ui.update { it.copy(hasCompletedOnboarding = true) }
    }

    fun setRemindersEnabled(enabled: Boolean) {
        settings.remindersEnabled = enabled
        _ui.update { it.copy(remindersEnabled = enabled) }
        if (enabled) {
            GameReminderScheduler.sync(appContext, _ui.value.state)
        } else {
            GameReminderScheduler.clearAll(appContext)
        }
    }

    fun setHapticsEnabled(enabled: Boolean) {
        settings.hapticsEnabled = enabled
        _ui.update { it.copy(hapticsEnabled = enabled) }
    }

    fun setSoundEnabled(enabled: Boolean) {
        settings.soundEnabled = enabled
        _ui.update { it.copy(soundEnabled = enabled) }
    }

    fun refreshActivity() {
        viewModelScope.launch { runCatching { refresh(force = true) } }
    }

    /**
     * Apply an authoritative server snapshot: it always wins over any locally
     * projected values, so a tampered client can never keep fake progress/balance.
     *
     * `discardOptimisticTaps` is true for mutations that already include those taps
     * (boost, reset, redeem). getState refresh keeps taps that landed during the fetch.
     */
    private fun applyState(
        state: GameState,
        force: Boolean,
        discardOptimisticTaps: Boolean = true,
        keepCombo: Boolean = true,
    ) {
        val incoming = state.updatedAt
        val prev = lastUpdatedAt
        if (!force && incoming != null && prev != null && incoming < prev) {
            return // stale response lost a race with a newer tap/boost
        }
        if (incoming != null) lastUpdatedAt = incoming
        val preserveLiveTaps = keepCombo && comboRecentlyTapped(_ui.value.state)
        val adopted = if (preserveLiveTaps) {
            if (discardOptimisticTaps) {
                state.keepingComboFrom(_ui.value.state)
            } else {
                // getState: keep Stronger × combo tap units; auto stays on the local clock.
                state.takingLiveTapUnits(confirmedState)
            }
        } else {
            state
        }
        if (discardOptimisticTaps) {
            // Invalidate any in-flight optimistic tap flush; those responses are stale
            // relative to this authoritative snapshot (boost / reset / redeem).
            tapFlushGeneration += 1
            unackedTaps = 0
            confirmedState = adopted
            serverState = adopted
            anchorMs = System.currentTimeMillis()
            windowEndHandled = false
            val projected = project(adopted, anchorMs)
            _ui.update { it.copy(state = projected) }
            GameReminderScheduler.sync(appContext, projected)
        } else {
            confirmedState = adopted
            if (!preserveLiveTaps) {
                anchorMs = System.currentTimeMillis()
            }
            windowEndHandled = false
            publishOptimisticTaps()
            GameReminderScheduler.sync(appContext, _ui.value.state)
        }
        ensureTicker()
    }

    private fun GameState.keepingComboFrom(from: GameState): GameState = copy(
        comboTaps = from.comboTaps,
        comboMeter = from.comboMeter,
        comboLevel = from.comboLevel,
        comboContrib = from.comboContrib,
        comboMeter1 = from.comboMeter1,
        comboLevel1 = from.comboLevel1,
        comboContrib1 = from.comboContrib1,
        comboMeter2 = from.comboMeter2,
        comboLevel2 = from.comboLevel2,
        comboContrib2 = from.comboContrib2,
        lastManualTapAt = from.lastManualTapAt,
        comboMultiplier = from.comboMultiplier,
    )

    private fun comboRecentlyTapped(s: GameState): Boolean {
        val last = parseIso8601Millis(s.lastManualTapAt ?: return false) ?: return false
        return System.currentTimeMillis() - last < 15_000L
    }

    private fun syncProgress() {
        applyProgress(null)
    }

    private fun applyProgress(server: PlayerProgress?) {
        val adsFromServer = server?.dailyGoals?.firstOrNull { it.id == "ads" }?.current
        if (adsFromServer != null) adsWatchedToday = adsFromServer
        _ui.update { ui ->
            val incoming = ui.progress.takingServer(server)
            val next = incoming.syncedWith(
                state = ui.state,
                tunables = ui.tunables,
                adsWatched = adsWatchedToday,
            )
            // Server remaining already includes tokens for this hold. Only grant slots
            // that local goal completion added on top (optimistic taps / this session).
            // Resume getState with no in-flight taps must not grant.
            val grantAbove = when {
                server != null && unackedTaps == 0 -> next.adBank.max
                server != null -> incoming.adBank.max
                else -> ui.progress.adBank.max
            }
            val oldRemaining = ui.state.adsRemainingToday
            val gained = (next.adBank.max - grantAbove).coerceAtLeast(0)
            val state = if (gained > 0 && ui.state.adsRemainingToday <= oldRemaining) {
                grantCharges(ui.state, gained, next.adBank.max)
            } else {
                ui.state
            }
            if (gained > 0 && state !== ui.state) {
                serverState = grantCharges(serverState, gained, next.adBank.max)
                confirmedState = grantCharges(confirmedState, gained, next.adBank.max)
            }
            ui.copy(
                state = state,
                progress = next,
                unseenDailyGoalCount = settings.unseenCompletedGoalCount(next.displayedDailyGoals),
            )
        }
    }

    private fun grantCharges(s: GameState, gained: Int, cap: Int): GameState {
        val remaining = (s.adsRemainingToday + gained).coerceIn(0, cap)
        return s.copy(
            adsRemainingToday = remaining,
            adRegenSecondsLeft = if (remaining >= cap) 0 else s.adRegenSecondsLeft,
            nextAdChargeAt = if (remaining >= cap) null else s.nextAdChargeAt,
        )
    }

    fun acknowledgeDailyGoals() {
        settings.acknowledgeDailyGoals(_ui.value.progress.displayedDailyGoals)
        _ui.update { it.copy(unseenDailyGoalCount = 0) }
    }

    /**
     * Local, network-free animation loop. While an auto window is running everything
     * is deterministic (progress = fillRate x elapsed, cooldown counts down), so we
     * project from the last server snapshot instead of polling. When the window ends
     * we hit the server exactly once to pull the authoritative reset (ads refilled).
     */
    private fun ensureTicker() {
        if (!foreground || skipAnimating) return
        if (tickerJob?.isActive == true) return
        tickerJob = viewModelScope.launch {
            while (isActive && foreground && !skipAnimating) {
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
                val adsMax = adsHoldMax(shown)
                val waitingRegen = shown.adRegenSecondsLeft > 0 && shown.adsRemainingToday < adsMax
                if (!shown.autoFillActive && shown.adCooldownSecondsLeft <= 0 && !waitingRegen) break
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
        // When the shared auto window just ended, show a full ad bank until refresh lands.
        val windowExpired = s.autoFillActive && !autoActive
        val maxCharges = adsHoldMax(s)
        val (adsLeft, regenLeft) = if (windowExpired) {
            maxCharges to 0
        } else {
            projectChargeBank(
                initialCharges = s.adsRemainingToday,
                initialRegen = s.adRegenSecondsLeft,
                nextAt = s.nextAdChargeAt,
                maxCharges = maxCharges.coerceAtLeast(1),
                nowMs = nowMs,
            )
        }
        val skipMax = _ui.value.tunables?.skipAdsPerCycle
        val (skipLeft, skipRegenLeft) = when {
            skipMax != null && skipMax < 0 -> 0 to 0 // disabled
            windowExpired -> when {
                skipMax == null -> s.skipAdsRemaining to 0
                skipMax == 0 -> -1 to 0
                else -> skipMax to 0
            }
            skipMax == 0 -> -1 to 0
            else -> {
                val maxSkip = skipMax ?: maxOf(s.skipAdsRemaining, 0)
                if (maxSkip <= 0) {
                    s.skipAdsRemaining to 0
                } else {
                    projectChargeBank(
                        initialCharges = s.skipAdsRemaining.coerceAtLeast(0),
                        initialRegen = s.skipAdRegenSecondsLeft,
                        nextAt = s.nextSkipAdChargeAt,
                        maxCharges = maxSkip,
                        nowMs = nowMs,
                    )
                }
            }
        }

        if (!s.autoFillActive || s.fillRate <= 0.0 || s.unitsPerSat <= 0 || untilMs == null) {
            return s.copy(
                adCooldownSecondsLeft = cooldown,
                autoFillActive = autoActive,
                adsRemainingToday = adsLeft,
                adRegenSecondsLeft = regenLeft,
                nextAdChargeAt = if (windowExpired) null else s.nextAdChargeAt,
                skipAdsRemaining = skipLeft,
                skipAdRegenSecondsLeft = skipRegenLeft,
                nextSkipAdChargeAt = if (windowExpired || skipLeft < 0) null else s.nextSkipAdChargeAt,
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
        // dailySatsEarnCap <= 0 means unlimited
        if (s.dailySatsEarnCap > 0) {
            val maxBars = (s.dailySatsEarnCap - s.satsEarnedToday).coerceAtLeast(0)
            if (bars > maxBars) bars = maxBars
        }
        val newProgress = (total - bars.toDouble() * s.unitsPerSat)
            .coerceIn(0.0, s.unitsPerSat.toDouble())

        return s.copy(
            progress = newProgress,
            satsBalance = s.satsBalance + bars,
            satsEarnedToday = s.satsEarnedToday + bars,
            adCooldownSecondsLeft = cooldown,
            autoFillActive = autoActive,
            adsRemainingToday = adsLeft,
            adRegenSecondsLeft = regenLeft,
            nextAdChargeAt = if (windowExpired) null else s.nextAdChargeAt,
            skipAdsRemaining = skipLeft,
            skipAdRegenSecondsLeft = skipRegenLeft,
            nextSkipAdChargeAt = if (windowExpired || skipLeft < 0) null else s.nextSkipAdChargeAt,
            durationBoostActive = if (autoActive) s.durationBoostActive else false,
            speedBoostActive = if (autoActive) s.speedBoostActive else false,
            tapStrengthActive = if (autoActive) s.tapStrengthActive else false,
            durationBoostCount = if (autoActive) s.durationBoostCount else 0,
            speedBoostCount = if (autoActive) s.speedBoostCount else 0,
            tapStrengthBoostCount = if (autoActive) s.tapStrengthBoostCount else 0,
        )
    }

    /**
     * Hold size for regen / display. Never below the server remaining we just loaded,
     * so a stale default bank of 5 cannot recap a full 13-token hold.
     */
    private fun adsHoldMax(s: GameState): Int {
        val bank = _ui.value.progress.adBank.max
        val cycle = _ui.value.tunables?.adsPerCycle ?: 0
        return maxOf(bank, cycle, s.adsRemainingToday, 1)
    }

    private fun projectChargeBank(
        initialCharges: Int,
        initialRegen: Int,
        nextAt: String?,
        maxCharges: Int,
        nowMs: Long,
    ): Pair<Int, Int> {
        val regenSec = _ui.value.tunables?.adRegenSeconds ?: 0
        var charges = initialCharges
        var regenLeft = initialRegen

        if (regenSec <= 0 || charges >= maxCharges) {
            return minOf(charges, maxCharges) to 0
        }

        val nextMs = parseMs(nextAt)
        if (nextMs != null) {
            if (nowMs >= nextMs) {
                val gained = 1 + ((nowMs - nextMs) / 1000L / regenSec).toInt()
                charges = minOf(maxCharges, initialCharges + gained)
                regenLeft = if (charges >= maxCharges) {
                    0
                } else {
                    val into = ((nowMs - nextMs) / 1000L % regenSec).toInt()
                    (regenSec - into).coerceAtLeast(0)
                }
            } else {
                regenLeft = ceil((nextMs - nowMs) / 1000.0).toInt().coerceAtLeast(0)
            }
        } else if (regenLeft > 0) {
            val elapsed = ((nowMs - anchorMs).coerceAtLeast(0L) / 1000.0)
            val left = ceil(regenLeft - elapsed).toInt()
            if (left <= 0) {
                val overdue = -left
                val gained = 1 + overdue / regenSec
                charges = minOf(maxCharges, initialCharges + gained)
                regenLeft = if (charges >= maxCharges) 0 else regenSec - (overdue % regenSec)
            } else {
                regenLeft = left
            }
        }
        return charges to regenLeft
    }

    private fun parseMs(iso: String?): Long? =
        iso?.let { runCatching { Instant.parse(it).toEpochMilli() }.getOrNull() }
}
