package com.adplay.app.ui

import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import kotlinx.coroutines.launch
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.adplay.app.UiState
import com.adplay.app.data.ComboEngine
import com.adplay.app.data.ComboState
import com.adplay.app.data.ComboTunables
import com.adplay.app.data.MinerStage
import com.adplay.app.data.Tunables
import java.time.Instant
import java.time.format.DateTimeParseException
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlinx.coroutines.delay

private enum class BoostVisual {
    /** Can watch an ad now (no boost timer) */
    Ready,
    /** Boost running and another ad can be watched */
    RunningReady,
    /** Boost running but ad cooldown / no ads — not pressable */
    RunningLocked,
    /** No boost; cooldown / out of ads */
    Locked,
}

@Composable
fun HomeScreen(
    ui: UiState,
    onTap: () -> Unit,
    onActivate: () -> Unit,
    onLonger: () -> Unit,
    onFaster: () -> Unit,
    onStronger: () -> Unit,
    onSkipTime: () -> Unit,
    onAchievements: () -> Unit,
    onSettings: () -> Unit,
    onDebugReset: () -> Unit,
    onToggleBypassAds: () -> Unit,
    onRetry: () -> Unit,
    onWheelTipPositioned: (LayoutCoordinates) -> Unit = {},
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.linearGradient(listOf(BrandBgTop, BrandBgMid, BrandBgBottom)),
            ),
    ) {
        Box(
            Modifier
                .size(360.dp)
                .align(Alignment.TopStart)
                .offset(x = (-120).dp, y = (-150).dp)
                .background(
                    Brush.radialGradient(listOf(BrandAccent.copy(alpha = 0.22f), Color.Transparent)),
                    CircleShape,
                ),
        )
        Box(
            Modifier
                .size(400.dp)
                .align(Alignment.BottomEnd)
                .offset(x = 130.dp, y = 160.dp)
                .background(
                    Brush.radialGradient(listOf(Color(0xFF6B5CF5).copy(alpha = 0.18f), Color.Transparent)),
                    CircleShape,
                ),
        )

        when {
            !ui.ready && ui.loading -> {
                Column(
                    Modifier.fillMaxSize(),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text("AdPlay", fontSize = 40.sp, fontWeight = FontWeight.Bold, color = BrandInk)
                    Spacer(Modifier.height(16.dp))
                    CircularProgressIndicator(color = BrandAccent)
                    Spacer(Modifier.height(12.dp))
                    Text(ui.apiBaseUrl, color = BrandMuted, fontSize = 12.sp, textAlign = TextAlign.Center)
                }
            }

            !ui.ready -> {
                Column(
                    Modifier
                        .fillMaxSize()
                        .padding(24.dp),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text("AdPlay", fontSize = 40.sp, fontWeight = FontWeight.Bold, color = BrandInk)
                    Spacer(Modifier.height(12.dp))
                    Text(ui.error ?: "Not connected", color = Color(0xFFFF6B6B), textAlign = TextAlign.Center)
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "${ui.apiBaseUrl}\nEnable Blaze + deploy functions (docs/LDPLAYER.md).",
                        color = BrandMuted,
                        fontSize = 13.sp,
                        textAlign = TextAlign.Center,
                    )
                    Spacer(Modifier.height(16.dp))
                    Button(onClick = onRetry) { Text("Retry") }
                }
            }

            else -> {
                val state = ui.state
                val canWatch = !ui.loading &&
                    !ui.watchingAd &&
                    state.adsRemainingToday > 0 &&
                    state.adCooldownSecondsLeft == 0
                // Free starter ad while idle — does not spend from the boost bank.
                val canActivate = !ui.loading &&
                    !ui.watchingAd &&
                    !state.autoFillActive &&
                    state.adCooldownSecondsLeft == 0
                // Faster / Stronger unlock once Auto Tapper is running.
                val canWatchSecondary = canWatch && state.autoFillActive
                var barFlash by remember { mutableFloatStateOf(0f) }
                var previousSats by remember { mutableStateOf<Int?>(null) }
                val barFlashAnimated by animateFloatAsState(
                    targetValue = barFlash,
                    animationSpec = tween(if (barFlash > 0f) 80 else 450),
                    label = "barFlash",
                )

                fun fireSatCelebrationBeat() {
                    barFlash = 1f
                }

                LaunchedEffect(barFlash) {
                    if (barFlash > 0f) {
                        delay(90)
                        barFlash = 0f
                    }
                }

                LaunchedEffect(state.satsBalance) {
                    val prev = previousSats
                    previousSats = state.satsBalance
                    if (prev == null) return@LaunchedEffect
                    val gained = state.satsBalance - prev
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
                        .graphicsLayer { clip = false },
                ) {
                Column(
                    Modifier
                        .align(Alignment.TopCenter)
                        .fillMaxWidth()
                        .fillMaxSize()
                        .padding(horizontal = 24.dp, vertical = 16.dp),
                ) {
                    Row(
                        Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column {
                            Text("AdPlay", fontSize = 28.sp, fontWeight = FontWeight.Bold, color = BrandInk)
                            Text(
                                MinerStage.from(ui.progress.lifetimeSatsEarned).title,
                                fontSize = 12.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = BrandAccent,
                            )
                        }
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            if (ui.bypassAdsAvailable) {
                                TextButton(onClick = onToggleBypassAds) {
                                    Text(
                                        if (ui.bypassAds) "Skip ads" else "Real ads",
                                        color = if (ui.bypassAds) BrandAccent else BrandMuted,
                                        fontWeight = FontWeight.SemiBold,
                                    )
                                }
                            }
                            // Fail-closed: only when server explicitly enables debug reset.
                            if (ui.tunables?.debugReset == true) {
                                TextButton(onClick = onDebugReset) {
                                    Text("Reset", color = BrandMuted, fontWeight = FontWeight.SemiBold)
                                }
                            }
                            Box(
                                Modifier
                                    .size(36.dp)
                                    .clip(CircleShape)
                                    .background(BrandAccent.copy(alpha = 0.14f))
                                    .border(1.dp, BrandAccent.copy(alpha = 0.55f), CircleShape)
                                    .clickable(onClick = onAchievements)
                                    .semantics { contentDescription = "Achievements" },
                                contentAlignment = Alignment.Center,
                            ) {
                                Text("🏆", fontSize = 16.sp)
                            }
                            Box(
                                Modifier
                                    .padding(start = 8.dp)
                                    .size(36.dp)
                                    .clip(CircleShape)
                                    .background(BrandInk.copy(alpha = 0.08f))
                                    .border(1.dp, BrandInk.copy(alpha = 0.25f), CircleShape)
                                    .clickable(onClick = onSettings)
                                    .semantics { contentDescription = "Settings" },
                                contentAlignment = Alignment.Center,
                            ) {
                                Text("⚙", color = BrandInk, fontSize = 18.sp)
                            }
                        }
                    }

                    Spacer(Modifier.height(10.dp))
                    Text(
                        "Early access — Lightning payouts are real. Earn rates stay modest while we roll out; " +
                            "they can improve as more players join and ad revenue grows.",
                        color = BrandMuted,
                        fontSize = 12.sp,
                        lineHeight = 16.sp,
                        modifier = Modifier.fillMaxWidth(),
                    )

                    Spacer(Modifier.weight(1f))

                    SatEarnStage(
                        satsBalance = state.satsBalance,
                        displayProgress = state.progress,
                        unitsPerSat = state.unitsPerSat,
                        autoActive = state.autoFillActive,
                        autoFillUntil = state.autoFillUntil,
                        fillRate = state.fillRate,
                        tapPower = state.tapPower,
                        combo = state.combo,
                        tunables = ui.tunables,
                        onTap = onTap,
                        wheelFlash = barFlashAnimated,
                        onWheelTipPositioned = onWheelTipPositioned,
                        modifier = Modifier.fillMaxWidth(),
                    )

                    Spacer(Modifier.height(14.dp))
                    Text(
                        if (state.tapsRemaining > 0) {
                            "Tap the wheel · ${state.tapsRemaining} taps left today"
                        } else {
                            "0 taps left today"
                        },
                        color = BrandMuted,
                        fontSize = 14.sp,
                        modifier = Modifier.fillMaxWidth(),
                        textAlign = TextAlign.Center,
                    )

                    Spacer(Modifier.weight(0.8f))

                    val t = ui.tunables
                    Text(
                        if (state.autoFillActive) {
                            "Watch an Ad for a Boost"
                        } else {
                            "Watch an Ad to activate Auto Tapper"
                        },
                        color = BrandMuted,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.SemiBold,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Spacer(Modifier.height(8.dp))
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(88.dp),
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        if (state.autoFillActive) {
                            BoostButton(
                                title = "Longer",
                                actionLabel = formatLongerAction(t),
                                theme = BrandTime,
                                running = state.durationBoostActive,
                                applyCount = state.durationBoostCount,
                                enabled = canWatch,
                                onClick = onLonger,
                                modifier = Modifier.weight(1f).fillMaxHeight(),
                            )
                            BoostButton(
                                title = "Faster",
                                actionLabel = formatFasterAction(t),
                                theme = BrandSpeed,
                                running = state.speedBoostActive,
                                applyCount = state.speedBoostCount,
                                enabled = canWatchSecondary,
                                onClick = onFaster,
                                modifier = Modifier.weight(1f).fillMaxHeight(),
                            )
                            BoostButton(
                                title = "Stronger",
                                actionLabel = formatStrongerAction(t),
                                theme = BrandPower,
                                running = state.tapStrengthActive,
                                applyCount = state.tapStrengthBoostCount,
                                enabled = canWatchSecondary,
                                onClick = onStronger,
                                modifier = Modifier.weight(1f).fillMaxHeight(),
                            )
                        } else {
                            BoostButton(
                                title = "Activate Auto Tapper",
                                actionLabel = formatLongerAction(t),
                                theme = BrandTime,
                                showCount = false,
                                enabled = canActivate,
                                onClick = onActivate,
                                modifier = Modifier.weight(1f).fillMaxHeight(),
                            )
                        }
                    }

                    Spacer(Modifier.height(10.dp))

                    ui.error?.let {
                        Text(it, color = Color(0xFFFF6B6B), fontSize = 13.sp, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
                        Spacer(Modifier.height(8.dp))
                    }

                    AdsFooter(
                        adsRemaining = state.adsRemainingToday,
                        cooldownLeft = state.adCooldownSecondsLeft,
                        regenLeft = state.adRegenSecondsLeft,
                        adsMax = ui.progress.adBank.max.takeIf { it > 0 } ?: (t?.adsPerCycle ?: 5),
                        adRegenSeconds = t?.adRegenSeconds ?: 0,
                    )

                    // Reserved height so layout never jumps when Skip appears.
                    Spacer(Modifier.height(8.dp))
                    // skipAdsPerCycle < 0 disables Skip Time entirely.
                    val skipEnabled = (t?.skipAdsPerCycle ?: 10) >= 0
                    val skipVisible = skipEnabled &&
                        state.adsRemainingToday <= 0 &&
                        state.autoFillActive &&
                        (state.skipAdsRemaining < 0 ||
                            state.skipAdsRemaining > 0 ||
                            state.skipAdRegenSecondsLeft > 0)
                    val canSkip = !ui.loading &&
                        !ui.watchingAd &&
                        skipVisible &&
                        state.adCooldownSecondsLeft == 0 &&
                        (state.skipAdsRemaining < 0 || state.skipAdsRemaining > 0)
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(52.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        if (skipVisible) {
                            SkipTimeButton(
                                actionLabel = formatSkipTimeAction(t),
                                remainingLabel = formatSkipButtonStatus(
                                    skipAdsRemaining = state.skipAdsRemaining,
                                    cooldownLeft = state.adCooldownSecondsLeft,
                                    regenLeft = state.skipAdRegenSecondsLeft,
                                ),
                                enabled = canSkip,
                                onClick = onSkipTime,
                            )
                        }
                    }
                }

                if (ui.loading) {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = BrandAccent)
                    }
                }

                } // home Box
            }
        }
    }
}

@Composable
private fun SharedAutoTimer(
    autoFillUntil: String?,
    autoActive: Boolean,
) {
    var nowMs by remember { mutableLongStateOf(System.currentTimeMillis()) }
    val left = remainingSeconds(autoFillUntil.takeIf { autoActive }, nowMs)
    LaunchedEffect(autoFillUntil, autoActive) {
        if (!autoActive || autoFillUntil.isNullOrBlank()) return@LaunchedEffect
        while (true) {
            nowMs = System.currentTimeMillis()
            if (remainingSeconds(autoFillUntil, nowMs) <= 0L) break
            delay(250)
        }
    }
    Text(
        if (left > 0L) "Auto ${formatCountdown(left)}" else " ",
        color = if (left > 0L) BrandTime else Color.Transparent,
        fontSize = 13.sp,
        fontWeight = FontWeight.SemiBold,
        textAlign = TextAlign.Center,
        maxLines = 1,
        modifier = Modifier.fillMaxWidth(),
    )
}

@Composable
private fun AdsFooter(
    adsRemaining: Int,
    cooldownLeft: Int,
    regenLeft: Int,
    adsMax: Int,
    adRegenSeconds: Int,
) {
    val footer = when {
        adsRemaining <= 0 -> {
            when {
                regenLeft > 0 -> "Next Boost Ad in ${formatCountdown(regenLeft.toLong())}"
                adRegenSeconds <= 0 -> "Tokens refill when Auto ends"
                else -> "No Ad Tokens"
            }
        }
        cooldownLeft > 0 -> "Next Boost Ad in ${cooldownLeft}s · $adsRemaining/$adsMax tokens"
        adsRemaining < adsMax && regenLeft > 0 ->
            "$adsRemaining/$adsMax tokens · +1 in ${formatCountdown(regenLeft.toLong())}"
        else -> "$adsRemaining/$adsMax tokens"
    }

    Row(
        Modifier
            .fillMaxWidth()
            .padding(bottom = 8.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        AdSlotIcon(size = 16.dp)
        Text(
            footer,
            color = BrandMuted,
            fontSize = 12.sp,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(start = 6.dp),
        )
    }
}

/**
 * Fixed-point 1e-13 BTC quanta. 1 sat = 1e-8 BTC = 100_000 quanta.
 * Uses fractional bar progress (not floor) so 1.5-power hits advance evenly.
 */
internal fun btcQuanta(satsBalance: Int, barProgress: Double, unitsPerSat: Int): Long {
    val units = unitsPerSat.coerceAtLeast(1)
    // Milli-units keep tapPower like 1.5 exact; avoid floor() which alternates +1/+2.
    val progressMilli = kotlin.math.round(barProgress.coerceIn(0.0, units.toDouble()) * 1000.0).toLong()
        .coerceIn(0L, units.toLong() * 1000L)
    val denom = units.toLong() * 1000L
    // Round-to-nearest quanta — truncating division fluttered the last digit.
    val fracQuanta = (progressMilli * 100_000L + denom / 2) / denom
    return satsBalance.toLong() * 100_000L + fracQuanta
}

/** BTC for completed sats plus the in-progress fraction of the current bar (1 full bar = 1 sat). */
internal fun formatBtcAmount(satsBalance: Int, barProgress: Double, unitsPerSat: Int): String =
    formatBtcQuanta(btcQuanta(satsBalance, barProgress, unitsPerSat))

internal fun formatBtcQuanta(quanta: Long): String {
    val whole = quanta / 10_000_000_000_000L
    val frac = quanta % 10_000_000_000_000L
    return String.format("%d.%013d", whole, frac)
}

/**
 * Upward odometer ticks for place 10^power.
 * Carries count: +10 on the value → ones place ticks 10 (full turn) even if the glyph ends the same.
 */
private fun odometerSteps(fromQuanta: Long, toQuanta: Long, power: Int, toDigit: Int): Int {
    var place = 1L
    repeat(power.coerceAtLeast(0)) { place *= 10L }
    return if (toQuanta >= fromQuanta) {
        val raw = toQuanta / place - fromQuanta / place
        raw.coerceIn(0L, 40L).toInt()
    } else {
        val fromDigit = ((fromQuanta / place) % 10L).toInt()
        (toDigit - fromDigit + 10) % 10
    }
}

private data class BtcGlyph(
    val key: String,
    val digit: Int?,
    val steps: Int,
    val literal: String?,
)

private fun btcGlyphs(fromQuanta: Long, toQuanta: Long): List<BtcGlyph> {
    val text = formatBtcQuanta(toQuanta)
    val digitCount = text.count { it.isDigit() }
    var power = digitCount - 1
    return text.map { ch ->
        if (ch.isDigit()) {
            val p = power
            power -= 1
            val d = ch - '0'
            BtcGlyph(
                key = "p$p",
                digit = d,
                steps = odometerSteps(fromQuanta, toQuanta, p, d),
                literal = null,
            )
        } else {
            BtcGlyph(key = "lit-$ch", digit = null, steps = 0, literal = ch.toString())
        }
    }
}

/** Odometer-style label: each digit slides vertically; punctuation stays put. */
@Composable
private fun RollingDigitsLabel(
    quanta: Long,
    fontSizeSp: Float = 42f,
    modifier: Modifier = Modifier,
) {
    var fromQuanta by remember { mutableLongStateOf(quanta) }
    var primed by remember { mutableStateOf(false) }
    var lastChangeMs by remember { mutableLongStateOf(0L) }
    val nowMs = SystemClock.uptimeMillis()
    val rapid = lastChangeMs > 0L && nowMs - lastChangeMs < 120L
    val jump = kotlin.math.abs(quanta - fromQuanta) > 400L
    val rollFrom = if (
        !primed ||
        (fromQuanta <= 0L && quanta >= 100_000L) ||
        rapid ||
        jump
    ) quanta else fromQuanta
    val glyphs = remember(quanta, rollFrom) { btcGlyphs(rollFrom, quanta) }
    LaunchedEffect(quanta) {
        lastChangeMs = SystemClock.uptimeMillis()
        if (!primed || (fromQuanta <= 0L && quanta >= 100_000L)) {
            fromQuanta = quanta
            primed = true
            return@LaunchedEffect
        }
        fromQuanta = quanta
    }

    val text = formatBtcQuanta(quanta)
    val digitStyle = TextStyle(
        fontSize = fontSizeSp.sp,
        fontWeight = FontWeight.Black,
        color = BrandInk,
        textAlign = TextAlign.Center,
    )
    val measurer = rememberTextMeasurer()
    val measured = remember(text, digitStyle) { measurer.measure(text, style = digitStyle) }

    BoxWithConstraints(
        modifier = modifier.fillMaxWidth(),
        contentAlignment = Alignment.Center,
    ) {
        val maxPx = constraints.maxWidth.toFloat().coerceAtLeast(1f)
        val scale = min(1f, maxPx / measured.size.width.toFloat().coerceAtLeast(1f))
        Row(
            modifier = Modifier.graphicsLayer {
                scaleX = scale
                scaleY = scale
            },
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            glyphs.forEach { glyph ->
                key(glyph.key) {
                    val d = glyph.digit
                    if (d != null) {
                        RollingDigitSlot(
                            digit = d,
                            steps = glyph.steps,
                            rollId = quanta,
                            textStyle = digitStyle,
                        )
                    } else {
                        Text(glyph.literal.orEmpty(), style = digitStyle)
                    }
                }
            }
        }
    }
}

@Composable
private fun RollingDigitSlot(
    digit: Int,
    steps: Int,
    rollId: Long,
    textStyle: TextStyle,
) {
    val target = digit.coerceIn(0, 9)
    // No slide — just tick the glyph through intermediates (incl. full-turn carries).
    var displayed by remember { mutableIntStateOf(target) }
    var primed by remember { mutableStateOf(false) }

    LaunchedEffect(rollId) {
        if (!primed) {
            displayed = target
            primed = true
            return@LaunchedEffect
        }
        val n = steps.coerceAtLeast(0)
        if (n == 0 || n > 6) {
            displayed = target
            return@LaunchedEffect
        }
        try {
            repeat(n) {
                displayed = (displayed + 1) % 10
                delay(35L)
            }
            displayed = target
        } finally {
            // Cancelled mid-sequence (rapid quanta updates): snap to latest.
            displayed = target
        }
    }

    Text(
        text = "$displayed",
        style = textStyle,
        modifier = Modifier.padding(horizontal = 0.5.dp),
    )
}


/** Rate line under the wheel stage: taps/s · power · fill/s — colored by Speed / Power. */
@Composable
private fun BarRateStatus(
    autoActive: Boolean,
    fillRate: Double,
    tapPower: Double,
) {
    val power = if (tapPower > 0.0) tapPower else 1.0
    val annotated = remember(autoActive, fillRate, power) {
        buildAnnotatedString {
            if (!autoActive || fillRate <= 0.0) {
                withStyle(SpanStyle(color = BrandMuted)) { append("Idle") }
                if (power > 1.0 + 1e-9) {
                    withStyle(SpanStyle(color = BrandMuted)) { append(" · ") }
                    withStyle(SpanStyle(color = BrandPower)) {
                        append(String.format("%.2f power", power))
                    }
                }
            } else {
                val tapsPerSec = fillRate / power
                withStyle(SpanStyle(color = BrandSpeed)) {
                    append(String.format("%.2f taps/s", tapsPerSec))
                }
                withStyle(SpanStyle(color = BrandMuted)) { append(" × ") }
                withStyle(SpanStyle(color = BrandPower)) {
                    append(String.format("%.2f power", power))
                }
                withStyle(SpanStyle(color = BrandMuted)) { append(" = ") }
                withStyle(SpanStyle(color = BrandFill)) {
                    append(String.format("%.2f/s", fillRate))
                }
            }
        }
    }
    Text(
        annotated,
        fontWeight = FontWeight.SemiBold,
        fontSize = 12.sp,
        maxLines = 1,
    )
}

internal fun formatLongerAction(t: Tunables?): String {
    val seconds = t?.durationBoostSeconds ?: 1800
    val minutes = seconds / 60
    return if (minutes % 60 == 0 && minutes >= 60) {
        "Add ${minutes / 60}h"
    } else {
        "Add $minutes min"
    }
}

internal fun formatFasterAction(t: Tunables?): String {
    val amount = t?.speedBoostAmount ?: 0.5
    return String.format("+%.2f taps/s", amount)
}

internal fun formatStrongerAction(t: Tunables?): String {
    val amount = t?.tapStrengthBoostAmount ?: 0.25
    return String.format("+%.2f power/tap", amount)
}

internal fun formatSkipTimeAction(t: Tunables?): String {
    val seconds = t?.skipTimeSeconds ?: 60
    val minutes = seconds / 60
    return if (minutes >= 1 && seconds % 60 == 0) {
        "Skip $minutes min"
    } else {
        "Skip ${seconds}s"
    }
}

internal fun formatSkipRemaining(skipAdsRemaining: Int): String {
    return when {
        skipAdsRemaining < 0 -> "Unlimited"
        else -> "$skipAdsRemaining left"
    }
}

internal fun formatSkipButtonStatus(
    skipAdsRemaining: Int,
    cooldownLeft: Int,
    regenLeft: Int = 0,
): String {
    if (cooldownLeft > 0) return "Next in ${cooldownLeft}s"
    if (skipAdsRemaining == 0 && regenLeft > 0) {
        return "Next in ${formatCountdown(regenLeft.toLong())}"
    }
    return formatSkipRemaining(skipAdsRemaining)
}

/** Raw auto tap rate (excludes Stronger). fillRate from server is total units/s. */
internal fun tapsPerSecond(fillRate: Double, tapPower: Double): Double {
    val power = if (tapPower > 0.0) tapPower else 1.0
    return fillRate / power
}

/**
 * Wheel / tap-count / BTC: knocker hits always add, even if the player also tapped.
 * Knocker clock is auto-only (no combo). Manual taps sit on top as `extra`.
 * Knocker may run past the bar (keeps striking); clamp for the counter, don't snap the arm.
 */
internal fun struckSyncedProgress(
    continuous: Double,
    knockerProgress: Double,
    tapPower: Double,
    autoActive: Boolean,
    fillRate: Double,
    total: Int,
): Double {
    if (!autoActive || fillRate <= 0.0) return continuous
    val power = tapPower.coerceAtLeast(0.01)
    val cap = total.toDouble()
    // Stale clock from a previous bar — only then drop back to continuous.
    if (knockerProgress > continuous + cap * 0.5 && knockerProgress > cap + power) {
        return minOf(cap, continuous)
    }
    val knockerHits = floor(minOf(knockerProgress, cap + power) / power + 1e-9)
    val quantized = knockerHits * power
    val extra = maxOf(0.0, continuous - knockerProgress)
    return minOf(cap, quantized + extra)
}

/** Never let BTC / tap-count walk backward except on a real bar wrap. */
internal fun holdMonotonicProgress(held: Double, raw: Double, wrapSlop: Double = 5.0): Double =
    if (raw + wrapSlop < held) raw else maxOf(held, raw)

/** Strike phase from wall-clock. `originUnits / power` preserves phase across rebases. */
internal fun knockerCyclePhase(
    elapsedSec: Double,
    tapsPerSec: Double,
    originUnits: Double,
    tapPower: Double,
): Double {
    if (tapsPerSec <= 0.0) return 0.0
    val power = tapPower.coerceAtLeast(0.01)
    val originFrac = originUnits / power
    val frac = originFrac - floor(originFrac)
    val raw = elapsedSec * tapsPerSec + frac
    return raw - floor(raw)
}

/** Sats earned per hour from the current auto fill rate (0 when idle). */
internal fun satsPerHour(fillRate: Double, unitsPerSat: Int, autoActive: Boolean): Double {
    if (!autoActive || fillRate <= 0.0 || unitsPerSat <= 0) return 0.0
    return (fillRate / unitsPerSat) * 3600.0
}

internal fun formatSatsPerHour(fillRate: Double, unitsPerSat: Int, autoActive: Boolean): String {
    val rate = satsPerHour(fillRate, unitsPerSat, autoActive)
    if (rate <= 0.0) return "0 sats/h"
    return if (rate >= 100.0) {
        String.format("%.0f sats/h", rate)
    } else {
        String.format("%.1f sats/h", rate)
    }
}

internal data class SatParticle(
    val id: Long,
    val from: Offset,
    val to: Offset,
)

/** BTC balance + centered sat wheel + overlapping auto knocker. */
@Composable
private fun SatEarnStage(
    satsBalance: Int,
    displayProgress: Double,
    unitsPerSat: Int,
    autoActive: Boolean,
    autoFillUntil: String?,
    fillRate: Double,
    tapPower: Double,
    combo: ComboState = ComboState(),
    tunables: Tunables? = null,
    onTap: () -> Unit,
    wheelFlash: Float = 0f,
    onWheelTipPositioned: (LayoutCoordinates) -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val comboT = ComboTunables.from(tunables)
    var comboNow by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            comboNow = System.currentTimeMillis()
            delay(32)
        }
    }
    val comboLive = ComboEngine.at(combo, comboNow, comboT)
    val comboMult = comboT.multiplier(comboLive)
    val comboMeters = ComboEngine.displayMeters(comboLive, comboT)
    val comboTracks = ComboEngine.displayTracks(comboLive, comboT)
    val tapsPerSec = tapsPerSecond(fillRate, tapPower)
    // Auto-only knocker clock. Never follow displayProgress (that includes combo taps).
    var nowMs by remember { mutableLongStateOf(System.currentTimeMillis()) }
    var knockerEpochMs by remember { mutableLongStateOf(nowMs) }
    var knockerOrigin by remember { mutableDoubleStateOf(displayProgress) }
    var lastDisplay by remember { mutableDoubleStateOf(displayProgress) }
    var heldVisual by remember { mutableDoubleStateOf(displayProgress) }
    var wasAuto by remember { mutableStateOf(false) }
    var prevFill by remember { mutableDoubleStateOf(fillRate) }
    var prevPower by remember { mutableDoubleStateOf(tapPower) }

    LaunchedEffect(autoActive, fillRate) {
        if (!autoActive || fillRate <= 0.0) return@LaunchedEffect
        while (true) {
            val now = System.currentTimeMillis()
            val elapsed = (now - knockerEpochMs) / 1000.0
            if (elapsed > 60.0) {
                knockerOrigin += fillRate * elapsed
                knockerEpochMs = now
            }
            nowMs = now
            delay(16)
        }
    }
    LaunchedEffect(displayProgress) {
        // True bar wrap / reset only — knocker ahead of the bar is normal.
        if (displayProgress + 5.0 < lastDisplay) {
            knockerOrigin = displayProgress
            knockerEpochMs = System.currentTimeMillis()
            heldVisual = displayProgress
        }
        lastDisplay = displayProgress
    }
    LaunchedEffect(fillRate, tapPower, autoActive) {
        val now = System.currentTimeMillis()
        if (autoActive && !wasAuto) {
            knockerOrigin = displayProgress
            knockerEpochMs = now
        } else if (autoActive && (fillRate != prevFill || tapPower != prevPower)) {
            val current = knockerOrigin + prevFill.coerceAtLeast(0.0) * (now - knockerEpochMs) / 1000.0
            knockerOrigin = current
            knockerEpochMs = now
        }
        wasAuto = autoActive
        prevFill = fillRate
        prevPower = tapPower
    }
    val knockerElapsed = if (autoActive && fillRate > 0.0) {
        (nowMs - knockerEpochMs) / 1000.0
    } else {
        0.0
    }
    val knockerProgress = knockerOrigin + fillRate.coerceAtLeast(0.0) * knockerElapsed
    val continuous = if (!autoActive || fillRate <= 0.0) {
        displayProgress
    } else {
        maxOf(displayProgress, knockerProgress).coerceIn(0.0, unitsPerSat.toDouble())
    }
    val rawVisual = struckSyncedProgress(
        continuous = continuous,
        knockerProgress = knockerProgress,
        tapPower = tapPower,
        autoActive = autoActive,
        fillRate = fillRate,
        total = unitsPerSat,
    )
    val visualProgress = holdMonotonicProgress(heldVisual, rawVisual)
    SideEffect { heldVisual = visualProgress }
    val fraction = if (unitsPerSat > 0) {
        (visualProgress / unitsPerSat).toFloat().coerceIn(0f, 1f)
    } else {
        0f
    }
    val pose = knockerPose(
        elapsedSec = knockerElapsed,
        originUnits = knockerOrigin,
        tapsPerSec = tapsPerSec,
        tapPower = tapPower,
        autoActive = autoActive,
    )
    val wheelSize = 220.dp

    Column(
        modifier = modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            RollingDigitsLabel(
                quanta = btcQuanta(
                    satsBalance = satsBalance,
                    barProgress = visualProgress,
                    unitsPerSat = unitsPerSat,
                ),
                fontSizeSp = 42f,
            )
            Spacer(Modifier.height(2.dp))
            Text(
                "BTC",
                fontSize = 13.sp,
                fontWeight = FontWeight.Bold,
                color = BrandAccent,
                letterSpacing = 3.sp,
            )
        }

        Spacer(Modifier.height(20.dp))

        Text(
            formatSatsPerHour(fillRate = fillRate, unitsPerSat = unitsPerSat, autoActive = autoActive),
            fontWeight = FontWeight.Bold,
            color = BrandAccent,
            fontSize = 14.sp,
        )
        Spacer(Modifier.height(8.dp))

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(wheelSize + 40.dp),
            contentAlignment = Alignment.Center,
        ) {
            // Wheel and tapper are one machine, nudged left to make room for the arm.
            Box(
                modifier = Modifier.offset(x = (-22).dp),
                contentAlignment = Alignment.Center,
            ) {
                SatWheelView(
                    fraction = fraction,
                    flash = wheelFlash,
                    comboFractions = comboMeters,
                    comboTracks = comboTracks,
                    comboMultiplier = comboMult,
                    onTap = onTap,
                    modifier = Modifier
                        .size(wheelSize)
                        .onGloballyPositioned(onWheelTipPositioned),
                )
                AutoKnockerView(pose = pose, active = autoActive, tapPower = tapPower)
                Box(
                    modifier = Modifier
                        .offset(x = 153.dp, y = 74.dp)
                        .width(92.dp),
                ) {
                    SharedAutoTimer(
                        autoFillUntil = autoFillUntil,
                        autoActive = autoActive,
                    )
                }
            }
        }

        Text(
            String.format("%.1f / %d taps", visualProgress, unitsPerSat),
            fontWeight = FontWeight.SemiBold,
            color = BrandInk,
            fontSize = 15.sp,
        )

        Spacer(Modifier.height(12.dp))
        BarRateStatus(autoActive = autoActive, fillRate = fillRate, tapPower = tapPower)
    }
}

/** Where the auto tapper is within one strike cycle. */
private data class KnockerPose(
    /** 0 = cocked on the stop, 1 = head against the rim. Dips negative while winding up. */
    val arm: Float = 0f,
    /** 1 at the moment of contact, fading to 0 shortly after. */
    val impact: Float = 0f,
    /** 0…1 through the current tap, used to turn the drive gears. */
    val phase: Float = 0f,
)

/** Seconds the hammer takes to swing from the cocked stop into the rim. */
private fun knockerStrikeDuration(tapPower: Double): Double =
    maxOf(0.07, 0.16 / tapPower.coerceAtLeast(0.01))

/** Impact VFX scale from tap power. Power 1 = baseline size; capped at power 10 (~2.25×). */
private fun knockerImpactScale(tapPower: Double): Float {
    val p = tapPower.coerceIn(1.0, 10.0)
    return (1.0 + (p - 1.0) / 9.0 * 1.25).toFloat()
}

/** How far the head rebounds off the rim, as a fraction of the full swing. */
private const val KNOCKER_BOUNCE = 0.42
/** Extra travel loaded past the stop just before release. */
private const val KNOCKER_WIND_UP = 0.07
/** Seconds the contact flash lasts. */
private const val KNOCKER_IMPACT_FADE = 0.16

/** Strike cycle for the auto tapper. Phase is wall-clock, not accumulated progress. */
private fun knockerPose(
    elapsedSec: Double,
    originUnits: Double,
    tapsPerSec: Double,
    tapPower: Double,
    autoActive: Boolean,
): KnockerPose {
    if (!autoActive || tapsPerSec <= 0.0) return KnockerPose()
    val period = 1.0 / tapsPerSec
    val phase = knockerCyclePhase(elapsedSec, tapsPerSec, originUnits, tapPower)

    // Segments of one tap, as fractions of the period.
    val strike = minOf(0.34, maxOf(0.06, knockerStrikeDuration(tapPower) / period))
    val recoil = minOf(0.20, maxOf(0.05, 0.07 / period))
    val windUp = maxOf(minOf(0.09, (1.0 - strike - recoil) * 0.2), 0.0001)
    val reset = maxOf(1.0 - strike - recoil - windUp, 0.001)

    val fadeSec = minOf(KNOCKER_IMPACT_FADE, period * 0.55)
    val impact = maxOf(0.0, 1.0 - (phase * period) / fadeSec).pow(1.7)
    val arm = when {
        // Rebounds off the rim.
        phase < recoil -> 1.0 - KNOCKER_BOUNCE * easeOutQuad(phase / recoil)
        // Drive hauls the hammer back onto its stop.
        phase < recoil + reset ->
            (1.0 - KNOCKER_BOUNCE) * (1.0 - easeInOutCubic((phase - recoil) / reset))
        // Held on the stop, loading a little extra travel.
        phase < 1.0 - strike ->
            -KNOCKER_WIND_UP * easeOutQuad((phase - recoil - reset) / windUp)
        // Released: accelerates the whole way in, with no cushion at the end.
        else -> {
            val t = minOf(1.0, (phase - (1.0 - strike)) / strike)
            -KNOCKER_WIND_UP + (1.0 + KNOCKER_WIND_UP) * t.pow(2.3)
        }
    }

    return KnockerPose(arm = arm.toFloat(), impact = impact.toFloat(), phase = phase.toFloat())
}

@Composable
private fun SatWheelView(
    fraction: Float,
    flash: Float,
    comboFractions: List<Double> = listOf(0.0, 0.0, 0.0),
    comboTracks: List<Boolean> = listOf(true, false, false),
    comboMultiplier: Double = 1.0,
    onTap: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val comboLabel = ComboEngine.formatMultiplier(comboMultiplier)
    Box(
        modifier = modifier
            .clip(CircleShape)
            .clickable(onClick = onTap),
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val sizeMin = size.minDimension
            val rim = sizeMin * 0.06f
            val center = Offset(size.width / 2f, size.height / 2f)
            val radius = sizeMin / 2f - rim / 2f
            val outerFrac = comboFractions.getOrNull(0)?.toFloat() ?: 0f
            val innerFrac = comboFractions.getOrNull(1)?.toFloat() ?: 0f
            val coreFrac = comboFractions.getOrNull(2)?.toFloat() ?: 0f
            val show0 = comboTracks.getOrNull(0) == true
            val show1 = comboTracks.getOrNull(1) == true
            val show2 = comboTracks.getOrNull(2) == true

            fun drawComboRing(
                ringRadius: Float,
                stroke: Float,
                frac: Float,
                color: Color,
                showTrack: Boolean,
                trackAlpha: Float,
                tickCount: Int,
            ) {
                val drawArc = frac > 0.001f
                if (showTrack || drawArc) {
                    drawCircle(
                        color = BrandInk.copy(alpha = 0.22f),
                        radius = ringRadius,
                        center = center,
                        style = Stroke(width = stroke * 1.22f),
                    )
                    drawCircle(
                        color = BrandInk.copy(alpha = trackAlpha),
                        radius = ringRadius,
                        center = center,
                        style = Stroke(width = stroke),
                    )
                    val majorEvery = (tickCount / 12).coerceAtLeast(1)
                    for (i in 0 until tickCount) {
                        val major = i % majorEvery == 0
                        val angleRad = Math.toRadians(i * 360.0 / tickCount - 90.0)
                        val half = if (major) stroke * 0.44f else stroke * 0.21f
                        val cosA = cos(angleRad).toFloat()
                        val sinA = sin(angleRad).toFloat()
                        drawLine(
                            color = BrandInk.copy(alpha = if (major) 0.32f else 0.11f),
                            start = Offset(center.x + cosA * (ringRadius - half), center.y + sinA * (ringRadius - half)),
                            end = Offset(center.x + cosA * (ringRadius + half), center.y + sinA * (ringRadius + half)),
                            strokeWidth = if (major) 1.5f else 0.7f,
                            cap = StrokeCap.Round,
                        )
                    }
                    for (i in 0 until 4) {
                        val angleRad = Math.toRadians(i * 90.0 - 90.0)
                        val rivetR = ringRadius - stroke * 0.12f
                        drawCircle(
                            color = BrandInk.copy(alpha = 0.42f),
                            radius = 1.6f,
                            center = Offset(
                                center.x + cos(angleRad).toFloat() * rivetR,
                                center.y + sin(angleRad).toFloat() * rivetR,
                            ),
                        )
                    }
                }
                if (!drawArc) return
                val sweep = 360f * frac.coerceIn(0f, 1f)
                val fresh = frac < 0.18f
                val box = Offset(center.x - ringRadius, center.y - ringRadius)
                val boxSize = Size(ringRadius * 2f, ringRadius * 2f)
                drawArc(
                    color = color.copy(alpha = if (fresh) 0.42f else 0.22f),
                    startAngle = -90f,
                    sweepAngle = sweep,
                    useCenter = false,
                    topLeft = box,
                    size = boxSize,
                    style = Stroke(width = stroke * if (fresh) 1.85f else 1.55f, cap = StrokeCap.Round),
                )
                drawArc(
                    color = BrandInk.copy(alpha = 0.38f),
                    startAngle = -90f,
                    sweepAngle = sweep,
                    useCenter = false,
                    topLeft = box,
                    size = boxSize,
                    style = Stroke(width = stroke, cap = StrokeCap.Round),
                )
                drawArc(
                    color = color,
                    startAngle = -90f,
                    sweepAngle = sweep,
                    useCenter = false,
                    topLeft = box,
                    size = boxSize,
                    style = Stroke(width = stroke * 0.70f, cap = StrokeCap.Round),
                )
            }

            drawCircle(
                color = BrandInk.copy(alpha = 0.08f),
                radius = radius,
                center = center,
                style = Stroke(width = rim),
            )

            val sweep = 360f * fraction
            if (sweep > 0.1f) {
                drawArc(
                    brush = Brush.sweepGradient(
                        colors = if (flash > 0.3f) {
                            listOf(BrandAccent, Color.White, BrandAccent)
                        } else {
                            listOf(BrandFill, BrandFillHot, BrandFill)
                        },
                        center = center,
                    ),
                    startAngle = -90f,
                    sweepAngle = sweep,
                    useCenter = false,
                    topLeft = Offset(center.x - radius, center.y - radius),
                    size = Size(radius * 2f, radius * 2f),
                    style = Stroke(width = rim, cap = StrokeCap.Round),
                )
            }

            val comboRim = rim * 0.50f
            val comboGap = comboRim * 0.35f
            val comboPitch = comboRim + comboGap
            val comboRadius = radius - rim * 1.05f
            val ring1Radius = comboRadius - comboPitch
            val ring2Radius = ring1Radius - comboPitch
            val innerShown = when {
                show2 || coreFrac > 0.001f -> 2
                show1 || innerFrac > 0.001f -> 1
                else -> 0
            }
            val innerComboR = when (innerShown) {
                2 -> ring2Radius
                1 -> ring1Radius
                else -> comboRadius
            }
            val pegOrbit = maxOf(sizeMin * 0.16f, innerComboR - comboRim * 0.55f - 5f)

            rotate(degrees = fraction * 360f, pivot = center) {
                drawCircle(
                    brush = Brush.radialGradient(
                        colors = listOf(
                            BrandInk.copy(alpha = 0.04f),
                            BrandInk.copy(alpha = 0.10f),
                        ),
                        center = center,
                        radius = sizeMin * 0.48f,
                    ),
                    radius = sizeMin * 0.42f,
                    center = center,
                )
                for (i in 0 until 60) {
                    val angleRad = Math.toRadians(i * 6.0 - 90.0)
                    val outer = sizeMin * 0.365f
                    val inner = outer - 5f
                    val cosA = cos(angleRad).toFloat()
                    val sinA = sin(angleRad).toFloat()
                    drawLine(
                        color = BrandInk.copy(alpha = 0.10f),
                        start = Offset(center.x + cosA * inner, center.y + sinA * inner),
                        end = Offset(center.x + cosA * outer, center.y + sinA * outer),
                        strokeWidth = 0.8f,
                        cap = StrokeCap.Round,
                    )
                }
                for (i in 0 until 12) {
                    val angleRad = Math.toRadians(i * 30.0 - 90.0)
                    val outer = sizeMin * 0.38f
                    val inner = outer - if (i % 3 == 0) 14f else 9f
                    val cosA = cos(angleRad).toFloat()
                    val sinA = sin(angleRad).toFloat()
                    drawLine(
                        color = BrandInk.copy(alpha = if (i % 3 == 0) 0.35f else 0.16f),
                        start = Offset(center.x + cosA * inner, center.y + sinA * inner),
                        end = Offset(center.x + cosA * outer, center.y + sinA * outer),
                        strokeWidth = if (i % 3 == 0) 3f else 2f,
                        cap = StrokeCap.Round,
                    )
                }
            }

            drawComboRing(comboRadius, comboRim, outerFrac, ComboRing0, showTrack = true, trackAlpha = 0.10f, tickCount = 60)
            drawComboRing(ring1Radius, comboRim, innerFrac, ComboRing1, showTrack = show1, trackAlpha = 0.14f, tickCount = 48)
            drawComboRing(ring2Radius, comboRim, coreFrac, ComboRing2, showTrack = show2, trackAlpha = 0.18f, tickCount = 36)

            if (show0 || outerFrac > 0.001f || show1 || innerFrac > 0.001f || show2 || coreFrac > 0.001f) {
                for (i in 0 until 18) {
                    val angleRad = Math.toRadians(i * 20.0 - 90.0)
                    val toothOuter = innerComboR - comboRim * 0.57f
                    val toothInner = toothOuter - comboRim * 0.5f
                    val cosA = cos(angleRad).toFloat()
                    val sinA = sin(angleRad).toFloat()
                    drawLine(
                        color = BrandInk.copy(alpha = 0.30f),
                        start = Offset(center.x + cosA * toothInner, center.y + sinA * toothInner),
                        end = Offset(center.x + cosA * toothOuter, center.y + sinA * toothOuter),
                        strokeWidth = 1.3f,
                        cap = StrokeCap.Round,
                    )
                }
            }

            // Peg just inside the innermost drawn combo stroke, on top of the rings.
            rotate(degrees = fraction * 360f, pivot = center) {
                drawCircle(
                    color = BrandInk.copy(alpha = 0.55f),
                    radius = 5f,
                    center = Offset(center.x, center.y - pegOrbit),
                )
                drawCircle(
                    color = BrandAccent.copy(alpha = 0.95f),
                    radius = 3.5f,
                    center = Offset(center.x, center.y - pegOrbit),
                )
            }

            // Fixed 12 o'clock pointer
            val tipY = center.y - sizeMin * 0.5f + 4f
            val pointer = Path().apply {
                moveTo(center.x, tipY)
                lineTo(center.x + 7f, tipY + 12f)
                lineTo(center.x - 7f, tipY + 12f)
                close()
            }
            drawPath(
                path = pointer,
                color = if (flash > 0.3f) BrandAccent else BrandInk.copy(alpha = 0.75f),
            )

            // Strike plate at 3 o'clock — where the auto tapper lands.
            val plateUnit = 1.dp.toPx()
            drawRoundRect(
                color = BrandInk.copy(alpha = 0.30f),
                topLeft = Offset(
                    center.x + sizeMin * 0.5f - 4.5f * plateUnit,
                    center.y - 13f * plateUnit,
                ),
                size = Size(9f * plateUnit, 26f * plateUnit),
                cornerRadius = CornerRadius(3f * plateUnit, 3f * plateUnit),
            )
            drawRoundRect(
                color = BrandInk.copy(alpha = 0.35f),
                topLeft = Offset(
                    center.x + sizeMin * 0.5f - 4.5f * plateUnit,
                    center.y - 13f * plateUnit,
                ),
                size = Size(9f * plateUnit, 26f * plateUnit),
                cornerRadius = CornerRadius(3f * plateUnit, 3f * plateUnit),
                style = Stroke(width = plateUnit),
            )

            drawCircle(
                brush = Brush.verticalGradient(
                    colors = listOf(BrandInk.copy(alpha = 0.12f), BrandInk.copy(alpha = 0.06f)),
                ),
                radius = sizeMin * 0.14f,
                center = center,
            )
            drawCircle(
                color = BrandInk.copy(alpha = 0.12f),
                radius = sizeMin * 0.14f,
                center = center,
                style = Stroke(width = 1f),
            )
            if (comboLabel.isEmpty()) {
                drawCircle(
                    color = BrandAccent.copy(alpha = if (flash > 0.3f) 0.55f else 0.2f),
                    radius = sizeMin * 0.04f,
                    center = center,
                )
            }

            if (flash > 0.3f) {
                drawCircle(
                    color = BrandAccent.copy(alpha = 0.85f * flash),
                    radius = sizeMin / 2f - 1f,
                    center = center,
                    style = Stroke(width = 2f),
                )
            }
        }
        if (comboLabel.isNotEmpty()) {
            Text(
                comboLabel,
                color = BrandAccent,
                fontWeight = FontWeight.Bold,
                fontSize = 13.sp,
            )
        }
    }
}

/** Fixed tapper geometry, in dp relative to the wheel centre. */
private object KnockerGeometry {
    /** Hammer pivot, up and to the right of the wheel. */
    const val PIVOT_X = 150f
    const val PIVOT_Y = -72f
    /** Head centre at contact — one HEAD_HALF_LENGTH back from the strike point. */
    const val CONTACT_X = 117.1f
    const val CONTACT_Y = -9.7f
    /** The spot on the rim the face lands on (3 o'clock, wheel radius 110). */
    const val STRIKE_X = 112f
    const val STRIKE_Y = 0f
    /** Degrees travelled between the cocked stop and contact. */
    const val SWEEP_DEGREES = 42f
    const val HEAD_HALF_LENGTH = 11f
    const val HEAD_HALF_WIDTH = 15f

    /** Housing the pivot and drive gears are bolted to. */
    const val PLATE_X = 128f
    const val PLATE_Y = -110f
    const val PLATE_W = 50f
    const val PLATE_H = 56f
    const val WINDOW_X = 133f
    const val WINDOW_Y = -105f
    const val WINDOW_W = 40f
    const val WINDOW_H = 26f
    const val DRIVE_X = 146f
    const val DRIVE_Y = -92f
    const val IDLER_X = 164f
    const val IDLER_Y = -92f
    const val DRIVE_RADIUS = 11f
    const val IDLER_RADIUS = 7f

    /** Bumper the arm rests against while cocked. */
    const val STOP_X = 163f
    const val STOP_Y = -53f
    const val STOP_W = 8f
    const val STOP_H = 14f

    val armLength = hypot(CONTACT_X - PIVOT_X, CONTACT_Y - PIVOT_Y)
    val strikeAngle = atan2(CONTACT_Y - PIVOT_Y, CONTACT_X - PIVOT_X)

    /** Arm angle in radians for a pose value. */
    fun angle(arm: Float): Float =
        strikeAngle - (SWEEP_DEGREES * PI.toFloat() / 180f) * (1f - arm)
}

/**
 * Side-mounted auto tapper: a geared hammer that swings onto the wheel rim.
 * Driven only by Auto fill progress — manual taps do not move it.
 */
@Composable
private fun AutoKnockerView(pose: KnockerPose, active: Boolean, tapPower: Double = 1.0) {
    Canvas(Modifier.requiredSize(400.dp, 300.dp)) {
        drawTapper(pose = pose, tapPower = tapPower, active = active)
    }
}

private fun DrawScope.drawTapper(pose: KnockerPose, tapPower: Double, active: Boolean) {
    val g = KnockerGeometry
    val u = 1.dp.toPx()
    val origin = Offset(size.width / 2f, size.height / 2f)
    val impact = if (active) pose.impact else 0f
    val hitScale = if (active) knockerImpactScale(tapPower) else 1f
    val fade = if (active) 1f else 0.4f

    val angle = g.angle(pose.arm)
    // Contact shoves the whole mount back along the strike axis.
    val kick = Offset(
        -cos(g.strikeAngle) * impact * 3f * hitScale * u,
        -sin(g.strikeAngle) * impact * 3f * hitScale * u,
    )
    fun mounted(x: Float, y: Float) =
        Offset(origin.x + x * u + kick.x, origin.y + y * u + kick.y)

    // Housing.
    val plateTopLeft = mounted(g.PLATE_X, g.PLATE_Y)
    val plateSize = Size(g.PLATE_W * u, g.PLATE_H * u)
    drawRoundRect(
        brush = Brush.linearGradient(
            colors = listOf(
                BrandInk.copy(alpha = 0.21f * fade),
                BrandInk.copy(alpha = 0.07f * fade),
            ),
            start = plateTopLeft,
            end = Offset(plateTopLeft.x + plateSize.width, plateTopLeft.y + plateSize.height),
        ),
        topLeft = plateTopLeft,
        size = plateSize,
        cornerRadius = CornerRadius(8f * u, 8f * u),
    )
    drawRoundRect(
        color = BrandInk.copy(alpha = 0.22f * fade),
        topLeft = plateTopLeft,
        size = plateSize,
        cornerRadius = CornerRadius(8f * u, 8f * u),
        style = Stroke(width = u),
    )
    drawRoundRect(
        color = BrandInk.copy(alpha = 0.10f * fade),
        topLeft = Offset(plateTopLeft.x + 5f * u, plateTopLeft.y + 5f * u),
        size = Size(plateSize.width - 10f * u, plateSize.height - 10f * u),
        cornerRadius = CornerRadius(5f * u, 5f * u),
        style = Stroke(width = u),
    )

    // Gear window, then the drive train — one turn per tap, so the machine reads
    // as the thing swinging the arm.
    drawRoundRect(
        color = Color.Black.copy(alpha = 0.35f * fade),
        topLeft = mounted(g.WINDOW_X, g.WINDOW_Y),
        size = Size(g.WINDOW_W * u, g.WINDOW_H * u),
        cornerRadius = CornerRadius(13f * u, 13f * u),
    )
    val turn = pose.phase * 2f * PI.toFloat()
    drawGear(
        center = mounted(g.DRIVE_X, g.DRIVE_Y),
        radius = g.DRIVE_RADIUS * u,
        teeth = 9,
        rotation = turn,
        color = BrandInk.copy(alpha = 0.34f * fade),
        hub = BrandInk.copy(alpha = 0.5f * fade),
    )
    drawGear(
        center = mounted(g.IDLER_X, g.IDLER_Y),
        radius = g.IDLER_RADIUS * u,
        teeth = 6,
        rotation = -turn * (g.DRIVE_RADIUS / g.IDLER_RADIUS) + PI.toFloat() / 6f,
        color = BrandInk.copy(alpha = 0.28f * fade),
        hub = BrandInk.copy(alpha = 0.44f * fade),
    )

    for (boltX in listOf(g.PLATE_X + 9f, g.PLATE_X + g.PLATE_W - 9f)) {
        val bolt = mounted(boltX, g.PLATE_Y + g.PLATE_H - 9f)
        drawCircle(BrandInk.copy(alpha = 0.26f * fade), radius = 3f * u, center = bolt)
        drawCircle(BrandInk.copy(alpha = 0.5f * fade), radius = 1.2f * u, center = bolt)
    }

    drawRoundRect(
        color = BrandInk.copy(alpha = 0.30f * fade),
        topLeft = mounted(g.STOP_X, g.STOP_Y),
        size = Size(g.STOP_W * u, g.STOP_H * u),
        cornerRadius = CornerRadius(3f * u, 3f * u),
    )

    // Arm and head, drawn along +x from the pivot.
    val pivot = mounted(g.PIVOT_X, g.PIVOT_Y)
    val length = g.armLength * u
    withTransform({
        translate(pivot.x, pivot.y)
        rotate(angle * 180f / PI.toFloat(), Offset.Zero)
    }) {
        val bar = Path().apply {
            fillType = PathFillType.EvenOdd
            moveTo(-11f * u, -9f * u)
            lineTo(length - 8f * u, -5.5f * u)
            lineTo(length - 8f * u, 5.5f * u)
            lineTo(-11f * u, 9f * u)
            close()
            for (at in listOf(length * 0.34f, length * 0.56f)) {
                addOval(
                    Rect(
                        left = at - 3.2f * u,
                        top = -3.2f * u,
                        right = at + 3.2f * u,
                        bottom = 3.2f * u,
                    ),
                )
            }
        }
        drawPath(
            path = bar,
            brush = Brush.verticalGradient(
                colors = listOf(
                    BrandInk.copy(alpha = 0.58f * fade),
                    BrandInk.copy(alpha = 0.22f * fade),
                ),
                startY = -9f * u,
                endY = 9f * u,
            ),
        )
        drawLine(
            color = BrandInk.copy(alpha = 0.72f * fade),
            start = Offset(-8f * u, -7f * u),
            end = Offset(length - 8f * u, -4f * u),
            strokeWidth = 1.5f * u,
        )

        withTransform({
            translate(length, 0f)
            // Impact squashes the head into the rim.
            scale(1f - 0.18f * impact, 1f + 0.16f * impact, Offset.Zero)
        }) {
            val halfLength = g.HEAD_HALF_LENGTH * u
            val halfWidth = g.HEAD_HALF_WIDTH * u
            drawRoundRect(
                color = BrandInk.copy(alpha = 0.45f * fade),
                topLeft = Offset(-14f * u, -9f * u),
                size = Size(8f * u, 18f * u),
                cornerRadius = CornerRadius(2.5f * u, 2.5f * u),
            )
            drawRoundRect(
                brush = Brush.verticalGradient(
                    colors = listOf(
                        BrandAccentHot.copy(alpha = fade),
                        BrandAccent.copy(alpha = fade),
                    ),
                    startY = -halfWidth,
                    endY = halfWidth,
                ),
                topLeft = Offset(-halfLength, -halfWidth),
                size = Size(halfLength * 2f, halfWidth * 2f),
                cornerRadius = CornerRadius(5f * u, 5f * u),
            )
            drawRoundRect(
                color = Color.White.copy(alpha = (0.28f + 0.55f * impact) * fade),
                topLeft = Offset(halfLength - 6f * u, -halfWidth + 3f * u),
                size = Size(6f * u, halfWidth * 2f - 6f * u),
                cornerRadius = CornerRadius(3f * u, 3f * u),
            )
            drawCircle(Color.Black.copy(alpha = 0.18f * fade), radius = 2.5f * u, center = Offset.Zero)
        }
    }

    // Pivot boss on top of the arm root.
    drawCircle(BrandInk.copy(alpha = 0.34f * fade), radius = 9f * u, center = pivot)
    drawCircle(
        BrandInk.copy(alpha = 0.3f * fade),
        radius = 9f * u,
        center = pivot,
        style = Stroke(width = u),
    )
    drawCircle(BrandInk.copy(alpha = 0.55f * fade), radius = 3.5f * u, center = pivot)

    if (impact <= 0.01f) return

    // Contact flash on the rim — grows with Stronger (capped at power 10).
    val hit = Offset(origin.x + g.STRIKE_X * u, origin.y + g.STRIKE_Y * u)
    val strokeW = (1.5f + 0.5f * hitScale) * u
    drawCircle(
        color = BrandAccent.copy(alpha = 0.6f * impact),
        radius = (10f + 24f * (1f - impact)) * hitScale * u,
        center = hit,
        style = Stroke(width = strokeW),
    )
    val sparkCount = 4 + (((hitScale - 1f) / 1.25f) * 4f).toInt() // 4…8
    for (i in 0 until sparkCount) {
        val a = (45f + i * (360f / sparkCount)) * PI.toFloat() / 180f
        val near = (10f + 8f * (1f - impact)) * hitScale * u
        val far = near + (8f + 14f * (1f - impact)) * hitScale * u
        drawLine(
            color = BrandAccent.copy(alpha = 0.85f * impact),
            start = Offset(hit.x + cos(a) * near, hit.y + sin(a) * near),
            end = Offset(hit.x + cos(a) * far, hit.y + sin(a) * far),
            strokeWidth = strokeW,
            cap = StrokeCap.Round,
        )
    }
    drawCircle(
        color = Color.White.copy(alpha = 0.75f * impact),
        radius = (4f + 7f * impact) * hitScale * u,
        center = hit,
    )
}

private fun DrawScope.drawGear(
    center: Offset,
    radius: Float,
    teeth: Int,
    rotation: Float,
    color: Color,
    hub: Color,
) {
    val root = radius * 0.72f
    val path = Path()
    for (i in 0 until teeth * 2) {
        val r = if (i % 2 == 0) radius else root
        val a = rotation + i * PI.toFloat() / teeth
        val x = center.x + cos(a) * r
        val y = center.y + sin(a) * r
        if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
    }
    path.close()
    drawPath(path, color)
    drawCircle(hub, radius = radius * 0.26f, center = center)
}

private fun easeOutQuad(t: Double): Double {
    val x = t.coerceIn(0.0, 1.0)
    return 1.0 - (1.0 - x) * (1.0 - x)
}

private fun easeInOutCubic(t: Double): Double {
    val x = t.coerceIn(0.0, 1.0)
    return if (x < 0.5) 4.0 * x * x * x else 1.0 - (-2.0 * x + 2.0).pow(3) / 2.0
}

internal object SatParticleMotion {
    const val POP_MS = 320L
    const val HOVER_MS = 500L
    const val FLY_MS = 850
    /** When the orb arrives at the Redeem tab (for afterglow sync). */
    const val LAND_AT_MS = POP_MS + HOVER_MS + FLY_MS - 60L
}

@Composable
internal fun FlyingSatParticle(
    particle: SatParticle,
    onFinished: () -> Unit,
) {
    val popT = remember { Animatable(0f) }
    val flyT = remember { Animatable(0f) }
    val bob = remember { Animatable(0f) }
    val density = LocalDensity.current
    val popUpPx = with(density) { 58.dp.toPx() }
    val popOutPx = with(density) { 18.dp.toPx() }
    val curveBulgePx = with(density) { 42.dp.toPx() }
    val curveLiftPx = with(density) { 36.dp.toPx() }
    val bobPx = with(density) { 7.dp.toPx() }
    val orbPx = with(density) { 44.dp.toPx() }

    LaunchedEffect(particle.id) {
        // 1) Pop out of the wheel tip
        popT.animateTo(
            1f,
            animationSpec = spring(
                dampingRatio = 0.58f,
                stiffness = Spring.StiffnessMediumLow,
            ),
        )
        // 2) Hover / breathe
        val hoverJob = launch {
            while (true) {
                bob.animateTo(-bobPx, animationSpec = tween(420, easing = FastOutSlowInEasing))
                bob.animateTo(0f, animationSpec = tween(420, easing = FastOutSlowInEasing))
            }
        }
        delay(SatParticleMotion.HOVER_MS)
        hoverJob.cancel()
        bob.snapTo(0f)
        // 3) Ease along the curve to the Redeem tab
        flyT.animateTo(
            1f,
            animationSpec = tween(
                durationMillis = SatParticleMotion.FLY_MS,
                easing = CubicBezierEasing(0.4f, 0.0f, 0.15f, 1.0f),
            ),
        )
        delay(80)
        onFinished()
    }

    val hover = Offset(particle.from.x + popOutPx, particle.from.y - popUpPx)
    val ctrl = Offset(
        x = hover.x + (particle.to.x - hover.x) * 0.3f + curveBulgePx,
        y = minOf(hover.y, particle.to.y) - curveLiftPx,
    )
    val flyEased = smoothstep(flyT.value)
    val pos = if (flyT.value > 0.0001f) {
        quadBezier(hover, ctrl, particle.to, flyEased)
    } else {
        val p = lerp(particle.from, hover, popEase(popT.value))
        Offset(p.x, p.y + bob.value)
    }
    val scale = if (flyT.value > 0.0001f) {
        1.28f - 0.38f * flyEased
    } else {
        0.55f + 0.78f * popEase(popT.value)
    }
    val alpha = when {
        popT.value < 0.15f -> (popT.value / 0.15f).coerceIn(0f, 1f)
        flyT.value < 0.82f -> 1f
        else -> ((1f - flyT.value) / 0.18f).coerceAtLeast(0f)
    }

    Box(
        modifier = Modifier
            .offset {
                IntOffset(
                    (pos.x - orbPx / 2f).roundToInt(),
                    (pos.y - orbPx / 2f).roundToInt(),
                )
            }
            .size(44.dp)
            .graphicsLayer {
                scaleX = scale
                scaleY = scale
                this.alpha = alpha
                clip = false
            }
            .drawBehind {
                drawCircle(
                    brush = Brush.radialGradient(
                        colors = listOf(
                            Color.White.copy(alpha = 0.95f),
                            BrandAccent,
                            BrandAccentHot.copy(alpha = 0.35f),
                            Color.Transparent,
                        ),
                    ),
                    radius = size.minDimension * 0.72f,
                )
            },
        contentAlignment = Alignment.Center,
    ) {
        Text(
            "S",
            color = BrandOnAccent.copy(alpha = 0.92f),
            fontSize = 18.sp,
            fontWeight = FontWeight.Black,
        )
    }
}

private fun popEase(t: Float): Float {
    val x = t.coerceIn(0f, 1f)
    return 1f - (1f - x) * (1f - x) * (1f - x)
}

private fun smoothstep(t: Float): Float {
    val x = t.coerceIn(0f, 1f)
    return x * x * (3f - 2f * x)
}

private fun lerp(a: Offset, b: Offset, t: Float): Offset =
    Offset(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)

private fun quadBezier(p0: Offset, p1: Offset, p2: Offset, t: Float): Offset {
    val u = 1f - t
    return Offset(
        x = u * u * p0.x + 2f * u * t * p1.x + t * t * p2.x,
        y = u * u * p0.y + 2f * u * t * p1.y + t * t * p2.y,
    )
}

internal fun playSatTick() {
    try {
        val tg = ToneGenerator(AudioManager.STREAM_MUSIC, 80)
        tg.startTone(ToneGenerator.TONE_PROP_BEEP, 70)
        Handler(Looper.getMainLooper()).postDelayed({ tg.release() }, 100)
    } catch (_: Exception) {
        // ToneGenerator can fail on some emulators — haptic still fires.
    }
}

@Composable
private fun SkipTimeButton(
    actionLabel: String,
    remainingLabel: String,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    val shape = RoundedCornerShape(14.dp)
    val theme = BrandTime
    val titleColor = if (enabled) BrandInk else BrandMuted.copy(alpha = 0.55f)
    val detailColor = if (enabled) theme else BrandMuted.copy(alpha = 0.45f)
    val bg = if (enabled) {
        Brush.horizontalGradient(
            listOf(BrandInk.copy(alpha = 0.06f), theme.copy(alpha = 0.20f)),
        )
    } else {
        Brush.horizontalGradient(
            listOf(BrandInk.copy(alpha = 0.03f), BrandInk.copy(alpha = 0.05f)),
        )
    }
    val borderColor = if (enabled) theme.copy(alpha = 0.85f) else BrandInk.copy(alpha = 0.08f)

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(52.dp)
            .clip(shape)
            .background(bg)
            .border(1.5.dp, borderColor, shape)
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            actionLabel,
            fontSize = 16.sp,
            fontWeight = FontWeight.Bold,
            color = titleColor,
        )
        Text(
            remainingLabel,
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            color = detailColor,
        )
    }
}

@Composable
private fun BoostButton(
    title: String,
    actionLabel: String,
    theme: Color,
    enabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    running: Boolean = false,
    applyCount: Int = 0,
    showCount: Boolean = true,
) {
    val visual = when {
        running && enabled -> BoostVisual.RunningReady
        running && !enabled -> BoostVisual.RunningLocked
        enabled -> BoostVisual.Ready
        else -> BoostVisual.Locked
    }

    val shape = RoundedCornerShape(18.dp)
    val titleColor = when (visual) {
        BoostVisual.Ready, BoostVisual.RunningReady -> BrandInk
        BoostVisual.RunningLocked -> BrandInk.copy(alpha = 0.55f)
        BoostVisual.Locked -> BrandMuted.copy(alpha = 0.55f)
    }
    val detailColor = when (visual) {
        BoostVisual.Ready -> theme
        BoostVisual.RunningReady -> BrandOnAccent
        BoostVisual.RunningLocked -> theme.copy(alpha = 0.55f)
        BoostVisual.Locked -> BrandMuted.copy(alpha = 0.45f)
    }
    val countColor = when (visual) {
        BoostVisual.Ready -> BrandInk.copy(alpha = 0.45f)
        BoostVisual.RunningReady -> BrandOnAccent.copy(alpha = 0.75f)
        BoostVisual.RunningLocked -> theme.copy(alpha = 0.40f)
        BoostVisual.Locked -> BrandMuted.copy(alpha = 0.35f)
    }
    val bg = when (visual) {
        BoostVisual.Ready -> Brush.verticalGradient(
            listOf(BrandInk.copy(alpha = 0.06f), theme.copy(alpha = 0.18f)),
        )
        BoostVisual.RunningReady -> Brush.verticalGradient(
            listOf(theme.copy(alpha = 0.95f), theme.copy(alpha = 0.70f)),
        )
        BoostVisual.RunningLocked -> Brush.verticalGradient(
            listOf(BrandInk.copy(alpha = 0.05f), theme.copy(alpha = 0.10f)),
        )
        BoostVisual.Locked -> Brush.verticalGradient(
            listOf(BrandInk.copy(alpha = 0.03f), BrandInk.copy(alpha = 0.05f)),
        )
    }
    val borderColor = when (visual) {
        BoostVisual.Ready -> theme.copy(alpha = 0.85f)
        BoostVisual.RunningReady -> theme
        BoostVisual.RunningLocked -> theme.copy(alpha = 0.35f)
        BoostVisual.Locked -> BrandInk.copy(alpha = 0.08f)
    }
    val borderWidth = when (visual) {
        BoostVisual.Ready -> 1.5.dp
        BoostVisual.RunningReady -> 2.dp
        BoostVisual.RunningLocked -> 1.5.dp
        BoostVisual.Locked -> 1.dp
    }

    Column(
        modifier
            .clip(shape)
            .background(bg)
            .border(borderWidth, borderColor, shape)
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 4.dp, vertical = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            title,
            fontSize = 17.sp,
            fontWeight = FontWeight.Bold,
            color = titleColor,
            textAlign = TextAlign.Center,
            maxLines = 2,
        )
        Text(
            actionLabel,
            fontSize = 11.sp,
            color = detailColor,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center,
            maxLines = 1,
        )
        if (showCount) {
            Text(
                "($applyCount)",
                fontSize = 11.sp,
                color = countColor,
                fontWeight = FontWeight.SemiBold,
                textAlign = TextAlign.Center,
                maxLines = 1,
            )
        }
    }
}

internal fun remainingSeconds(untilIso: String?, nowMs: Long = System.currentTimeMillis()): Long {
    if (untilIso.isNullOrBlank()) return 0L
    return try {
        val untilMs = Instant.parse(untilIso).toEpochMilli()
        maxOf(0L, (untilMs - nowMs) / 1000L)
    } catch (_: DateTimeParseException) {
        0L
    }
}

internal fun formatCountdown(totalSeconds: Long): String {
    var rem = maxOf(0L, totalSeconds)
    val d = rem / 86_400L
    rem %= 86_400L
    val h = rem / 3_600L
    rem %= 3_600L
    val m = rem / 60L
    val s = rem % 60L
    val parts = mutableListOf<String>()
    if (d > 0) parts.add("${d}d")
    if (h > 0 || d > 0) parts.add("${h}h")
    if (m > 0 || h > 0 || d > 0) parts.add("${m}m")
    parts.add("${s}s")
    return parts.joinToString(" ")
}
