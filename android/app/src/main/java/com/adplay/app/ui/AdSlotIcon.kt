package com.adplay.app.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** Gold coin stamped with a play mark — one Ad Token (spend to watch a Boost Ad). */
@Composable
fun AdSlotIcon(modifier: Modifier = Modifier, size: Dp = 28.dp) {
    Canvas(modifier.size(size)) {
        val s = this.size.minDimension
        val c = Offset(this.size.width / 2f, this.size.height / 2f)
        val r = s / 2f
        drawCircle(
            brush = Brush.linearGradient(
                colors = listOf(BrandAccentHot, BrandAccent, Color(0xFFB86A14)),
                start = Offset(c.x, 0f),
                end = Offset(c.x, s),
            ),
            radius = r,
            center = c,
        )
        drawCircle(
            color = Color(0xFF733D0A),
            radius = r,
            center = c,
            style = Stroke(width = s * 0.07f),
        )
        drawCircle(
            color = Color.White.copy(alpha = 0.38f),
            radius = r * 0.70f,
            center = c,
            style = Stroke(width = s * 0.055f),
        )
        val play = Path().apply {
            moveTo(s * 0.38f, s * 0.32f)
            lineTo(s * 0.38f, s * 0.68f)
            lineTo(s * 0.70f, s * 0.50f)
            close()
        }
        drawPath(play, Color.White.copy(alpha = 0.94f))
    }
}
