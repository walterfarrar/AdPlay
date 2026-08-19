package com.adplay.app.ui

import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
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
            Panel("Your hold") {
                Text(
                    "${ui.state.adsRemainingToday} / ${p.adBank.max}",
                    color = BrandInk,
                    fontSize = 32.sp,
                    fontWeight = FontWeight.Bold,
                )
                Text(
                    "Boost ads you can hold right now. Extra slots raise the max permanently.",
                    color = BrandMuted,
                    fontSize = 13.sp,
                )
            }
            Spacer(Modifier.height(16.dp))
            Panel("Extra ad slots") {
                Text(
                    "Buy +1 permanent hold, one at a time. ${p.iapAdsPurchased} / ${p.iapBonusAdsMax} purchased. Purchases and Restore purchases are available on iOS.",
                    color = BrandMuted,
                    fontSize = 13.sp,
                )
            }
    }
}
