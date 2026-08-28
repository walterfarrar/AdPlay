package com.adplay.app.ui

import android.os.Handler
import android.os.Looper
import android.view.HapticFeedbackConstants
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Box
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.adplay.app.UiState
import kotlinx.coroutines.delay

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
    onDeleteAccount: (done: (Boolean) -> Unit) -> Unit,
    onLoadHistory: () -> Unit,
    onSubmit: (amount: Int, bolt11: String, done: (Boolean) -> Unit) -> Unit,
    onAcknowledgeDailyGoals: () -> Unit,
) {
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var showSettings by remember { mutableStateOf(false) }
    var showAchievements by remember { mutableStateOf(false) }
    val labels = listOf("Play", "Daily Goals", "Store", "Redeem")
    val density = LocalDensity.current
    val view = LocalView.current

    var shellCoords by remember { mutableStateOf<LayoutCoordinates?>(null) }
    var wheelTipCoords by remember { mutableStateOf<LayoutCoordinates?>(null) }
    var redeemCoords by remember { mutableStateOf<LayoutCoordinates?>(null) }
    var shellWidthPx by remember { mutableStateOf(0f) }
    var shellHeightPx by remember { mutableStateOf(0f) }
    val satParticles = remember { mutableStateListOf<SatParticle>() }
    var redeemGlow by remember { mutableStateOf(false) }
    var lastCelebrateAtMs by remember { mutableLongStateOf(0L) }
    var previousSats by remember { mutableStateOf<Int?>(null) }
    var nextParticleId by remember { mutableLongStateOf(1L) }

    val redeemGlowScale by animateFloatAsState(
        targetValue = if (redeemGlow) 1.08f else 1f,
        animationSpec = spring(dampingRatio = 0.55f, stiffness = Spring.StiffnessMedium),
        label = "redeemGlowScale",
    )
    val redeemGlowStrength by animateFloatAsState(
        targetValue = if (redeemGlow) 1f else 0f,
        animationSpec = tween(if (redeemGlow) 180 else 500),
        label = "redeemGlowStrength",
    )

    fun localInShell(child: LayoutCoordinates?, pointInChild: Offset): Offset {
        val shell = shellCoords ?: return Offset.Zero
        val target = child ?: return Offset.Zero
        return if (target.isAttached && shell.isAttached) {
            shell.localPositionOf(target, pointInChild)
        } else {
            Offset.Zero
        }
    }

    fun fireSatCelebrationBeat() {
        val now = System.currentTimeMillis()
        if (now - lastCelebrateAtMs < 120L && satParticles.isNotEmpty()) return
        lastCelebrateAtMs = now

        val fallbackFrom = Offset(
            x = shellWidthPx * 0.38f,
            y = shellHeightPx * 0.38f,
        )
        val fallbackTo = Offset(
            x = shellWidthPx * 7f / 8f,
            y = (shellHeightPx - with(density) { 24.dp.toPx() }).coerceAtLeast(0f),
        )
        val wheelTip = wheelTipCoords?.let { coords ->
            localInShell(
                coords,
                Offset(coords.size.width / 2f, with(density) { 8.dp.toPx() }),
            )
        } ?: Offset.Zero
        val redeemCenter = redeemCoords?.let { coords ->
            localInShell(
                coords,
                Offset(coords.size.width / 2f, coords.size.height / 2f),
            )
        } ?: Offset.Zero
        val from = if (wheelTip != Offset.Zero) wheelTip else fallbackFrom
        val to = if (redeemCenter != Offset.Zero) redeemCenter else fallbackTo
        if (satParticles.size < 4 && shellWidthPx > 0f) {
            satParticles.add(
                SatParticle(id = nextParticleId++, from = from, to = to),
            )
        }

        if (ui.hapticsEnabled) {
            @Suppress("DEPRECATION")
            view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
        }
        if (ui.soundEnabled) {
            playSatTick()
        }

        Handler(Looper.getMainLooper()).postDelayed({
            redeemGlow = true
            Handler(Looper.getMainLooper()).postDelayed({
                redeemGlow = false
            }, 550)
        }, SatParticleMotion.LAND_AT_MS)
    }

    LaunchedEffect(ui.state.satsBalance) {
        val prev = previousSats
        previousSats = ui.state.satsBalance
        if (prev == null) return@LaunchedEffect
        val gained = ui.state.satsBalance - prev
        if (gained <= 0) return@LaunchedEffect
        val bursts = gained.coerceIn(1, 4)
        for (i in 0 until bursts) {
            if (i > 0) delay(120)
            fireSatCelebrationBeat()
        }
    }

    Box(
        Modifier
            .fillMaxSize()
            .onGloballyPositioned { coords ->
                shellCoords = coords
                shellWidthPx = coords.size.width.toFloat()
                shellHeightPx = coords.size.height.toFloat()
            },
    ) {
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
                            modifier = Modifier
                                .then(
                                    if (i == 3) {
                                        Modifier
                                            .onGloballyPositioned { redeemCoords = it }
                                            .graphicsLayer {
                                                scaleX = redeemGlowScale
                                                scaleY = redeemGlowScale
                                                shadowElevation = 14.dp.toPx() * redeemGlowStrength
                                                ambientShadowColor = BrandAccent
                                                spotShadowColor = BrandAccent
                                            }
                                    } else {
                                        Modifier
                                    },
                                ),
                            icon = {
                                TabGlyph(
                                    selected = tab == i || (i == 3 && redeemGlowStrength > 0.01f),
                                    showGoalBadge = i == 1 && ui.unseenDailyGoalCount > 0,
                                    goalBadgeCount = ui.unseenDailyGoalCount,
                                )
                            },
                            label = {
                                Text(
                                    label,
                                    color = if (tab == i || (i == 3 && redeemGlowStrength > 0.01f)) {
                                        BrandAccent
                                    } else {
                                        BrandMuted
                                    },
                                )
                            },
                            colors = NavigationBarItemDefaults.colors(
                                selectedTextColor = BrandAccent,
                                unselectedTextColor = BrandMuted,
                                indicatorColor = BrandAccent.copy(
                                    alpha = if (i == 3) 0.18f + 0.32f * redeemGlowStrength else 0.18f,
                                ),
                            ),
                        )
                    }
                }
            },
        ) { padding ->
            Box(Modifier.padding(padding)) {
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
                        onWheelTipPositioned = { wheelTipCoords = it },
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

        satParticles.forEach { particle ->
            key(particle.id) {
                FlyingSatParticle(
                    particle = particle,
                    onFinished = { satParticles.removeAll { it.id == particle.id } },
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
                    onDeleteAccount = onDeleteAccount,
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

@Composable
private fun TabGlyph(
    selected: Boolean,
    showGoalBadge: Boolean,
    goalBadgeCount: Int,
) {
    BadgedBox(
        badge = {
            if (showGoalBadge) {
                Badge { Text("$goalBadgeCount") }
            }
        },
    ) {
        Text(
            if (selected) "●" else "○",
            color = if (selected) BrandAccent else BrandMuted,
        )
    }
}
