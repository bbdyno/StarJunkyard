package com.bbdyno.starjunkyard.combat

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.viewinterop.AndroidView

@Composable
fun PixelCombatRoute(modifier: Modifier = Modifier) {
    AndroidView(
        factory = { context -> PixelCombatSurfaceView(context) },
        modifier = modifier
            .fillMaxSize()
            .semantics {
                contentDescription = "별을 줍는 고물상 자동 전투. 오버클럭 사용 가능."
            },
    )
}
