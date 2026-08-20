package com.adplay.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.adplay.app.UiState

@Composable
fun StoreScreen(ui: UiState) {
    val p = ui.progress
    CenteredFitPage {
            Text("Store", color = BrandInk, fontSize = 28.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(16.dp))
            Panel("Ad Tokens") {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    AdSlotIcon(size = 36.dp)
                    Text(
                        "${ui.state.adsRemainingToday} / ${p.adBank.max}",
                        color = BrandInk,
                        fontSize = 32.sp,
                        fontWeight = FontWeight.Bold,
                    )
                }
                Text(
                    "Spend one token to watch a Boost Ad. Goals, streaks, achievements, and extras raise how many you can keep.",
                    color = BrandMuted,
                    fontSize = 13.sp,
                )
            }
            Spacer(Modifier.height(16.dp))
            Panel("Extra tokens") {
                Text(
                    "Buy +1 permanent Ad Token, one at a time.",
                    color = BrandMuted,
                    fontSize = 13.sp,
                )
                Text(
                    "${p.iapAdsPurchased} / ${p.iapBonusAdsMax} purchased.",
                    color = BrandMuted,
                    fontSize = 13.sp,
                )
                Text(
                    "Purchases and Restore purchases are available on iOS.",
                    color = BrandMuted,
                    fontSize = 13.sp,
                )
            }
    }
}
