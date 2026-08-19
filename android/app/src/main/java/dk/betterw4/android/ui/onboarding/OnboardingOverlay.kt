package dk.betterw4.android.ui.onboarding

import android.provider.Settings
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import dk.betterw4.android.R
import kotlinx.coroutines.delay

private val EnterEasing = CubicBezierEasing(0.23f, 1f, 0.32f, 1f)

/**
 * One-time post-login welcome.
 */
@Composable
fun OnboardingOverlay(
    onComplete: () -> Unit,
) {
    BackHandler(enabled = true) {}

    val surface = MaterialTheme.colorScheme.surface
    val wash = MaterialTheme.colorScheme.primary.copy(alpha = 0.10f)

    Surface(
        modifier = Modifier.fillMaxSize(),
        color = surface,
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        colorStops = arrayOf(
                            0f to wash,
                            0.42f to surface,
                            1f to surface,
                        ),
                    ),
                )
                .statusBarsPadding()
                .navigationBarsPadding(),
        ) {
            Column(
                modifier = Modifier.fillMaxSize(),
            ) {
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = 32.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    FadeUp(delayMillis = 0) {
                        Image(
                            painter = painterResource(R.drawable.ic_logo),
                            contentDescription = stringResource(R.string.app_name),
                            modifier = Modifier
                                .size(96.dp)
                                .clip(RoundedCornerShape(24.dp)),
                        )
                    }
                    Spacer(Modifier.height(28.dp))
                    FadeUp(delayMillis = 50) {
                        Text(
                            text = stringResource(R.string.onboarding_welcome_title),
                            style = MaterialTheme.typography.headlineMedium,
                            fontWeight = FontWeight.SemiBold,
                            textAlign = TextAlign.Center,
                        )
                    }
                    Spacer(Modifier.height(12.dp))
                    FadeUp(delayMillis = 100) {
                        Text(
                            text = stringResource(R.string.onboarding_welcome_body),
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center,
                        )
                    }
                }

                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 24.dp)
                        .padding(bottom = 20.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    FadeUp(
                        delayMillis = 160,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Button(
                            onClick = onComplete,
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(52.dp),
                        ) {
                            Text(stringResource(R.string.onboarding_start))
                        }
                    }
                    Spacer(Modifier.height(16.dp))
                    FadeUp(delayMillis = 220) {
                        Text(
                            text = stringResource(R.string.onboarding_credit),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.64f),
                            textAlign = TextAlign.Center,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun FadeUp(
    delayMillis: Int,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    val reduceMotion = rememberReduceMotion()
    var shown by remember { mutableStateOf(reduceMotion) }
    LaunchedEffect(reduceMotion) {
        if (reduceMotion) {
            shown = true
            return@LaunchedEffect
        }
        delay(delayMillis.toLong())
        shown = true
    }
    val progress by animateFloatAsState(
        targetValue = if (shown) 1f else 0f,
        animationSpec = tween(durationMillis = 280, easing = EnterEasing),
        label = "welcomeEnter",
    )
    Box(
        modifier = modifier.graphicsLayer {
            alpha = progress
            val from = 12.dp.toPx()
            translationY = (1f - progress) * from
            val scale = 0.98f + 0.02f * progress
            scaleX = scale
            scaleY = scale
        },
    ) {
        content()
    }
}

@Composable
private fun rememberReduceMotion(): Boolean {
    val context = LocalContext.current
    return remember {
        try {
            Settings.Global.getFloat(
                context.contentResolver,
                Settings.Global.ANIMATOR_DURATION_SCALE,
                1f,
            ) == 0f
        } catch (_: Settings.SettingNotFoundException) {
            false
        }
    }
}
