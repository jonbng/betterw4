package dk.betterw4.android.ui.onboarding

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.Smartphone
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dk.betterw4.android.R
import dk.betterw4.android.feature.settings.SettingsStore
import dk.betterw4.android.feature.settings.SubjectColorResolver

private const val STEP_COUNT = 2

private data class PreviewBlock(
    val shortLabel: String,
    val labelRes: Int,
    val hue: Int,
)

private val PREVIEW_BLOCKS = listOf(
    PreviewBlock("Ma", R.string.onboarding_preview_math, 220),
    PreviewBlock("Da", R.string.onboarding_preview_danish, 340),
    PreviewBlock("En", R.string.onboarding_preview_english, 45),
    PreviewBlock("Hi", R.string.onboarding_preview_history, 150),
    PreviewBlock("Fy", R.string.onboarding_preview_physics, 280),
)

/**
 * One-time post-login wizard: welcome, then subject colors.
 */
@Composable
fun OnboardingOverlay(
    settingsStore: SettingsStore,
    onComplete: () -> Unit,
) {
    var step by remember { mutableIntStateOf(0) }
    var stepDirection by remember { mutableIntStateOf(1) }
    val useSubjectColors by settingsStore.useSubjectColors.collectAsStateWithLifecycle()

    BackHandler(enabled = true) {
        if (step > 0) {
            stepDirection = -1
            step -= 1
        }
    }

    Surface(
        modifier = Modifier.fillMaxSize(),
        color = MaterialTheme.colorScheme.surface,
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding(),
        ) {
            LinearProgressIndicator(
                progress = { (step + 1f) / STEP_COUNT },
                modifier = Modifier.fillMaxWidth(),
                trackColor = MaterialTheme.colorScheme.surfaceVariant,
            )

            AnimatedContent(
                targetState = step,
                transitionSpec = {
                    val enter = slideInHorizontally(
                        animationSpec = tween(220),
                        initialOffsetX = { full -> if (stepDirection >= 0) full / 4 else -full / 4 },
                    ) + fadeIn(tween(220))
                    val exit = slideOutHorizontally(
                        animationSpec = tween(180),
                        targetOffsetX = { full -> if (stepDirection >= 0) -full / 5 else full / 5 },
                    ) + fadeOut(tween(160))
                    enter togetherWith exit
                },
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth(),
                label = "onboardingStep",
            ) { current ->
                when (current) {
                    0 -> WelcomeStep()
                    else -> SubjectColorsStep(
                        useSubjectColors = useSubjectColors,
                        onUseSubjectColorsChange = settingsStore::setUseSubjectColors,
                    )
                }
            }

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 24.dp)
                    .padding(bottom = 20.dp),
            ) {
                StepDots(step = step, count = STEP_COUNT)

                Spacer(Modifier.height(16.dp))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    if (step > 0) {
                        TextButton(onClick = {
                            stepDirection = -1
                            step -= 1
                        }) {
                            Icon(
                                Icons.AutoMirrored.Filled.ArrowBack,
                                contentDescription = null,
                                modifier = Modifier.size(18.dp),
                            )
                            Spacer(Modifier.width(4.dp))
                            Text(stringResource(R.string.onboarding_back))
                        }
                    } else {
                        Spacer(Modifier.width(1.dp))
                    }

                    if (step < STEP_COUNT - 1) {
                        Button(onClick = {
                            stepDirection = 1
                            step += 1
                        }) {
                            Text(stringResource(R.string.onboarding_next))
                        }
                    } else {
                        Button(onClick = onComplete) {
                            Text(stringResource(R.string.onboarding_start))
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun WelcomeStep() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 28.dp)
            .padding(top = 36.dp, bottom = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        IconBadge {
            Icon(
                imageVector = Icons.Outlined.Smartphone,
                contentDescription = null,
                modifier = Modifier.size(40.dp),
                tint = MaterialTheme.colorScheme.primary,
            )
        }
        Text(
            text = stringResource(R.string.onboarding_welcome_title),
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center,
        )
        Text(
            text = stringResource(R.string.onboarding_welcome_body),
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        Text(
            text = stringResource(R.string.onboarding_welcome_supporting),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun SubjectColorsStep(
    useSubjectColors: Boolean,
    onUseSubjectColorsChange: (Boolean) -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 28.dp)
            .padding(top = 28.dp, bottom = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(
            text = stringResource(R.string.onboarding_colors_title),
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center,
        )
        Text(
            text = stringResource(R.string.onboarding_colors_body),
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )

        SchedulePreview(colored = useSubjectColors)

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            ColorChoiceCard(
                selected = useSubjectColors,
                title = stringResource(R.string.onboarding_colors_with),
                coloredDots = true,
                onClick = { onUseSubjectColorsChange(true) },
                modifier = Modifier.weight(1f),
            )
            ColorChoiceCard(
                selected = !useSubjectColors,
                title = stringResource(R.string.onboarding_colors_without),
                coloredDots = false,
                onClick = { onUseSubjectColorsChange(false) },
                modifier = Modifier.weight(1f),
            )
        }

        Text(
            text = stringResource(R.string.onboarding_colors_hint),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun SchedulePreview(colored: Boolean) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f),
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            PREVIEW_BLOCKS.forEach { block ->
                val hue = if (colored) block.hue else 215
                val accent = Color(SubjectColorResolver.hueToArgb(hue))
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .clip(RoundedCornerShape(12.dp))
                        .background(accent.copy(alpha = if (colored) 0.18f else 0.10f))
                        .padding(vertical = 14.dp, horizontal = 4.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Text(
                        text = block.shortLabel,
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.Bold,
                        color = accent.copy(alpha = if (colored) 1f else 0.75f),
                    )
                    Text(
                        text = stringResource(block.labelRes),
                        style = MaterialTheme.typography.labelSmall,
                        color = accent.copy(alpha = if (colored) 0.75f else 0.55f),
                        maxLines = 1,
                    )
                }
            }
        }
    }
}

@Composable
private fun ColorChoiceCard(
    selected: Boolean,
    title: String,
    coloredDots: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val borderColor = if (selected) {
        MaterialTheme.colorScheme.primary
    } else {
        MaterialTheme.colorScheme.outlineVariant
    }
    Surface(
        modifier = modifier
            .border(
                width = if (selected) 2.dp else 1.dp,
                color = borderColor,
                shape = RoundedCornerShape(16.dp),
            )
            .clip(RoundedCornerShape(16.dp))
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(16.dp),
        color = if (selected) {
            MaterialTheme.colorScheme.primary.copy(alpha = 0.06f)
        } else {
            MaterialTheme.colorScheme.surface
        },
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 14.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                val hues = if (coloredDots) listOf(220, 340, 45, 150) else listOf(215, 215, 215, 215)
                hues.forEach { hue ->
                    Box(
                        modifier = Modifier
                            .size(10.dp)
                            .clip(CircleShape)
                            .background(Color(SubjectColorResolver.hueToArgb(hue))),
                    )
                }
            }
            Text(
                text = title,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
                color = if (selected) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.onSurface
                },
                textAlign = TextAlign.Center,
            )
        }
    }
}

@Composable
private fun StepDots(step: Int, count: Int) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        repeat(count) { index ->
            val active = index == step
            val done = index < step
            Box(
                modifier = Modifier
                    .padding(horizontal = 3.dp)
                    .height(6.dp)
                    .width(if (active) 18.dp else 6.dp)
                    .clip(CircleShape)
                    .background(
                        when {
                            active -> MaterialTheme.colorScheme.primary
                            done -> MaterialTheme.colorScheme.primary.copy(alpha = 0.4f)
                            else -> MaterialTheme.colorScheme.outlineVariant
                        },
                    ),
            )
        }
    }
}

@Composable
private fun IconBadge(content: @Composable () -> Unit) {
    Box(
        modifier = Modifier
            .size(80.dp)
            .background(
                color = MaterialTheme.colorScheme.primaryContainer,
                shape = RoundedCornerShape(24.dp),
            ),
        contentAlignment = Alignment.Center,
    ) {
        content()
    }
}
