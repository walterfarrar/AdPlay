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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.adplay.app.UiState
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
    onRedeem: () -> Unit,
    onDebugReset: () -> Unit,
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
                .size(280.dp)
                .align(Alignment.TopStart)
                .padding(start = 0.dp, top = 0.dp)
                .clip(CircleShape)
                .background(BrandAccent.copy(alpha = 0.12f)),
        )
        Box(
            Modifier
                .size(320.dp)
                .align(Alignment.BottomEnd)
                .clip(CircleShape)
                .background(Color(0xFF739E8C).copy(alpha = 0.14f)),
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
                    Text(ui.error ?: "Not connected", color = Color(0xFFB00020), textAlign = TextAlign.Center)
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
                            if (ui.tunables?.debugReset != false) {
                                TextButton(onClick = onDebugReset) {
                                    Text("Reset", color = BrandMuted, fontWeight = FontWeight.SemiBold)
                                }
                            }
                            TextButton(onClick = onRedeem) {
                                Text("Redeem", color = BrandAccent, fontWeight = FontWeight.SemiBold)
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
                            "${state.satsBalance}",
                            fontSize = 64.sp,
                            fontWeight = FontWeight.Bold,
                            color = BrandInk,
                        )
                        Text("sats", fontSize = 18.sp, fontWeight = FontWeight.Medium, color = BrandMuted)
                    }

                    Spacer(Modifier.weight(0.6f))

                    ProgressBar(
                        progress = state.progress,
                        total = state.unitsPerSat,
                        autoActive = state.autoFillActive,
                        fillRate = state.fillRate,
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

                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(96.dp),
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        BoostButton(
                            title = "Longer",
                            idleSubtitle = "Extend auto",
                            activeUntil = state.autoFillUntil.takeIf { state.autoFillActive },
                            enabled = canWatch,
                            onClick = onLonger,
                            modifier = Modifier.weight(1f).fillMaxHeight(),
                        )
                        BoostButton(
                            title = "Faster",
                            idleSubtitle = "Raise speed",
                            // Same shared auto timer as Longer
                            activeUntil = state.autoFillUntil.takeIf { state.autoFillActive },
                            activeMetric = if (state.autoFillActive && state.fillRate > 0) {
                                String.format("%.2f/s", state.fillRate)
                            } else {
                                null
                            },
                            enabled = canWatch,
                            onClick = onFaster,
                            modifier = Modifier.weight(1f).fillMaxHeight(),
                        )
                        BoostButton(
                            title = "Stronger",
                            idleSubtitle = "Boost tap power",
                            activeUntil = state.tapStrengthUntil.takeIf { state.tapStrengthActive },
                            activeMetric = if (state.tapStrengthActive) "${state.tapPower}/tap" else null,
                            enabled = canWatch,
                            onClick = onStronger,
                            modifier = Modifier.weight(1f).fillMaxHeight(),
                        )
                    }

                    Spacer(Modifier.height(16.dp))

                    ui.error?.let {
                        Text(it, color = Color(0xFFB00020), fontSize = 13.sp, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
                        Spacer(Modifier.height(8.dp))
                    }

                    AdsFooter(
                        adsRemaining = state.adsRemainingToday,
                        cooldownLeft = state.adCooldownSecondsLeft,
                        autoFillUntil = state.autoFillUntil,
                        autoActive = state.autoFillActive,
                        tapStrengthUntil = state.tapStrengthUntil,
                        tapStrengthActive = state.tapStrengthActive,
                    )
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
private fun AdsFooter(
    adsRemaining: Int,
    cooldownLeft: Int,
    autoFillUntil: String?,
    autoActive: Boolean,
    tapStrengthUntil: String?,
    tapStrengthActive: Boolean,
) {
    var nowMs by remember { mutableLongStateOf(System.currentTimeMillis()) }
    val refillUntil = listOfNotNull(
        autoFillUntil.takeIf { autoActive },
        tapStrengthUntil.takeIf { tapStrengthActive },
    ).maxByOrNull { remainingSeconds(it, nowMs) }
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
            val left = remainingSeconds(refillUntil, nowMs)
            if (left > 0L) {
                "More ads in ${formatCountdown(left)}"
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

@Composable
private fun ProgressBar(
    progress: Double,
    total: Int,
    autoActive: Boolean,
    fillRate: Double,
    onTap: () -> Unit,
) {
    var displayProgress by remember { mutableDoubleStateOf(progress) }

    // Smooth local fill between server polls — never snap backward except on bar wrap/reset.
    LaunchedEffect(progress, fillRate, autoActive, total) {
        if (progress + 5.0 < displayProgress) {
            // Bar completed (progress wrapped) or debug reset
            displayProgress = progress
        } else if (progress > displayProgress) {
            displayProgress = progress
        }
        if (!autoActive || fillRate <= 0.0 || total <= 0) return@LaunchedEffect
        val start = displayProgress
        val startMs = System.currentTimeMillis()
        while (true) {
            delay(50)
            val elapsed = (System.currentTimeMillis() - startMs) / 1000.0
            val next = start + fillRate * elapsed
            // Hold server progress as a floor so a late animation restart can't erase a tap
            displayProgress = maxOf(progress, next).coerceIn(0.0, total.toDouble())
            if (next >= total) break
        }
    }

    val fraction by animateFloatAsState(
        targetValue = if (total > 0) (displayProgress / total).toFloat().coerceIn(0f, 1f) else 0f,
        label = "bar",
    )
    val status = if (!autoActive) {
        "Idle"
    } else {
        String.format("%.2f taps/s", fillRate)
    }
    Column(Modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(
                "${floor(displayProgress).toInt()} / $total taps",
                fontWeight = FontWeight.SemiBold,
                color = BrandInk,
                fontSize = 15.sp,
            )
            Text(
                status,
                color = if (autoActive) BrandAccent else BrandMuted,
                fontWeight = FontWeight.SemiBold,
                fontSize = 13.sp,
            )
        }
        Spacer(Modifier.height(10.dp))
        Box(
            Modifier
                .fillMaxWidth()
                .height(28.dp)
                .clip(RoundedCornerShape(50))
                .background(BrandInk.copy(alpha = 0.08f))
                .clickable(onClick = onTap),
        ) {
            Box(
                Modifier
                    .fillMaxWidth(fraction.coerceAtLeast(0.04f))
                    .height(28.dp)
                    .clip(RoundedCornerShape(50))
                    .background(Brush.horizontalGradient(listOf(BrandAccent, BrandAccentHot))),
            )
        }
    }
}

@Composable
private fun BoostButton(
    title: String,
    idleSubtitle: String,
    enabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    activeUntil: String? = null,
    activeMetric: String? = null,
) {
    var nowMs by remember { mutableLongStateOf(System.currentTimeMillis()) }
    val left = remainingSeconds(activeUntil, nowMs)
    val active = left > 0L
    val visual = when {
        active && enabled -> BoostVisual.RunningReady
        active && !enabled -> BoostVisual.RunningLocked
        enabled -> BoostVisual.Ready
        else -> BoostVisual.Locked
    }

    LaunchedEffect(activeUntil) {
        if (activeUntil.isNullOrBlank()) return@LaunchedEffect
        while (true) {
            nowMs = System.currentTimeMillis()
            if (remainingSeconds(activeUntil, nowMs) <= 0L) break
            delay(250)
        }
    }

    val line2 = if (active) formatCountdown(left) else idleSubtitle
    val line3 = if (active) activeMetric.orEmpty() else ""
    val shape = RoundedCornerShape(16.dp)

    val titleColor = when (visual) {
        BoostVisual.Ready, BoostVisual.RunningReady -> BrandInk
        BoostVisual.RunningLocked -> BrandInk.copy(alpha = 0.55f)
        BoostVisual.Locked -> BrandMuted.copy(alpha = 0.55f)
    }
    val detailColor = when (visual) {
        BoostVisual.Ready -> BrandMuted
        BoostVisual.RunningReady -> Color(0xFF7A3A12)
        BoostVisual.RunningLocked -> BrandMuted.copy(alpha = 0.75f)
        BoostVisual.Locked -> BrandMuted.copy(alpha = 0.45f)
    }
    val bg = when (visual) {
        BoostVisual.Ready -> Brush.verticalGradient(
            listOf(Color.White.copy(alpha = 0.92f), BrandAccent.copy(alpha = 0.12f)),
        )
        BoostVisual.RunningReady -> Brush.verticalGradient(
            listOf(BrandAccent.copy(alpha = 0.58f), BrandAccentHot.copy(alpha = 0.48f)),
        )
        // Same timer content, but washed out — clearly not pressable
        BoostVisual.RunningLocked -> Brush.verticalGradient(
            listOf(BrandInk.copy(alpha = 0.05f), BrandInk.copy(alpha = 0.08f)),
        )
        BoostVisual.Locked -> Brush.verticalGradient(
            listOf(BrandInk.copy(alpha = 0.03f), BrandInk.copy(alpha = 0.05f)),
        )
    }
    val borderColor = when (visual) {
        BoostVisual.Ready -> BrandAccent.copy(alpha = 0.85f)
        BoostVisual.RunningReady -> BrandAccentHot
        BoostVisual.RunningLocked -> BrandMuted.copy(alpha = 0.35f)
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
            line2,
            fontSize = 11.sp,
            color = detailColor,
            fontWeight = if (visual == BoostVisual.RunningReady || visual == BoostVisual.RunningLocked) {
                FontWeight.Bold
            } else {
                FontWeight.Medium
            },
            textAlign = TextAlign.Center,
            maxLines = 1,
        )
        Text(
            line3.ifEmpty { " " },
            fontSize = 11.sp,
            color = if (line3.isEmpty()) Color.Transparent else detailColor,
            fontWeight = FontWeight.SemiBold,
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
