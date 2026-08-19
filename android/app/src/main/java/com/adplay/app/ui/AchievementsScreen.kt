package com.adplay.app.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.adplay.app.UiState
import com.adplay.app.data.Achievement

@Composable
fun AchievementsScreen(ui: UiState, onClose: () -> Unit) {
    CenteredFitPage(Modifier.statusBarsPadding().navigationBarsPadding()) {
            Row(
                Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "Achievements",
                    color = BrandInk,
                    fontSize = 28.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.weight(1f),
                )
                TextButton(onClick = onClose) {
                    Text("Close", color = BrandMuted, fontWeight = FontWeight.SemiBold)
                }
            }
            Spacer(Modifier.height(8.dp))
            Text(
                "Unlock these by playing. Slot achievements raise how many boost ads you can hold.",
                color = BrandMuted,
                fontSize = 13.sp,
            )
            Spacer(Modifier.height(8.dp))
            ui.progress.displayedAchievements.forEach { AchievementRow(it) }
    }
}

@Composable
internal fun AchievementRow(a: Achievement) {
    Row(Modifier.padding(top = 10.dp), verticalAlignment = Alignment.Top) {
        Text(if (a.unlocked) "✓" else "🔒", color = if (a.unlocked) BrandFill else BrandMuted)
        Column(Modifier.weight(1f).padding(start = 10.dp)) {
            Text(a.title, color = BrandInk, fontWeight = FontWeight.SemiBold)
            Text(a.detail, color = BrandMuted, fontSize = 12.sp)
        }
        if (a.grantsSlot) {
            Text(
                if (a.unlocked) "+1 hold" else "+1",
                color = if (a.unlocked) BrandAccent else BrandMuted,
                fontSize = 12.sp,
            )
        }
    }
}
