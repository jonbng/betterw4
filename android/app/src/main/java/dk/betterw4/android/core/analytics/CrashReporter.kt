package dk.betterw4.android.core.analytics

import android.content.Context
import android.util.AtomicFile
import android.util.Log
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.atomic.AtomicBoolean

/** Persists fatal Java crashes before Android terminates the app and replays them next launch. */
object CrashReporter {
    private const val CRASH_FILE_NAME = "crash_log.json"
    private val handlingCrash = AtomicBoolean(false)

    fun install(context: Context) {
        val applicationContext = context.applicationContext
        val previousHandler = Thread.getDefaultUncaughtExceptionHandler()

        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            if (handlingCrash.compareAndSet(false, true)) {
                val properties = crashProperties(throwable, System.currentTimeMillis())

                // Disk is the reliable path: PostHog's flush is best-effort while the process dies.
                persist(applicationContext, properties)
                AppTelemetry.capture("app_crash", properties)
                AppTelemetry.flush()
            }

            previousHandler?.uncaughtException(thread, throwable)
        }
    }

    fun reportPendingCrash(context: Context) {
        val crashFile = AtomicFile(File(context.filesDir, CRASH_FILE_NAME))
        if (!crashFile.baseFile.isFile) return

        val properties = runCatching {
            val json = JSONObject(
                crashFile.openRead().bufferedReader().use { it.readText() },
            )
            buildMap<String, Any> {
                put("exception_class", json.getString("exception_class"))
                put("exception_message", json.optString("exception_message"))
                put("stack_trace", json.getString("stack_trace"))
                put("timestamp", json.getLong("timestamp"))
            }
        }.getOrNull()

        if (properties == null) {
            // A partial/corrupt record cannot become reportable by retrying every launch.
            crashFile.delete()
            return
        }

        if (AppTelemetry.capture("app_crash_report", properties)) {
            AppTelemetry.flush()
            crashFile.delete()
        }
    }

    private fun crashProperties(throwable: Throwable, timestamp: Long): Map<String, Any> = mapOf(
        "exception_class" to throwable.javaClass.name,
        "exception_message" to throwable.message.orEmpty(),
        "stack_trace" to Log.getStackTraceString(throwable),
        "timestamp" to timestamp,
    )

    private fun persist(context: Context, properties: Map<String, Any>) {
        val crashFile = AtomicFile(File(context.filesDir, CRASH_FILE_NAME))
        var output: FileOutputStream? = null
        runCatching {
            val json = JSONObject(properties).toString()
            val stream = crashFile.startWrite()
            output = stream
            stream.write(json.toByteArray(Charsets.UTF_8))
            crashFile.finishWrite(stream)
            output = null
        }.onFailure {
            output?.let(crashFile::failWrite)
        }
    }
}
