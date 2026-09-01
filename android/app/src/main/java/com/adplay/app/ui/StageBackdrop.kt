package com.adplay.app.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import com.adplay.app.R
import com.adplay.app.data.MinerStage
import com.adplay.app.data.Tunables

fun MinerStage.backdropRes(): Int = when (this) {
    MinerStage.Level1 -> R.drawable.stage_level_1
    MinerStage.Level2 -> R.drawable.stage_level_2
    MinerStage.Level3 -> R.drawable.stage_level_3
    MinerStage.Level4 -> R.drawable.stage_level_4
    MinerStage.Level5 -> R.drawable.stage_level_5
    MinerStage.Level6 -> R.drawable.stage_level_6
    MinerStage.Level7 -> R.drawable.stage_level_7
    MinerStage.Level8 -> R.drawable.stage_level_8
    MinerStage.Level9 -> R.drawable.stage_level_9
    MinerStage.Level10 -> R.drawable.stage_level_10
}

fun MinerStage.wheelFaceRes(): Int = when (this) {
    MinerStage.Level1 -> R.drawable.wheel_face_1
    MinerStage.Level2 -> R.drawable.wheel_face_2
    MinerStage.Level3 -> R.drawable.wheel_face_3
    MinerStage.Level4 -> R.drawable.wheel_face_4
    MinerStage.Level5 -> R.drawable.wheel_face_5
    MinerStage.Level6 -> R.drawable.wheel_face_6
    MinerStage.Level7 -> R.drawable.wheel_face_7
    MinerStage.Level8 -> R.drawable.wheel_face_8
    MinerStage.Level9 -> R.drawable.wheel_face_9
    MinerStage.Level10 -> R.drawable.wheel_face_10
}

@Composable
fun StageBackdrop(lifetimeSats: Int, tunables: Tunables? = null, modifier: Modifier = Modifier) {
    val stage = MinerStage.from(lifetimeSats, tunables)
    Box(modifier.fillMaxSize()) {
        Image(
            painter = painterResource(stage.backdropRes()),
            contentDescription = null,
            modifier = Modifier.fillMaxSize(),
            contentScale = ContentScale.Crop,
        )
        Box(
            Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = 0.52f)),
        )
    }
}
