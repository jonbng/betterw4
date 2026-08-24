package dk.betterw4.android.core.analytics

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.core.content.edit

/** Reports crashes and ANRs that Android recorded after the previous process could no longer run. */
object PreviousExitReporter {
    private const val PREFS_NAME = "process_exit_telemetry"
    private const val LAST_SEEN_TIMESTAMP = "last_seen_timestamp"

    fun report(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return

        val preferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val lastSeen = preferences.getLong(LAST_SEEN_TIMESTAMP, 0L)
        val activityManager = context.getSystemService(ActivityManager::class.java) ?: return
        val exits = runCatching {
            activityManager.getHistoricalProcessExitReasons(context.packageName, 0, 20)
        }.getOrDefault(emptyList())

        var newestTimestamp = lastSeen
        exits.sortedBy { it.timestamp }.forEach { exit ->
            if (exit.timestamp <= lastSeen) return@forEach
            newestTimestamp = maxOf(newestTimestamp, exit.timestamp)
            val reason = exit.telemetryReason() ?: return@forEach
            AppTelemetry.capture(
                "app_previous_exit",
                mapOf(
                    "reason" to reason,
                    "importance" to exit.importance,
                    "pss_bytes" to exit.pss,
                    "rss_bytes" to exit.rss,
                ),
            )
        }

        if (newestTimestamp > lastSeen) {
            preferences.edit { putLong(LAST_SEEN_TIMESTAMP, newestTimestamp) }
        }
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private fun ApplicationExitInfo.telemetryReason(): String? = when (reason) {
        ApplicationExitInfo.REASON_ANR -> "anr"
        ApplicationExitInfo.REASON_CRASH -> "java_crash"
        ApplicationExitInfo.REASON_CRASH_NATIVE -> "native_crash"
        else -> null
    }
}
