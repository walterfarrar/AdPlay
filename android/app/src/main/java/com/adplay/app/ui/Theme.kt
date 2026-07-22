package com.adplay.app.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// Dark, premium palette — near-white ink, warm Bitcoin-orange accents.
val BrandInk = Color(0xFFF4F5FA)
val BrandMuted = Color(0xFF969CB0)
val BrandAccent = Color(0xFFF7931A)
val BrandAccentHot = Color(0xFFFF6B2C)
val BrandBgTop = Color(0xFF12131F)
val BrandBgMid = Color(0xFF0E0F1A)
val BrandBgBottom = Color(0xFF0A0B12)

// Elevated surfaces / glass cards on the dark backdrop.
val BrandCard = Color(0xFF171826)
val BrandCardBorder = Color(0xFF2B2D3D)
val BrandOnAccent = Color(0xFF0B0C14)

private val colors = darkColorScheme(
    primary = BrandAccent,
    onPrimary = BrandOnAccent,
    background = BrandBgMid,
    onBackground = BrandInk,
    surface = BrandCard,
    onSurface = BrandInk,
)

@Composable
fun AdPlayTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = colors, content = content)
}
