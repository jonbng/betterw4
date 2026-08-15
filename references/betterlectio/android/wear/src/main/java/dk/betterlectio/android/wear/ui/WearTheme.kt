package dk.betterlectio.android.wear.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.wear.compose.material3.MaterialTheme

object BetterLectioWearColors {
    val Brand = Color(0xFF6F93FF)
    val BrandDim = Color(0xFF243A78)
    val Surface = Color(0xFF101114)
    val SurfaceRaised = Color(0xFF1A1C21)
    val TextMuted = Color(0xFFB4B8C4)
    val Cancelled = Color(0xFFFF8A80)
    val Changed = Color(0xFFFFCA66)
}

@Composable
fun BetterLectioWearTheme(content: @Composable () -> Unit) {
    MaterialTheme(content = content)
}
