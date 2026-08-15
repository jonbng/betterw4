package dk.betterlectio.android.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MotionScheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp

private val LightColorScheme = lightColorScheme(
    primary = BrandBlue,
    onPrimary = Color.White,
    primaryContainer = BrandBlueContainer,
    onPrimaryContainer = Color(0xFF001A41),
    secondary = Color(0xFF565E71),
    onSecondary = Color.White,
    secondaryContainer = Color(0xFFDAE2F9),
    onSecondaryContainer = Color(0xFF131C2B),
    tertiary = Color(0xFF705574),
    onTertiary = Color.White,
    tertiaryContainer = Color(0xFFFAD8FD),
    onTertiaryContainer = Color(0xFF29132E),
    error = ErrorLight,
    onError = Color.White,
    background = SurfaceLight,
    onBackground = Neutral10,
    surface = SurfaceLight,
    onSurface = Neutral10,
    surfaceVariant = Color(0xFFE1E2EC),
    onSurfaceVariant = Color(0xFF44474F),
    outline = Color(0xFF74777F),
)

private val DarkColorScheme = darkColorScheme(
    primary = BrandBlueDark,
    onPrimary = Color(0xFF002E69),
    primaryContainer = BrandBlueContainerDark,
    onPrimaryContainer = BrandBlueContainer,
    secondary = Color(0xFFBEC6DC),
    onSecondary = Color(0xFF283041),
    secondaryContainer = Color(0xFF3E4759),
    onSecondaryContainer = Color(0xFFDAE2F9),
    tertiary = Color(0xFFDDBCE0),
    onTertiary = Color(0xFF3F2844),
    tertiaryContainer = Color(0xFF573E5B),
    onTertiaryContainer = Color(0xFFFAD8FD),
    error = ErrorDark,
    onError = Color(0xFF690005),
    background = SurfaceDark,
    onBackground = Neutral90,
    surface = SurfaceDark,
    onSurface = Neutral90,
    surfaceVariant = Color(0xFF44474F),
    onSurfaceVariant = Color(0xFFC4C6D0),
    outline = Color(0xFF8E9099),
)

/** Slightly tighter, system-like corners — not the soft “card app” look. */
private val AppShapes = Shapes(
    extraSmall = RoundedCornerShape(4.dp),
    small = RoundedCornerShape(8.dp),
    medium = RoundedCornerShape(12.dp),
    large = RoundedCornerShape(16.dp),
    extraLarge = RoundedCornerShape(24.dp),
)

@Immutable
data class BetterLectioExtendedColors(
    val statusChanged: Color,
    val statusCancelled: Color,
    val statusNormal: Color,
)

val LocalExtendedColors = staticCompositionLocalOf {
    BetterLectioExtendedColors(
        statusChanged = StatusChanged,
        statusCancelled = StatusCancelled,
        statusNormal = StatusNormal,
    )
}

@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun BetterLectioTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    /**
     * When true on Android 12+, uses Material You dynamic colors.
     * Prefer brand colors for product consistency; enable if users want wallpaper-matched UI.
     */
    dynamicColor: Boolean = false,
    content: @Composable () -> Unit,
) {
    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        darkTheme -> DarkColorScheme
        else -> LightColorScheme
    }

    val extended = BetterLectioExtendedColors(
        statusChanged = StatusChanged,
        statusCancelled = StatusCancelled,
        statusNormal = if (darkTheme) BrandBlueDark else StatusNormal,
    )

    // Expressive component language with *standard* motion — calm school-app springs, not bounce.
    CompositionLocalProvider(LocalExtendedColors provides extended) {
        MaterialTheme(
            colorScheme = colorScheme,
            motionScheme = MotionScheme.standard(),
            shapes = AppShapes,
            typography = Typography,
            content = content,
        )
    }
}

object BetterLectioThemeExtras {
    val extendedColors: BetterLectioExtendedColors
        @Composable
        get() = LocalExtendedColors.current
}
