package com.adplay.app.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

val BrandInk = Color(0xFF1A1A25)
val BrandMuted = Color(0xFF595F66)
val BrandAccent = Color(0xFFF7931A)
val BrandAccentHot = Color(0xFFEB6B2E)
val BrandBgTop = Color(0xFFFAF5EB)
val BrandBgMid = Color(0xFFEDF2F8)
val BrandBgBottom = Color(0xFFE6EDE6)

private val colors = lightColorScheme(
    primary = BrandAccent,
    onPrimary = BrandInk,
    background = BrandBgTop,
    onBackground = BrandInk,
    surface = Color.White.copy(alpha = 0.55f),
    onSurface = BrandInk,
)

@Composable
fun AdPlayTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = colors, content = content)
}
