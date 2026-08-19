package com.adplay.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.adplay.app.UiState

@Composable
fun StoreScreen(ui: UiState) {
    val p = ui.progress
    Column(
        Modifier
            .fillMaxSize()
            .background(Brush.linearGradient(listOf(BrandBgTop, BrandBgMid, BrandBgBottom)))
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Column(Modifier.widthIn(max = 560.dp).fillMaxWidth()) {
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
}
