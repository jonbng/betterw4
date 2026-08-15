package dk.betterlectio.android.ui.theme

import androidx.compose.ui.unit.dp

/**
 * Flat, system-native spacing / radius scale.
 * Prefer structure from type & layout over elevated cards.
 */
object Dimens {
    val screenHorizontal = 16.dp
    val screenVertical = 8.dp

    val rowMinHeight = 64.dp
    val rowHorizontal = 16.dp
    val rowVertical = 12.dp

    val sectionTop = 20.dp
    val sectionBottom = 6.dp

    val accentBarWidth = 3.dp
    val accentBarHeight = 36.dp

    /** Only for controls that need rounding (chips, FABs, sheets). Not list rows. */
    val radiusControl = 8.dp
    val radiusPill = 999.dp

    val dividerIndent = 16.dp
}
