package com.adplay.app.ui

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.adplay.app.UiState

@Composable
fun MainShell(
    ui: UiState,
    onTap: () -> Unit,
    onActivate: () -> Unit,
    onLonger: () -> Unit,
    onFaster: () -> Unit,
    onStronger: () -> Unit,
    onSkipTime: () -> Unit,
    onDebugReset: () -> Unit,
    onToggleBypassAds: () -> Unit,
    onRetry: () -> Unit,
    onRefreshActivity: () -> Unit,
    onReminders: (Boolean) -> Unit,
    onHaptics: (Boolean) -> Unit,
    onSound: (Boolean) -> Unit,
    onLoadHistory: () -> Unit,
    onSubmit: (amount: Int, bolt11: String, done: (Boolean) -> Unit) -> Unit,
    onAcknowledgeDailyGoals: () -> Unit,
) {
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var showSettings by remember { mutableStateOf(false) }
    var showAchievements by remember { mutableStateOf(false) }
    val labels = listOf("Play", "Daily Goals", "Store", "Redeem")

    Scaffold(
        containerColor = BrandBgMid,
        bottomBar = {
            NavigationBar(containerColor = BrandCard) {
                labels.forEachIndexed { i, label ->
                    NavigationBarItem(
                        selected = tab == i,
                        onClick = {
                            tab = i
                            if (i == 1) onAcknowledgeDailyGoals()
                        },
                        icon = {
                            BadgedBox(
                                badge = {
                                    if (i == 1 && ui.unseenDailyGoalCount > 0) {
                                        Badge { Text("${ui.unseenDailyGoalCount}") }
                                    }
                                },
                            ) {
                                Text(if (tab == i) "●" else "○", color = if (tab == i) BrandAccent else BrandMuted)
                            }
                        },
                        label = { Text(label) },
                        colors = NavigationBarItemDefaults.colors(
                            selectedTextColor = BrandAccent,
                            unselectedTextColor = BrandMuted,
                            indicatorColor = BrandAccent.copy(alpha = 0.18f),
                        ),
                    )
                }
            }
        },
    ) { padding ->
        androidx.compose.foundation.layout.Box(Modifier.padding(padding)) {
            when (tab) {
                0 -> HomeScreen(
                    ui = ui,
                    onTap = onTap,
                    onActivate = onActivate,
                    onLonger = onLonger,
                    onFaster = onFaster,
                    onStronger = onStronger,
                    onSkipTime = onSkipTime,
                    onAchievements = { showAchievements = true },
                    onSettings = { showSettings = true },
                    onDebugReset = onDebugReset,
                    onToggleBypassAds = onToggleBypassAds,
                    onRetry = onRetry,
                )
                1 -> ActivityScreen(ui = ui, onRefresh = onRefreshActivity)
                2 -> StoreScreen(ui = ui)
                else -> RedeemScreen(
                    ui = ui,
                    onLoadHistory = onLoadHistory,
                    onSubmit = onSubmit,
                    showClose = false,
                )
            }
        }
    }

    if (showSettings) {
        Dialog(
            onDismissRequest = { showSettings = false },
            properties = DialogProperties(
                usePlatformDefaultWidth = false,
                decorFitsSystemWindows = false,
            ),
        ) {
            Surface(Modifier.fillMaxSize(), color = BrandBgTop) {
                SettingsScreen(
                    ui = ui,
                    onReminders = onReminders,
                    onHaptics = onHaptics,
                    onSound = onSound,
                    onClose = { showSettings = false },
                )
            }
        }
    }

    if (showAchievements) {
        Dialog(
            onDismissRequest = { showAchievements = false },
            properties = DialogProperties(
                usePlatformDefaultWidth = false,
                decorFitsSystemWindows = false,
            ),
        ) {
            Surface(Modifier.fillMaxSize(), color = BrandBgTop) {
                AchievementsScreen(ui = ui, onClose = { showAchievements = false })
            }
        }
    }
}
