package dk.betterw4.android

import android.app.Application
import coil3.ImageLoader
import coil3.SingletonImageLoader
import com.posthog.android.PostHogAndroid
import com.posthog.android.PostHogAndroidConfig
import dagger.hilt.android.HiltAndroidApp
import dk.betterw4.android.core.analytics.AppTelemetry
import dk.betterw4.android.core.analytics.PreviousExitReporter
import dk.betterw4.android.core.w4.session.SessionController
import timber.log.Timber
import javax.inject.Inject

@HiltAndroidApp
class BetterW4App : Application(), SingletonImageLoader.Factory {

    @Inject
    lateinit var sessionController: SessionController

    @Inject
    lateinit var imageLoader: ImageLoader

    override fun onCreate() {
        super.onCreate()
        plantLogging()
        initializePostHog()
    }

    private fun initializePostHog() {
        val projectToken = BuildConfig.POSTHOG_PROJECT_TOKEN
        val host = BuildConfig.POSTHOG_HOST

        if (projectToken.isBlank()) {
            if (BuildConfig.DEBUG) {
                error("POSTHOG_PROJECT_TOKEN variable required by PostHog is missing or un-configured, this causes events to be silently missed. This error stops appearing once POSTHOG_PROJECT_TOKEN is configured")
            }
            return
        }

        if (host.isBlank()) {
            if (BuildConfig.DEBUG) {
                error("POSTHOG_HOST variable required by PostHog is missing or un-configured, this causes events to be silently missed. This error stops appearing once POSTHOG_HOST is configured")
            }
            return
        }

        val config = PostHogAndroidConfig(apiKey = projectToken, host = host).apply {
            // Keep analytics deliberately small and make privacy-sensitive features explicit.
            captureApplicationLifecycleEvents = true
            captureScreenViews = false
            captureDeepLinks = false
            sessionReplay = false
            surveys = false
            preloadFeatureFlags = false
            sendFeatureFlagEvent = false
            errorTrackingConfig.apply {
                autoCapture = true
                captureNativeCrashes = true
                exceptionSteps.enabled = true
            }
        }
        PostHogAndroid.setup(this, config)
        AppTelemetry.markInitialized()
        PreviousExitReporter.report(this)
    }

    private fun plantLogging() {
        if (BuildConfig.DEBUG) {
            Timber.plant(Timber.DebugTree())
        }
    }

    /** Coil uses the cookie-aware ImageLoader from [dk.betterw4.android.core.di.AppModule]. */
    override fun newImageLoader(context: android.content.Context): ImageLoader {
        return if (this::imageLoader.isInitialized) imageLoader
        else ImageLoader.Builder(context).build()
    }
}
