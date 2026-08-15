package dk.betterlectio.android.feature.feedback

import timber.log.Timber
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.ConcurrentLinkedDeque
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Ring buffer of recent Timber lines for bug reports.
 * Thread-safe; planted once from [dk.betterlectio.android.BetterLectioApp].
 */
@Singleton
class FeedbackLogBuffer @Inject constructor() : Timber.Tree() {

    private val lines = ConcurrentLinkedDeque<String>()

    @Volatile
    private var capacity: Int = DEFAULT_CAPACITY

    private val timeFormat = ThreadLocal.withInitial {
        SimpleDateFormat("HH:mm:ss.SSS", Locale.US)
    }

    override fun log(priority: Int, tag: String?, message: String, t: Throwable?) {
        // Timber.Tree's public `log(priority, message, *args)` overloads are not this method —
        // use [record] from tests or other non-Timber call sites.
        record(priority, tag, message, t)
    }

    /** Append a log line (same formatting as Timber). Prefer Timber in app code. */
    fun record(priority: Int, tag: String?, message: String, t: Throwable? = null) {
        val level = when (priority) {
            android.util.Log.VERBOSE -> "V"
            android.util.Log.DEBUG -> "D"
            android.util.Log.INFO -> "I"
            android.util.Log.WARN -> "W"
            android.util.Log.ERROR -> "E"
            android.util.Log.ASSERT -> "A"
            else -> "?"
        }
        val ts = timeFormat.get()?.format(Date()) ?: ""
        val tagPart = tag?.takeIf { it.isNotBlank() }?.let { " $it" }.orEmpty()
        val base = "$ts $level$tagPart: $message"
        val line = if (t != null) {
            val stack = t.stackTraceToString().lineSequence().take(12).joinToString("\n")
            "$base\n$stack"
        } else {
            base
        }
        // Cap individual entries so one huge dump cannot fill the buffer alone.
        val clipped = if (line.length > MAX_LINE_CHARS) {
            line.take(MAX_LINE_CHARS) + "…[truncated]"
        } else {
            line
        }
        lines.addLast(clipped)
        while (lines.size > capacity) {
            lines.pollFirst()
        }
    }

    /** Newest-last dump for inclusion in a feedback payload. */
    fun snapshot(maxChars: Int = MAX_SNAPSHOT_CHARS): String {
        val joined = lines.joinToString("\n")
        if (joined.length <= maxChars) return joined
        return "…[older logs truncated]\n" + joined.takeLast(maxChars)
    }

    fun clear() {
        lines.clear()
    }

    /** Test / tuning hook. */
    fun setCapacity(value: Int) {
        capacity = value.coerceAtLeast(1)
        while (lines.size > capacity) {
            lines.pollFirst()
        }
    }

    fun size(): Int = lines.size

    companion object {
        const val DEFAULT_CAPACITY = 250
        const val MAX_LINE_CHARS = 2_000
        const val MAX_SNAPSHOT_CHARS = 24_000
    }
}
