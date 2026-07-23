package com.adplay.app.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.adplay.app.UiState
import com.adplay.app.data.Tunables
import java.time.Instant
import java.time.format.DateTimeParseException
import kotlin.math.floor
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
    onLonger: () -> Unit,
    onFaster: () -> Unit,
    onStronger: () -> Unit,
    onSkipTime: () -> Unit,
    onRedeem: () -> Unit,
    onDebugReset: () -> Unit,
    onToggleBypassAds: () -> Unit,
    onRetry: () -> Unit,
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
                    state.adsRemainingToday > 0 &&
                    state.adCooldownSecondsLeft == 0
                var displayProgress by remember { mutableDoubleStateOf(state.progress) }

                // Smooth local fill between server polls — shared by BTC balance + progress bar.
                LaunchedEffect(state.progress, state.fillRate, state.autoFillActive, state.unitsPerSat) {
                    if (state.progress + 5.0 < displayProgress) {
                        // Bar completed (progress wrapped) or debug reset
                        displayProgress = state.progress
                    } else if (state.progress > displayProgress) {
                        displayProgress = state.progress
                    }
                    if (!state.autoFillActive || state.fillRate <= 0.0 || state.unitsPerSat <= 0) {
                        return@LaunchedEffect
                    }
                    val start = displayProgress
                    val startMs = System.currentTimeMillis()
                    while (true) {
                        delay(50)
                        val elapsed = (System.currentTimeMillis() - startMs) / 1000.0
                        val next = start + state.fillRate * elapsed
                        // Hold server progress as a floor so a late animation restart can't erase a tap
                        displayProgress = maxOf(state.progress, next).coerceIn(0.0, state.unitsPerSat.toDouble())
                        if (next >= state.unitsPerSat) break
                    }
                }

                Column(
                    Modifier
                        .fillMaxSize()
                        .padding(horizontal = 24.dp, vertical = 16.dp),
                ) {
                    Row(
                        Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text("AdPlay", fontSize = 28.sp, fontWeight = FontWeight.Bold, color = BrandInk)
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
                            if (ui.tunables?.debugReset != false) {
                                TextButton(onClick = onDebugReset) {
                                    Text("Reset", color = BrandMuted, fontWeight = FontWeight.SemiBold)
                                }
                            }
                            Box(
                                Modifier
                                    .clip(RoundedCornerShape(50))
                                    .background(BrandAccent.copy(alpha = 0.14f))
                                    .border(1.dp, BrandAccent.copy(alpha = 0.55f), RoundedCornerShape(50))
                                    .clickable(onClick = onRedeem)
                                    .padding(horizontal = 14.dp, vertical = 7.dp),
                            ) {
                                Text("Redeem", color = BrandAccent, fontWeight = FontWeight.Bold, fontSize = 14.sp)
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

                    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                        Text(
                            formatBtcAmount(
                                satsBalance = state.satsBalance,
                                barProgress = displayProgress,
                                unitsPerSat = state.unitsPerSat,
                            ),
                            fontSize = 42.sp,
                            fontWeight = FontWeight.Black,
                            color = BrandInk,
                            maxLines = 1,
                            style = TextStyle(
                                shadow = Shadow(
                                    color = BrandAccent.copy(alpha = 0.5f),
                                    offset = Offset(0f, 6f),
                                    blurRadius = 34f,
                                ),
                            ),
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

                    Spacer(Modifier.weight(0.6f))

                    ProgressBar(
                        displayProgress = displayProgress,
                        total = state.unitsPerSat,
                        autoActive = state.autoFillActive,
                        fillRate = state.fillRate,
                        tapPower = state.tapPower,
                        onTap = onTap,
                    )

                    Spacer(Modifier.height(14.dp))
                    Text(
                        if (state.tapsRemaining > 0) {
                            "Tap the bar · ${state.tapsRemaining} taps left today"
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
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(88.dp),
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        BoostButton(
                            title = "Longer",
                            actionLabel = formatLongerAction(t),
                            theme = BrandTime,
                            running = state.autoFillActive,
                            enabled = canWatch,
                            onClick = onLonger,
                            modifier = Modifier.weight(1f).fillMaxHeight(),
                        )
                        BoostButton(
                            title = "Faster",
                            actionLabel = formatFasterAction(t),
                            theme = BrandSpeed,
                            running = state.autoFillActive && state.fillRate > 0,
                            enabled = canWatch,
                            onClick = onFaster,
                            modifier = Modifier.weight(1f).fillMaxHeight(),
                        )
                        BoostButton(
                            title = "Stronger",
                            actionLabel = formatStrongerAction(t),
                            theme = BrandPower,
                            running = state.tapStrengthActive,
                            enabled = canWatch,
                            onClick = onStronger,
                            modifier = Modifier.weight(1f).fillMaxHeight(),
                        )
                    }

                    Spacer(Modifier.height(10.dp))
                    SharedAutoTimer(
                        autoFillUntil = state.autoFillUntil,
                        autoActive = state.autoFillActive,
                    )

                    Spacer(Modifier.height(10.dp))

                    ui.error?.let {
                        Text(it, color = Color(0xFFFF6B6B), fontSize = 13.sp, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
                        Spacer(Modifier.height(8.dp))
                    }

                    AdsFooter(
                        adsRemaining = state.adsRemainingToday,
                        cooldownLeft = state.adCooldownSecondsLeft,
                        autoFillUntil = state.autoFillUntil,
                        autoActive = state.autoFillActive,
                    )

                    // Reserved height so layout never jumps when Skip appears.
                    Spacer(Modifier.height(8.dp))
                    val skipVisible = state.adsRemainingToday <= 0 &&
                        state.autoFillActive &&
                        (state.skipAdsRemaining < 0 || state.skipAdsRemaining > 0)
                    val canSkip = !ui.loading &&
                        skipVisible &&
                        state.adCooldownSecondsLeft == 0
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
        fontSize = 14.sp,
        fontWeight = FontWeight.SemiBold,
        textAlign = TextAlign.Center,
        modifier = Modifier.fillMaxWidth(),
    )
}

@Composable
private fun AdsFooter(
    adsRemaining: Int,
    cooldownLeft: Int,
    autoFillUntil: String?,
    autoActive: Boolean,
) {
    var nowMs by remember { mutableLongStateOf(System.currentTimeMillis()) }
    val refillUntil = autoFillUntil.takeIf { autoActive && adsRemaining <= 0 }
    val needTick = adsRemaining <= 0 && refillUntil != null
    LaunchedEffect(needTick, refillUntil) {
        if (!needTick) return@LaunchedEffect
        while (true) {
            nowMs = System.currentTimeMillis()
            if (remainingSeconds(refillUntil, nowMs) <= 0L) break
            delay(250)
        }
    }

    val footer = when {
        adsRemaining <= 0 -> {
            if (autoActive) {
                "Ads refill when auto ends"
            } else {
                "More ads soon…"
            }
        }
        cooldownLeft > 0 -> "Next ad in ${cooldownLeft}s · $adsRemaining ads left"
        else -> "$adsRemaining ads left this run"
    }

    Text(
        footer,
        color = BrandMuted,
        fontSize = 12.sp,
        textAlign = TextAlign.Center,
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 8.dp),
    )
}

/** BTC for completed sats plus the in-progress fraction of the current bar (1 full bar = 1 sat). */
internal fun formatBtcAmount(satsBalance: Int, barProgress: Double, unitsPerSat: Int): String {
    val fraction = if (unitsPerSat > 0) {
        (barProgress / unitsPerSat).coerceIn(0.0, 1.0)
    } else {
        0.0
    }
    val btc = (satsBalance + fraction) * 1e-8
    // 11 dp: 1 sat = 1e-8 BTC; with ~1000 units/sat each unit is visible as 1e-11.
    return String.format("%.11f", btc)
}

/** Status above the bar: taps/s · power · fill/s — colored by Speed / Power. */
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

internal fun formatSkipButtonStatus(skipAdsRemaining: Int, cooldownLeft: Int): String {
    if (cooldownLeft > 0) return "Next in ${cooldownLeft}s"
    return formatSkipRemaining(skipAdsRemaining)
}

/** Raw auto tap rate (excludes Stronger). fillRate from server is total units/s. */
internal fun tapsPerSecond(fillRate: Double, tapPower: Double): Double {
    val power = if (tapPower > 0.0) tapPower else 1.0
    return fillRate / power
}

@Composable
private fun ProgressBar(
    displayProgress: Double,
    total: Int,
    autoActive: Boolean,
    fillRate: Double,
    tapPower: Double,
    onTap: () -> Unit,
) {
    val fraction by animateFloatAsState(
        targetValue = if (total > 0) (displayProgress / total).toFloat().coerceIn(0f, 1f) else 0f,
        label = "bar",
    )
    Column(Modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(
                "${floor(displayProgress).toInt()} / $total taps",
                fontWeight = FontWeight.SemiBold,
                color = BrandInk,
                fontSize = 15.sp,
            )
            BarRateStatus(autoActive = autoActive, fillRate = fillRate, tapPower = tapPower)
        }
        Spacer(Modifier.height(10.dp))
        Box(
            Modifier
                .fillMaxWidth()
                .height(30.dp)
                .clip(RoundedCornerShape(50))
                .background(BrandInk.copy(alpha = 0.06f))
                .border(1.dp, BrandInk.copy(alpha = 0.10f), RoundedCornerShape(50))
                .clickable(onClick = onTap),
        ) {
            Box(
                Modifier
                    .fillMaxWidth(fraction.coerceAtLeast(0.04f))
                    .height(30.dp)
                    .clip(RoundedCornerShape(50))
                    .background(Brush.horizontalGradient(listOf(BrandFill, BrandFillHot)))
                    .border(1.dp, BrandFillHot.copy(alpha = 0.5f), RoundedCornerShape(50)),
            )
        }
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
            .padding(horizontal = 4.dp, vertical = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            title,
            fontSize = 17.sp,
            fontWeight = FontWeight.Bold,
            color = titleColor,
            maxLines = 1,
        )
        Text(
            actionLabel,
            fontSize = 11.sp,
            color = detailColor,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center,
            maxLines = 1,
        )
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
