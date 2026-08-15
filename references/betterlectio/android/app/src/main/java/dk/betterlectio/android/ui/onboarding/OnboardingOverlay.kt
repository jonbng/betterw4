package dk.betterlectio.android.ui.onboarding

import android.view.HapticFeedbackConstants
import android.view.View
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
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
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Feedback
import androidx.compose.material.icons.outlined.Smartphone
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dk.betterlectio.android.R
import dk.betterlectio.android.feature.feedback.ShakeInteractionGate
import dk.betterlectio.android.feature.settings.SettingsStore
import dk.betterlectio.android.feature.supabase.SupabaseSubjectService
import kotlinx.coroutines.delay

private const val STEP_COUNT = 3
private const val SOFT_SKIP_DELAY_MS = 10_000L
private const val SHAKE_SUPPRESS_SOURCE = "onboarding"

private enum class PracticePhase {
    WaitingShake,
    WaitingChipTap,
    Done,
}

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
 * One-time post-login wizard: welcome, subject colors, then hobby + shake/chip practice.
 * Uses a full-screen overlay (not a Dialog) so [FeedbackHost]'s real confirm chip can
 * appear on top during the practice step.
 */
@Composable
fun OnboardingOverlay(
    shakeGate: ShakeInteractionGate,
    settingsStore: SettingsStore,
    onComplete: () -> Unit,
) {
    val view = LocalView.current
    var step by remember { mutableIntStateOf(0) }
    var practicePhase by remember { mutableStateOf(PracticePhase.WaitingShake) }
    var showSoftSkip by remember { mutableStateOf(false) }
    var stepDirection by remember { mutableIntStateOf(1) }
    val useSubjectColors by settingsStore.useSubjectColors.collectAsStateWithLifecycle()

    val onPracticeStep = step == STEP_COUNT - 1

    DisposableEffect(shakeGate) {
        onDispose {
            shakeGate.setShakePromptSuppressed(SHAKE_SUPPRESS_SOURCE, false)
            shakeGate.setPracticeMode(false)
        }
    }

    LaunchedEffect(onPracticeStep, shakeGate) {
        if (onPracticeStep) {
            shakeGate.setShakePromptSuppressed(SHAKE_SUPPRESS_SOURCE, false)
            shakeGate.setPracticeMode(true)
        } else {
            shakeGate.setPracticeMode(false)
            shakeGate.setShakePromptSuppressed(SHAKE_SUPPRESS_SOURCE, true)
            if (practicePhase != PracticePhase.Done) {
                practicePhase = PracticePhase.WaitingShake
            }
        }
    }

    LaunchedEffect(onPracticeStep, shakeGate) {
        if (!onPracticeStep) return@LaunchedEffect
        shakeGate.shakeEvents.collect {
            if (practicePhase == PracticePhase.WaitingShake) {
                practicePhase = PracticePhase.WaitingChipTap
                performHaptic(view)
            }
        }
    }

    LaunchedEffect(onPracticeStep, shakeGate) {
        if (!onPracticeStep) return@LaunchedEffect
        shakeGate.practiceChipConfirmed.collect {
            if (practicePhase == PracticePhase.WaitingChipTap) {
                practicePhase = PracticePhase.Done
                performHaptic(view)
            }
        }
    }

    LaunchedEffect(onPracticeStep, practicePhase) {
        showSoftSkip = false
        if (!onPracticeStep || practicePhase == PracticePhase.Done) return@LaunchedEffect
        delay(SOFT_SKIP_DELAY_MS)
        showSoftSkip = true
    }

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
                    1 -> SubjectColorsStep(
                        useSubjectColors = useSubjectColors,
                        onUseSubjectColorsChange = settingsStore::setUseSubjectColors,
                    )
                    else -> FeedbackPracticeStep(phase = practicePhase)
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

                    when {
                        step < STEP_COUNT - 1 -> {
                            Button(onClick = {
                                stepDirection = 1
                                step += 1
                            }) {
                                Text(stringResource(R.string.onboarding_next))
                            }
                        }
                        practicePhase == PracticePhase.Done -> {
                            Button(onClick = onComplete) {
                                Text(stringResource(R.string.onboarding_start))
                            }
                        }
                        else -> {
                            Button(
                                onClick = {},
                                enabled = false,
                            ) {
                                Text(
                                    stringResource(
                                        if (practicePhase == PracticePhase.WaitingShake) {
                                            R.string.onboarding_shake_to_continue
                                        } else {
                                            R.string.onboarding_tap_chip_to_continue
                                        },
                                    ),
                                )
                            }
                        }
                    }
                }

                AnimatedVisibility(
                    visible = onPracticeStep &&
                        showSoftSkip &&
                        practicePhase != PracticePhase.Done,
                    enter = fadeIn(),
                    exit = fadeOut(),
                ) {
                    TextButton(
                        onClick = onComplete,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 4.dp),
                    ) {
                        Text(text = stringResource(R.string.onboarding_skip_shake))
                    }
                }

                if (onPracticeStep && practicePhase == PracticePhase.WaitingChipTap) {
                    Spacer(Modifier.height(72.dp))
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
private fun FeedbackPracticeStep(phase: PracticePhase) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 28.dp)
            .padding(top = 28.dp, bottom = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Text(
            text = stringResource(R.string.onboarding_hobby_title),
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center,
        )
        Text(
            text = stringResource(R.string.onboarding_hobby_body),
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )

        AnimatedContent(
            targetState = phase,
            transitionSpec = {
                fadeIn(tween(220)) togetherWith fadeOut(tween(160))
            },
            label = "practicePhase",
        ) { current ->
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(14.dp),
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 8.dp),
            ) {
                when (current) {
                    PracticePhase.WaitingShake -> {
                        ShakePhoneIllustration()
                        Text(
                            text = stringResource(R.string.onboarding_practice_shake_body),
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center,
                        )
                        Text(
                            text = stringResource(R.string.onboarding_shake_hint),
                            style = MaterialTheme.typography.titleSmall,
                            color = MaterialTheme.colorScheme.primary,
                            fontWeight = FontWeight.Medium,
                            textAlign = TextAlign.Center,
                        )
                    }
                    PracticePhase.WaitingChipTap -> {
                        IconBadge {
                            Icon(
                                imageVector = Icons.Outlined.Feedback,
                                contentDescription = null,
                                modifier = Modifier.size(40.dp),
                                tint = MaterialTheme.colorScheme.primary,
                            )
                        }
                        Text(
                            text = stringResource(R.string.onboarding_practice_chip_title),
                            style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.SemiBold,
                            textAlign = TextAlign.Center,
                        )
                        Text(
                            text = stringResource(R.string.onboarding_practice_chip_body),
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center,
                        )
                    }
                    PracticePhase.Done -> {
                        IconBadge {
                            Icon(
                                imageVector = Icons.Outlined.CheckCircle,
                                contentDescription = null,
                                modifier = Modifier.size(40.dp),
                                tint = MaterialTheme.colorScheme.primary,
                            )
                        }
                        Text(
                            text = stringResource(R.string.onboarding_practice_success_title),
                            style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.SemiBold,
                            textAlign = TextAlign.Center,
                        )
                        Text(
                            text = stringResource(R.string.onboarding_practice_success_body),
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center,
                        )
                    }
                }
            }
        }
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
                val accent = Color(SupabaseSubjectService.hueToArgb(hue))
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
                            .background(Color(SupabaseSubjectService.hueToArgb(hue))),
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

@Composable
private fun ShakePhoneIllustration() {
    val transition = rememberInfiniteTransition(label = "shakePhone")
    val rotation by transition.animateFloat(
        initialValue = -10f,
        targetValue = 10f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 420, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "shakeRotation",
    )

    IconBadge {
        Box(contentAlignment = Alignment.Center) {
            Icon(
                imageVector = Icons.Outlined.Smartphone,
                contentDescription = null,
                modifier = Modifier
                    .size(40.dp)
                    .rotate(rotation),
                tint = MaterialTheme.colorScheme.primary,
            )
            Icon(
                imageVector = Icons.Outlined.Feedback,
                contentDescription = null,
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .size(16.dp)
                    .rotate(rotation * 0.4f),
                tint = MaterialTheme.colorScheme.primary,
            )
        }
    }
}

private fun performHaptic(view: View) {
    try {
        view.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
    } catch (_: Throwable) {
        view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
    }
}
