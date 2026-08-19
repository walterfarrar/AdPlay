package com.adplay.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.adplay.app.UiState
import com.adplay.app.data.DailyGoal
import com.adplay.app.data.ProgressCatalog
import com.adplay.app.data.StreakMilestone

@Composable
fun ActivityScreen(ui: UiState, onRefresh: () -> Unit) {
    val p = ui.progress
    val bank = p.adBank
    LaunchedEffect(Unit) { onRefresh() }

    CenteredFitPage {
            Text("Daily Goals", color = BrandInk, fontSize = 28.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(16.dp))
            Panel("Login streak") {
                Row(verticalAlignment = Alignment.Bottom) {
                    Text("${p.loginStreak}", color = BrandAccent, fontSize = 36.sp, fontWeight = FontWeight.Bold)
                    Text(if (p.loginStreak == 1) "  day" else "  days", color = BrandMuted)
                    Spacer(Modifier.weight(1f))
                    Text("Best ${p.bestLoginStreak}", color = BrandInk, fontWeight = FontWeight.SemiBold)
                }
                Spacer(Modifier.height(10.dp))
                StreakTimeline(days = p.loginStreak)
                Spacer(Modifier.height(8.dp))
                Row(
                    verticalAlignment = Alignment.Top,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    AdSlotIcon(size = 18.dp)
                    Text(
                        "Check in once each UTC day. Extra Ad Tokens unlock at days 1, 3, 5, 7, and 30. Miss a day and those tokens reset. Now +${bank.streakBonus}.",
                        color = BrandMuted,
                        fontSize = 13.sp,
                    )
                }
            }
            Spacer(Modifier.height(16.dp))
            Panel("Daily goals") {
                Row(
                    verticalAlignment = Alignment.Top,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    AdSlotIcon(size = 18.dp)
                    Text(
                        "Each completed goal adds +1 Ad Token today. Resets with the UTC day. Now +${bank.dailyBonus}.",
                        color = BrandMuted,
                        fontSize = 13.sp,
                    )
                }
                p.displayedDailyGoals.forEach { GoalRow(it) }
            }
    }
}

@Composable
private fun StreakTimeline(days: Int) {
    val marks = ProgressCatalog.streakMilestones
    val fill = ProgressCatalog.streakTrackFill(days)
    val nodeSlot = 22.dp
    BoxWithConstraints(Modifier.fillMaxWidth().height(48.dp)) {
        val inset = 12.dp
        val rail = (maxWidth - inset * 2).coerceAtLeast(1.dp)
        val railTop = (nodeSlot - 4.dp) / 2
        Box(
            Modifier
                .offset(x = inset, y = railTop)
                .width(rail)
                .height(4.dp)
                .clip(RoundedCornerShape(2.dp))
                .background(BrandCardBorder),
        )
        Box(
            Modifier
                .offset(x = inset, y = railTop)
                .width(rail * fill.coerceIn(0f, 1f))
                .height(4.dp)
                .clip(RoundedCornerShape(2.dp))
                .background(BrandAccent),
        )
        marks.forEach { mark ->
            val reached = days >= mark.day
            val x = inset + rail * ProgressCatalog.streakRailX(mark.day)
            Box(
                Modifier
                    .offset(x = x - nodeSlot / 2, y = 0.dp)
                    .size(nodeSlot),
                contentAlignment = Alignment.Center,
            ) {
                if (mark.grantsToken) {
                    AdSlotIcon(
                        size = if (mark.isLongRun) 22.dp else 18.dp,
                        modifier = Modifier.alpha(if (reached) 1f else 0.38f),
                    )
                } else {
                    Box(
                        Modifier
                            .size(14.dp)
                            .clip(CircleShape)
                            .background(BrandCard)
                            .border(1.5.dp, if (reached) BrandAccent else BrandCardBorder, CircleShape),
                        contentAlignment = Alignment.Center,
                    ) {
                        if (reached) {
                            Box(
                                Modifier
                                    .size(8.dp)
                                    .clip(CircleShape)
                                    .background(BrandAccent),
                            )
                        }
                    }
                }
            }
            Text(
                "${mark.day}",
                color = if (reached) BrandInk else BrandMuted,
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .offset(x = x - 18.dp, y = nodeSlot + 6.dp)
                    .width(36.dp),
            )
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
            if (goal.completed) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    AdSlotIcon(size = 14.dp)
                    Text(
                        "Done · +1 token",
                        color = BrandFill,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            } else {
                Text(
                    "${goal.current.coerceAtMost(goal.target)} / ${goal.target}",
                    color = BrandMuted,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                )
            }
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
