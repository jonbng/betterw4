package dk.betterw4.android.ui.theme

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.toArgb
import dk.betterw4.android.feature.settings.SubjectColorResolver

// Brand seed from BetterW4 (Flutter splash / product blue)
val BrandBlue = Color(0xFF3362E1)
val BrandBlueDark = Color(0xFF8AB4FF)
val BrandBlueContainer = Color(0xFFD8E2FF)
val BrandBlueContainerDark = Color(0xFF1A3A8F)

val Neutral10 = Color(0xFF1A1C1E)
val Neutral90 = Color(0xFFE2E2E6)
val Neutral99 = Color(0xFFFCFCFF)

val SurfaceLight = Color(0xFFF8F9FC)
val SurfaceDark = Color(0xFF111318)

val ErrorLight = Color(0xFFBA1A1A)
val ErrorDark = Color(0xFFFFB4AB)

// Schedule status accents (Lectio)
val StatusChanged = Color(0xFFE6A817)
val StatusCancelled = Color(0xFFD32F2F)
val StatusNormal = BrandBlue

private fun Color.toArgbLong(): Long = toArgb().toLong() and 0xFFFFFFFFL

/**
 * Darken (light surfaces) or lighten (dark surfaces) so this colour can be used as
 * text/icon against [against]. Fills should keep the original swatch.
 */
fun Color.ensuringContrast(
    against: Color,
    minRatio: Float = SubjectColorResolver.MIN_TEXT_CONTRAST,
): Color = Color(SubjectColorResolver.ensureContrast(toArgbLong(), against.toArgbLong(), minRatio))

/** Subject/status accent that stays readable as text on the current surface. */
fun Color.readableAccent(dark: Boolean): Color =
    ensuringContrast(if (dark) Color(0xFF121212) else Color.White)

/** Mix [amount] of [accent] into this surface. ~0.18 is a quiet wash that still reads as colour. */
fun Color.tinted(accent: Color, amount: Float = 0.18f): Color {
    val a = amount.coerceIn(0f, 1f)
    return Color(
        red = red + (accent.red - red) * a,
        green = green + (accent.green - green) * a,
        blue = blue + (accent.blue - blue) * a,
        alpha = 1f,
    )
}

/** Subject wash for schedule tiles — a bit stronger on dark surfaces so the tint still shows. */
fun Color.scheduleWash(accent: Color): Color =
    tinted(accent, amount = if (luminance() < 0.5f) 0.24f else 0.18f)
