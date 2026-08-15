package dk.betterlectio.android.ui.feedback

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.hardware.SensorManager
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Feedback
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dk.betterlectio.android.R
import dk.betterlectio.android.feature.feedback.FeedbackCapture
import dk.betterlectio.android.feature.feedback.FeedbackOpenRequests
import dk.betterlectio.android.feature.feedback.FeedbackRepository
import dk.betterlectio.android.feature.feedback.FeedbackSubmitResult
import dk.betterlectio.android.feature.feedback.FeedbackSubmission
import dk.betterlectio.android.feature.feedback.ScreenshotCapturer
import dk.betterlectio.android.feature.feedback.ShakeDetector
import dk.betterlectio.android.feature.feedback.ShakeInteractionGate
import dk.betterlectio.android.feature.review.ReviewPromptCoordinator
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.launch
import timber.log.Timber
import javax.inject.Inject

/**
 * Overlay host: listens for deliberate device shakes, shows a short-lived confirm
 * chip, and only then captures screenshot + logs / opens [FeedbackSheet].
 * Place once at the root of the Compose tree (above navigation).
 */
@Composable
fun FeedbackHost(
    viewModel: FeedbackHostViewModel = hiltViewModel(),
    content: @Composable () -> Unit,
) {
    val context = LocalContext.current
    val view = LocalView.current
    val activity = remember(context) { context.findActivity() }
    val scope = rememberCoroutineScope()

    var showPrompt by remember { mutableStateOf(false) }
    var activeCapture by remember { mutableStateOf<FeedbackCapture?>(null) }
    var opening by remember { mutableStateOf(false) }
    var promptGeneration by remember { mutableIntStateOf(0) }
    var openRequestGeneration by remember { mutableIntStateOf(0) }
    val practiceMode by viewModel.practiceMode.collectAsStateWithLifecycle()

    DisposableEffect(activity) {
        if (activity == null) {
            return@DisposableEffect onDispose { }
        }
        val sensorManager =
            activity.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        val detector = ShakeDetector(
            sensorManager = sensorManager,
            onShake = { viewModel.onShakeDetected() },
        )
        detector.start()
        onDispose { detector.stop() }
    }

    // Keep rating prompts from stacking over an open feedback sheet.
    LaunchedEffect(activeCapture, opening) {
        viewModel.setReviewBlocking(activeCapture != null || opening)
    }

    // Shake → confirm chip (not the sheet). Auto-hides so accidents are harmless.
    // Skipped while onboarding (or other sources) suppress the prompt.
    LaunchedEffect(viewModel) {
        viewModel.shakeEvents.collect {
            if (viewModel.isShakePromptSuppressed()) return@collect
            if (activeCapture != null || opening || showPrompt) return@collect
            performHaptic(view)
            showPrompt = true
            promptGeneration += 1
            Timber.d("Feedback confirm chip shown")
        }
    }

    // Rating pre-filter "could be better" → open feedback sheet directly.
    LaunchedEffect(viewModel) {
        viewModel.openRequests.collect {
            openRequestGeneration += 1
        }
    }

    LaunchedEffect(promptGeneration, showPrompt, practiceMode) {
        if (!showPrompt) return@LaunchedEffect
        // Keep the chip up during onboarding practice so they can tap it.
        if (practiceMode) return@LaunchedEffect
        delay(PROMPT_AUTO_HIDE_MS)
        showPrompt = false
    }

    LaunchedEffect(openRequestGeneration) {
        if (openRequestGeneration == 0) return@LaunchedEffect
        if (opening || activeCapture != null) return@LaunchedEffect
        val act = activity ?: return@LaunchedEffect
        showPrompt = false
        opening = true
        try {
            delay(PROMPT_EXIT_CAPTURE_DELAY_MS)
            performHaptic(view)
            val bitmap = ScreenshotCapturer.capture(act)
            val logs = viewModel.currentLogs()
            activeCapture = FeedbackCapture(
                screenshot = bitmap,
                logs = logs,
            )
            Timber.d(
                "Feedback sheet opened from review prompt screenshot=%s logsChars=%d",
                bitmap != null,
                logs.length,
            )
        } catch (t: Throwable) {
            Timber.w(t, "Failed to open feedback sheet from review prompt")
            activeCapture = FeedbackCapture(
                screenshot = null,
                logs = viewModel.currentLogs(),
            )
        } finally {
            opening = false
        }
    }

    fun openFeedbackSheet() {
        if (opening || activeCapture != null) return
        val act = activity ?: return
        showPrompt = false
        opening = true
        scope.launch {
            // Let the chip leave the tree so it is not in the screenshot.
            delay(PROMPT_EXIT_CAPTURE_DELAY_MS)
            try {
                performHaptic(view)
                val bitmap = ScreenshotCapturer.capture(act)
                val logs = viewModel.currentLogs()
                activeCapture = FeedbackCapture(
                    screenshot = bitmap,
                    logs = logs,
                )
                Timber.d(
                    "Feedback sheet opened screenshot=%s logsChars=%d",
                    bitmap != null,
                    logs.length,
                )
            } catch (t: Throwable) {
                Timber.w(t, "Failed to open feedback sheet")
                activeCapture = FeedbackCapture(
                    screenshot = null,
                    logs = viewModel.currentLogs(),
                )
            } finally {
                opening = false
            }
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        content()

        AnimatedVisibility(
            visible = showPrompt && activeCapture == null && !opening,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .navigationBarsPadding()
                .padding(bottom = 88.dp),
            enter = fadeIn() + scaleIn(initialScale = 0.92f),
            exit = fadeOut() + scaleOut(targetScale = 0.92f),
        ) {
            FeedbackShakePrompt(
                onConfirm = {
                    if (practiceMode) {
                        showPrompt = false
                        viewModel.notifyPracticeChipConfirmed()
                        Timber.d("Feedback confirm chip tapped in onboarding practice")
                    } else {
                        openFeedbackSheet()
                    }
                },
                onDismiss = { showPrompt = false },
            )
        }
    }

    activeCapture?.let { capture ->
        FeedbackSheet(
            capture = capture,
            onDismiss = {
                capture.screenshot?.takeIf { !it.isRecycled }?.recycle()
                activeCapture = null
                viewModel.setReviewBlocking(false)
            },
            onSubmit = { submission -> viewModel.submit(submission) },
        )
    }
}

@Composable
private fun FeedbackShakePrompt(
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    Surface(
        shape = RoundedCornerShape(32.dp),
        color = MaterialTheme.colorScheme.primary,
        shadowElevation = 10.dp,
    ) {
        Row(
            modifier = Modifier.padding(start = 18.dp, end = 6.dp, top = 8.dp, bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Icon(
                Icons.Outlined.Feedback,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onPrimary,
                modifier = Modifier.padding(end = 2.dp),
            )
            TextButton(onClick = onConfirm) {
                Text(
                    stringResource(R.string.feedback_prompt_action),
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onPrimary,
                )
            }
            IconButton(onClick = onDismiss) {
                Icon(
                    Icons.Outlined.Close,
                    contentDescription = stringResource(R.string.feedback_prompt_dismiss),
                    tint = MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.85f),
                )
            }
        }
    }
}

@HiltViewModel
class FeedbackHostViewModel @Inject constructor(
    private val repository: FeedbackRepository,
    private val openRequestsBus: FeedbackOpenRequests,
    private val reviewPromptCoordinator: ReviewPromptCoordinator,
    private val shakeGate: ShakeInteractionGate,
) : ViewModel() {

    val shakeEvents: SharedFlow<Unit> = shakeGate.shakeEvents

    val openRequests: SharedFlow<Unit> = openRequestsBus.requests

    val practiceMode = shakeGate.practiceMode

    private var submitJob: Job? = null

    fun onShakeDetected() {
        shakeGate.onShakeDetected()
    }

    fun setShakePromptSuppressed(source: String, suppressed: Boolean) {
        shakeGate.setShakePromptSuppressed(source, suppressed)
    }

    fun isShakePromptSuppressed(): Boolean = shakeGate.isShakePromptSuppressed()

    fun isPracticeMode(): Boolean = shakeGate.isPracticeMode()

    fun notifyPracticeChipConfirmed() {
        shakeGate.notifyPracticeChipConfirmed()
    }

    fun setReviewBlocking(blocking: Boolean) {
        reviewPromptCoordinator.setExternalPromptBlocking("feedback", blocking)
    }

    fun currentLogs(): String = repository.currentLogs()

    suspend fun submit(submission: FeedbackSubmission): FeedbackSubmitResult {
        return repository.submit(submission)
    }

    /** Optional: fire-and-forget submit from non-suspend call sites. */
    fun submitAsync(
        submission: FeedbackSubmission,
        onResult: (FeedbackSubmitResult) -> Unit,
    ) {
        submitJob?.cancel()
        submitJob = viewModelScope.launch {
            onResult(repository.submit(submission))
        }
    }
}

private const val PROMPT_AUTO_HIDE_MS = 5_000L
private const val PROMPT_EXIT_CAPTURE_DELAY_MS = 80L

private fun performHaptic(view: View) {
    try {
        view.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
    } catch (_: Throwable) {
        view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
    }
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
