package dk.betterlectio.android.feature.review

import com.posthog.PostHog
import dk.betterlectio.android.core.lectio.session.SessionController
import dk.betterlectio.android.feature.feedback.FeedbackOpenRequests
import dk.betterlectio.android.feature.referral.ReferralCoordinator
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import timber.log.Timber
import java.time.Instant
import java.util.concurrent.atomic.AtomicBoolean
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Orchestrates soft rating pre-filter + Play review after happy moments.
 */
@Singleton
class ReviewPromptCoordinator @Inject constructor(
    private val store: ReviewPromptStore,
    private val eligibility: ReviewEligibility,
    private val playReviewLauncher: PlayReviewLauncher,
    private val session: SessionController,
    private val referralCoordinator: ReferralCoordinator,
    private val feedbackOpenRequests: FeedbackOpenRequests,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val launchRecordedThisProcess = AtomicBoolean(false)
    private var sessionStartedAt: Instant? = null
    private var lastErrorAt: Instant? = null
    private var pendingJob: Job? = null
    private var shownTrigger: ReviewTrigger? = null
    private val responseHandled = AtomicBoolean(false)

    /** Active soft-prompt blockers keyed by source (extension, feedback, …). */
    private val blockers = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()

    private val _softPromptVisible = MutableStateFlow(false)
    val softPromptVisible: StateFlow<Boolean> = _softPromptVisible.asStateFlow()

    /**
     * Call once per authenticated process from the authenticated shell.
     * Records a launch for the 8-opens / 14-days gate.
     */
    fun onAuthenticatedLaunch() {
        if (!launchRecordedThisProcess.compareAndSet(false, true)) return
        sessionStartedAt = Instant.now()
        store.recordLaunch()
    }

    fun reportRecentError() {
        lastErrorAt = Instant.now()
    }

    fun setExternalPromptBlocking(source: String, blocking: Boolean) {
        if (blocking) blockers.add(source) else blockers.remove(source)
    }

    /**
     * After a happy moment — delays briefly, re-checks gates, then may show the soft sheet.
     */
    fun maybePrompt(trigger: ReviewTrigger) {
        val student = session.currentStudent ?: return
        if (student.isDemo) return
        if (_softPromptVisible.value) return

        pendingJob?.cancel()
        pendingJob = scope.launch {
            delay(PROMPT_DELAY_MS)
            if (_softPromptVisible.value) return@launch
            if (hasConflictingPrompt()) {
                Timber.d("Review prompt skipped: conflicting UI (%s)", trigger.analyticsName)
                return@launch
            }
            if (!eligibility.isEligible(
                    sessionStartedAt = sessionStartedAt,
                    lastErrorAt = lastErrorAt,
                )
            ) {
                Timber.d("Review prompt ineligible (%s)", trigger.analyticsName)
                return@launch
            }
            shownTrigger = trigger
            responseHandled.set(false)
            store.markSoftPromptShown()
            _softPromptVisible.value = true
            PostHog.capture(
                event = "review_prompt_shown",
                properties = mapOf("trigger" to trigger.analyticsName),
            )
        }
    }

    fun onPositive(activity: android.app.Activity) {
        if (!responseHandled.compareAndSet(false, true)) {
            dismissSoftPromptUi()
            return
        }
        val trigger = shownTrigger?.analyticsName.orEmpty()
        PostHog.capture(
            event = "review_prompt_positive",
            properties = mapOf("trigger" to trigger),
        )
        dismissSoftPromptUi()
        store.markPlayFlowRequested()
        playReviewLauncher.launch(activity) { launched ->
            PostHog.capture(
                event = "review_play_flow_requested",
                properties = mapOf(
                    "trigger" to trigger,
                    "play_accepted" to launched,
                ),
            )
        }
    }

    fun onNegative() {
        if (!responseHandled.compareAndSet(false, true)) {
            dismissSoftPromptUi()
            return
        }
        val trigger = shownTrigger?.analyticsName.orEmpty()
        PostHog.capture(
            event = "review_prompt_negative",
            properties = mapOf("trigger" to trigger),
        )
        dismissSoftPromptUi()
        feedbackOpenRequests.requestOpen()
    }

    fun onDismissed() {
        if (!responseHandled.compareAndSet(false, true)) {
            dismissSoftPromptUi()
            return
        }
        val trigger = shownTrigger?.analyticsName.orEmpty()
        PostHog.capture(
            event = "review_prompt_dismissed",
            properties = mapOf("trigger" to trigger),
        )
        dismissSoftPromptUi()
    }

    private fun dismissSoftPromptUi() {
        _softPromptVisible.value = false
        shownTrigger = null
    }

    private fun hasConflictingPrompt(): Boolean {
        if (blockers.isNotEmpty()) return true
        if (referralCoordinator.nudgeVisible.value) return true
        return false
    }

    companion object {
        private const val PROMPT_DELAY_MS = 1_800L
    }
}
