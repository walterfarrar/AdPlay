package com.adplay.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch

private data class OnboardPage(val title: String, val body: String)

@Composable
fun OnboardingScreen(onFinished: () -> Unit) {
    val pages = listOf(
        OnboardPage(
            "Tap the wheel",
            "Each tap fills the progress wheel. Fill it completely to earn 1 sat — a tiny unit of Bitcoin.",
        ),
        OnboardPage(
            "Ad Tokens",
            "Spend one Ad Token to watch a Boost Ad. Daily goals, login streaks, achievements, and extras raise how many tokens you can keep.",
        ),
        OnboardPage(
            "Watch ads to boost",
            "Activate Auto Tapper, then watch Longer, Faster, or Stronger to speed up earning. Ads are optional.",
        ),
        OnboardPage(
            "Redeem over Lightning",
            "When you have enough sats, paste a Lightning invoice on Redeem.",
        ),
    )
    val pager = rememberPagerState { pages.size }
    val scope = rememberCoroutineScope()

    Box(
        Modifier
            .fillMaxSize()
            .background(Brush.linearGradient(listOf(BrandBgTop, BrandBgMid, BrandBgBottom))),
    ) {
        Column(
            Modifier
                .align(Alignment.Center)
                .widthIn(max = 560.dp)
                .fillMaxWidth()
                .fillMaxSize()
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            HorizontalPager(pager, Modifier.weight(1f)) { i ->
                Column(
                    Modifier.fillMaxSize(),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    if (pages[i].title == "Ad Tokens") {
                        AdSlotIcon(size = 56.dp)
                        Spacer(Modifier.height(18.dp))
                    }
                    Text(
                        pages[i].title,
                        color = BrandInk,
                        fontSize = 28.sp,
                        fontWeight = FontWeight.Bold,
                        textAlign = TextAlign.Center,
                    )
                    Spacer(Modifier.height(16.dp))
                    Text(
                        pages[i].body,
                        color = BrandMuted,
                        fontSize = 16.sp,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.widthIn(max = 420.dp),
                    )
                }
            }
            Button(
                onClick = {
                    if (pager.currentPage < pages.lastIndex) {
                        scope.launch { pager.animateScrollToPage(pager.currentPage + 1) }
                    } else {
                        onFinished()
                    }
                },
                colors = ButtonDefaults.buttonColors(containerColor = BrandAccent, contentColor = BrandOnAccent),
                shape = RoundedCornerShape(50),
                modifier = Modifier
                    .widthIn(max = 360.dp)
                    .fillMaxWidth()
                    .height(52.dp),
            ) {
                Text(
                    if (pager.currentPage < pages.lastIndex) "Next" else "Start playing",
                    fontWeight = FontWeight.Bold,
                )
            }
        }
    }
}
