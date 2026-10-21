package dk.betterw4.android

import android.app.Application
import coil3.ImageLoader
import coil3.SingletonImageLoader
import com.posthog.android.PostHogAndroid
import com.posthog.android.PostHogAndroidConfig
import dagger.hilt.android.HiltAndroidApp
import dk.betterw4.android.core.analytics.AppTelemetry
import dk.betterw4.android.core.analytics.CrashReporter
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
        val postHogInitialized = initializePostHog()
        CrashReporter.install(this)
        if (postHogInitialized) {
            CrashReporter.reportPendingCrash(this)
            PreviousExitReporter.report(this)
        }
    }

    private fun initializePostHog(): Boolean {
        val projectToken = BuildConfig.POSTHOG_PROJECT_TOKEN
        val host = BuildConfig.POSTHOG_HOST

        if (projectToken.isBlank()) {
            Timber.e("PostHog disabled: POSTHOG_PROJECT_TOKEN is missing")
            return false
        }

        if (host.isBlank()) {
            Timber.e("PostHog disabled: POSTHOG_HOST is missing")
            return false
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
            if (BuildConfig.DEBUG) {
                flushAt = 1
                flushIntervalSeconds = 5
            }
            errorTrackingConfig.apply {
                autoCapture = true
                captureNativeCrashes = true
                exceptionSteps.enabled = true
            }
        }
        PostHogAndroid.setup(this, config)
        AppTelemetry.markInitialized()
        return true
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
