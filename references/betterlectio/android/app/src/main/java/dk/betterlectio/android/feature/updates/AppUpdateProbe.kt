package dk.betterlectio.android.feature.updates

import android.app.Activity
import android.content.Context
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.UpdateAvailability
import dagger.hilt.android.qualifiers.ApplicationContext
import dk.betterlectio.android.R
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Play In-App Updates: real check when Play services present; graceful fallback otherwise.
 */
@Singleton
class AppUpdateProbe @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    data class ProbeResult(
        val attempted: Boolean,
        val available: Boolean,
        val message: String,
        val updateType: String? = null,
    )

    fun probe(): ProbeResult {
        return try {
            Class.forName("com.google.android.play.core.appupdate.AppUpdateManagerFactory")
            ProbeResult(
                attempted = true,
                available = true,
                message = context.getString(R.string.update_ready_retry_activity),
            )
        } catch (_: ClassNotFoundException) {
            ProbeResult(
                attempted = true,
                available = false,
                message = context.getString(R.string.update_not_linked),
            )
        } catch (e: Exception) {
            Timber.w(e, "App update probe failed")
            ProbeResult(
                attempted = true,
                available = false,
                message = context.getString(R.string.update_check_failed, e.message.orEmpty()),
            )
        }
    }

    /**
     * Checks Play for an update and optionally starts flexible flow.
     * Safe on non-Play devices (returns message, never crashes).
     */
    fun checkAndStart(activity: Activity, onResult: (ProbeResult) -> Unit) {
        try {
            val manager = AppUpdateManagerFactory.create(context)
            manager.appUpdateInfo
                .addOnSuccessListener { info ->
                    val available = info.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE
                    if (available && info.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE)) {
                        try {
                            manager.startUpdateFlow(
                                info,
                                activity,
                                AppUpdateOptions.newBuilder(AppUpdateType.FLEXIBLE).build(),
                            )
                            onResult(
                                ProbeResult(
                                    attempted = true,
                                    available = true,
                                    message = context.getString(R.string.update_flexible_started),
                                    updateType = "FLEXIBLE",
                                ),
                            )
                        } catch (e: Exception) {
                            onResult(
                                ProbeResult(
                                    attempted = true,
                                    available = true,
                                    message = context.getString(
                                        R.string.update_flexible_failed,
                                        e.message.orEmpty(),
                                    ),
                                    updateType = "FLEXIBLE",
                                ),
                            )
                        }
                    } else if (available && info.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE)) {
                        try {
                            manager.startUpdateFlow(
                                info,
                                activity,
                                AppUpdateOptions.newBuilder(AppUpdateType.IMMEDIATE).build(),
                            )
                            onResult(
                                ProbeResult(
                                    attempted = true,
                                    available = true,
                                    message = context.getString(R.string.update_immediate_started),
                                    updateType = "IMMEDIATE",
                                ),
                            )
                        } catch (e: Exception) {
                            onResult(
                                ProbeResult(
                                    attempted = true,
                                    available = true,
                                    message = context.getString(
                                        R.string.update_immediate_failed,
                                        e.message.orEmpty(),
                                    ),
                                ),
                            )
                        }
                    } else {
                        onResult(
                            ProbeResult(
                                attempted = true,
                                available = false,
                                message = context.getString(
                                    R.string.update_none_available,
                                    appVersionName(),
                                ),
                            ),
                        )
                    }
                }
                .addOnFailureListener { e ->
                    Timber.w(e, "appUpdateInfo failed")
                    onResult(
                        ProbeResult(
                            attempted = true,
                            available = false,
                            message = context.getString(
                                R.string.update_play_check_failed,
                                e.message.orEmpty(),
                            ),
                        ),
                    )
                }
        } catch (e: Exception) {
            onResult(
                ProbeResult(
                    attempted = true,
                    available = false,
                    message = context.getString(
                        R.string.update_play_core_unavailable,
                        e.message.orEmpty(),
                    ),
                ),
            )
        }
    }

    fun appVersionName(): String =
        try {
            context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: "1.0"
        } catch (_: Exception) {
            "1.0"
        }
}
