package dk.betterw4.android.feature.review

import android.app.Activity
import android.content.Context
import com.google.android.play.core.review.ReviewManagerFactory
import dagger.hilt.android.qualifiers.ApplicationContext
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Play In-App Review wrapper. Safe on non-Play devices (never crashes).
 */
@Singleton
class PlayReviewLauncher @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    /**
     * Requests and launches the Play review flow. Returns true if Play accepted the request
     * (Google may still choose not to show UI due to quota).
     */
    fun launch(activity: Activity, onComplete: (Boolean) -> Unit = {}) {
        try {
            val manager = ReviewManagerFactory.create(context)
            manager.requestReviewFlow()
                .addOnCompleteListener { request ->
                    if (!request.isSuccessful) {
                        Timber.w(request.exception, "requestReviewFlow failed")
                        onComplete(false)
                        return@addOnCompleteListener
                    }
                    manager.launchReviewFlow(activity, request.result)
                        .addOnCompleteListener { launch ->
                            if (!launch.isSuccessful) {
                                Timber.w(launch.exception, "launchReviewFlow failed")
                            }
                            onComplete(launch.isSuccessful)
                        }
                }
        } catch (e: Exception) {
            Timber.w(e, "Play Review unavailable")
            onComplete(false)
        }
    }
}
