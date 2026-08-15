package dk.betterlectio.android

import android.app.Application
import coil3.ImageLoader
import coil3.SingletonImageLoader
import com.posthog.PersonProfiles
import com.posthog.PostHogEvent
import com.posthog.android.PostHogAndroid
import com.posthog.android.PostHogAndroidConfig
import dagger.hilt.android.HiltAndroidApp
import dk.betterlectio.android.core.lectio.session.SessionController
import dk.betterlectio.android.feature.feedback.FeedbackLogBuffer
import timber.log.Timber
import javax.inject.Inject

@HiltAndroidApp
class BetterLectioApp : Application(), SingletonImageLoader.Factory {

    @Inject
    lateinit var sessionController: SessionController

    @Inject
    lateinit var imageLoader: ImageLoader

    @Inject
    lateinit var feedbackLogBuffer: FeedbackLogBuffer

    override fun onCreate() {
        super.onCreate()
        // Hilt fields are injected after super.onCreate() returns for @HiltAndroidApp.
        // Plant trees on the first opportunity after injection — see plantLogging().
        // restore() is called from MainActivity to ensure injection is ready.

        if (BuildConfig.POSTHOG_API_KEY.isNotBlank()) {
            val posthogConfig = PostHogAndroidConfig(
                apiKey = BuildConfig.POSTHOG_API_KEY,
                host = BuildConfig.POSTHOG_HOST,
            ).apply {
                // Explicit-only analytics: retain login and feedback outcomes
                // while dropping every automatic/routine event. Referral
                // attribution is emitted once by the server-side finalizer.
                captureApplicationLifecycleEvents = false
                captureDeepLinks = false
                captureScreenViews = false
                sessionReplay = false
                surveys = false
                preloadFeatureFlags = false
                sendFeatureFlagEvent = false
                setDefaultPersonProperties = false
                personProfiles = PersonProfiles.NEVER
                debug = BuildConfig.DEBUG
                errorTrackingConfig.autoCapture = true
                addBeforeSend { event ->
                    when {
                        event.event in ALLOWED_POSTHOG_EVENTS -> event
                        event.event in DEDUPED_POSTHOG_EVENTS && shouldSendOperational(event.event) -> event
                        event.event in SAMPLED_POSTHOG_EVENTS && isInProductSample(event) -> event
                        event.event == "\$exception" && shouldSendError(event) -> event
                        else -> null
                    }
                }
            }
            PostHogAndroid.setup(this, posthogConfig)
        } else if (BuildConfig.DEBUG) {
            Timber.w(
                "PostHog disabled: POSTHOG_API_KEY empty. " +
                    "Set posthog.apiKey in local.properties or POSTHOG_API_KEY env.",
            )
        }

        plantLogging()
    }

    /**
     * Debug console + always-on ring buffer so shake-to-feedback can attach recent logs
     * in release builds as well.
     */
    private fun plantLogging() {
        if (BuildConfig.DEBUG) {
            Timber.plant(Timber.DebugTree())
        }
        if (this::feedbackLogBuffer.isInitialized) {
            Timber.plant(feedbackLogBuffer)
        }
    }

    /** Coil uses the rate-limited ImageLoader from [dk.betterlectio.android.core.di.AppModule]. */
    override fun newImageLoader(context: android.content.Context): ImageLoader {
        return if (this::imageLoader.isInitialized) imageLoader
        else ImageLoader.Builder(context).build()
    }

    private companion object {
        const val MAX_ERRORS_PER_PROCESS = 5
        val ALLOWED_POSTHOG_EVENTS = setOf(
            "login_completed",
            "login_started",
            "login_with_password_completed",
            "demo_entered",
            "logged_out",
            "feedback_submitted",
            "message_reply_sent",
            "message_composed_sent",
            "private_event_created",
            "private_event_updated",
            "private_event_deleted",
            "absence_cause_updated",
            "referral share",
            "review_prompt_shown",
            "review_prompt_positive",
            "review_prompt_negative",
            "review_prompt_dismissed",
            "review_play_flow_requested",
        )
        val DEDUPED_POSTHOG_EVENTS = setOf("login_failed", "lectio session lost")
        val SAMPLED_POSTHOG_EVENTS = setOf(
            "lesson_detail_viewed",
            "assignment_detail_viewed",
            "grades_viewed",
            "absence_viewed",
            "message_thread_opened",
            "referral_screen_opened",
        )
        val seenOperationalEvents = mutableSetOf<String>()
        val errorSignatures = mutableSetOf<String>()
        var errorCount = 0

        @Synchronized
        fun shouldSendError(event: PostHogEvent): Boolean {
            if (errorCount >= MAX_ERRORS_PER_PROCESS) return false
            val signature = event.properties?.get("\$exception_list")?.toString()
                ?: event.properties?.toString()
                ?: "unknown"
            if (!errorSignatures.add(signature.take(1_000))) return false
            errorCount += 1
            return true
        }

        @Synchronized
        fun shouldSendOperational(event: String): Boolean = seenOperationalEvents.add(event)

        fun isInProductSample(event: PostHogEvent): Boolean =
            Math.floorMod(event.distinctId.hashCode(), 10) == 0
    }
}
