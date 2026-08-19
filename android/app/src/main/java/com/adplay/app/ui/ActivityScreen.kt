package com.adplay.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.adplay.app.UiState
import com.adplay.app.data.DailyGoal
import com.adplay.app.data.ProgressCatalog

@Composable
fun ActivityScreen(ui: UiState, onRefresh: () -> Unit) {
    val p = ui.progress
    val bank = p.adBank
    LaunchedEffect(Unit) { onRefresh() }

    Column(
        Modifier
            .fillMaxSize()
            .background(Brush.linearGradient(listOf(BrandBgTop, BrandBgMid, BrandBgBottom)))
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Column(Modifier.widthIn(max = 560.dp).fillMaxWidth()) {
            Text("Daily Goals", color = BrandInk, fontSize = 28.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(16.dp))
            Panel("Login streak") {
                Row(verticalAlignment = Alignment.Bottom) {
                    Text("${p.loginStreak}", color = BrandAccent, fontSize = 36.sp, fontWeight = FontWeight.Bold)
                    Text("  days", color = BrandMuted)
                    Spacer(Modifier.weight(1f))
                    Text("Best ${p.bestLoginStreak}", color = BrandInk, fontWeight = FontWeight.SemiBold)
                }
                Text(
                    "Open AdPlay once each UTC day. +1 ad hold per day while the streak is alive, up to 5. Miss a day and this bonus drops to 0. Now +${bank.streakBonus}.",
                    color = BrandMuted,
                    fontSize = 13.sp,
                )
            }
            Spacer(Modifier.height(16.dp))
            Panel("Daily goals") {
                Text(
                    "Each completed goal adds +1 ad hold today. Resets with the UTC day. Now +${bank.dailyBonus}.",
                    color = BrandMuted,
                    fontSize = 13.sp,
                )
                p.displayedDailyGoals.forEach { GoalRow(it) }
            }
        }
    }
}

@Composable
private fun GoalRow(goal: DailyGoal) {
    Column(Modifier.padding(top = 10.dp)) {
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f)) {
                Text(goal.title, color = BrandInk)
                Text(ProgressCatalog.howTo(goal), color = BrandMuted, fontSize = 12.sp)
            }
            Text(
                if (goal.completed) "Done · +1" else "${goal.current.coerceAtMost(goal.target)} / ${goal.target}",
                color = if (goal.completed) BrandFill else BrandMuted,
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
            )
        }
        Spacer(Modifier.height(6.dp))
        LinearProgressIndicator(
            progress = { (goal.current.toFloat() / goal.target.coerceAtLeast(1)).coerceIn(0f, 1f) },
            modifier = Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(4.dp)),
            color = if (goal.completed) BrandFill else BrandAccent,
            trackColor = BrandCardBorder,
        )
    }
}

@Composable
fun Panel(title: String, content: @Composable () -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(BrandCard)
            .border(1.dp, BrandCardBorder, RoundedCornerShape(16.dp))
            .padding(16.dp),
    ) {
        Text(title, color = BrandInk, fontWeight = FontWeight.Bold, fontSize = 18.sp)
        Spacer(Modifier.height(8.dp))
        content()
    }
}
