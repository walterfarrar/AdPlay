package com.adplay.app

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.adplay.app.data.AdServiceFactory
import com.adplay.app.data.AdServing
import com.adplay.app.data.ApiClient
import com.adplay.app.data.BoostType
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

data class UiState(
    val ready: Boolean = false,
    val loading: Boolean = false,
    val state: GameState = GameState(),
    val tunables: Tunables? = null,
    val error: String? = null,
    val withdrawals: List<Withdrawal> = emptyList(),
    val apiBaseUrl: String = "Firebase (adplay-sats)",
)

class GameViewModel(app: Application) : AndroidViewModel(app) {
    private val api = ApiClient()
    private var ads: AdServing? = null
    private var pollJob: Job? = null
    /** Drop poll results older than the last applied mutation/poll. */
    private var lastUpdatedAt: String? = null
    private val appContext = app.applicationContext

    private val _ui = MutableStateFlow(UiState())
    val ui: StateFlow<UiState> = _ui.asStateFlow()

    init {
        GameReminderScheduler.ensureChannel(appContext)
        start()
    }

    fun start() {
        viewModelScope.launch {
            _ui.update { it.copy(loading = true, error = null) }
            try {
                api.ensureSignedIn()
                refresh(force = true)
                _ui.update { it.copy(ready = true, loading = false) }
                startPolling()
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

    private fun applyState(state: GameState, force: Boolean) {
        val incoming = state.updatedAt
        val prev = lastUpdatedAt
        if (!force && incoming != null && prev != null && incoming < prev) {
            return // stale poll lost a race with a newer tap/boost
        }
        if (incoming != null) lastUpdatedAt = incoming
        _ui.update { it.copy(state = state) }
        GameReminderScheduler.sync(appContext, state)
    }

    private fun startPolling() {
        pollJob?.cancel()
        pollJob = viewModelScope.launch {
            while (isActive) {
                val s = _ui.value.state
                val busy = s.autoFillActive || s.adCooldownSecondsLeft > 0 || s.tapStrengthActive
                delay(if (busy) 400 else 2_000)
                runCatching { refresh(force = false) }
            }
        }
    }
}
