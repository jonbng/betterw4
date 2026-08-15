package dk.betterw4.android.feature.review

import android.content.Context
import androidx.core.content.edit
import dagger.hilt.android.qualifiers.ApplicationContext
import java.time.Instant
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Persists launch timestamps and rating-prompt anti-spam flags.
 */
@Singleton
class ReviewPromptStore @Inject constructor(
    @ApplicationContext context: Context,
) {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /**
     * Records one authenticated launch (caller ensures at most once per process).
     * Prunes launches older than [LAUNCH_WINDOW_DAYS].
     */
    fun recordLaunch(now: Instant = Instant.now()) {
        val cutoff = now.toEpochMilli() - LAUNCH_WINDOW_MS
        val pruned = launchTimestampsMs()
            .filter { it >= cutoff }
            .toMutableList()
        pruned.add(now.toEpochMilli())
        prefs.edit { putString(KEY_LAUNCH_TIMESTAMPS, pruned.joinToString(",")) }
    }

    fun launchCountInWindow(now: Instant = Instant.now()): Int {
        val cutoff = now.toEpochMilli() - LAUNCH_WINDOW_MS
        return launchTimestampsMs().count { it >= cutoff }
    }

    fun promptCount(): Int = prefs.getInt(KEY_PROMPT_COUNT, 0)

    fun lastPromptAtMillis(): Long = prefs.getLong(KEY_LAST_PROMPT_AT, 0L)

    fun completedPlayFlow(): Boolean = prefs.getBoolean(KEY_COMPLETED_PLAY, false)

    fun neverAsk(): Boolean = prefs.getBoolean(KEY_NEVER_ASK, false)

    fun markSoftPromptShown(now: Instant = Instant.now()) {
        prefs.edit {
            putInt(KEY_PROMPT_COUNT, promptCount() + 1)
            putLong(KEY_LAST_PROMPT_AT, now.toEpochMilli())
        }
    }

    fun markPlayFlowRequested() {
        prefs.edit {
            putBoolean(KEY_COMPLETED_PLAY, true)
            putBoolean(KEY_NEVER_ASK, true)
        }
    }

    fun markNeverAsk() {
        prefs.edit { putBoolean(KEY_NEVER_ASK, true) }
    }

    private fun launchTimestampsMs(): List<Long> {
        val raw = prefs.getString(KEY_LAUNCH_TIMESTAMPS, null).orEmpty()
        if (raw.isBlank()) return emptyList()
        return raw.split(',')
            .mapNotNull { it.trim().toLongOrNull() }
    }

    companion object {
        const val LAUNCH_WINDOW_DAYS = 14L
        private val LAUNCH_WINDOW_MS = LAUNCH_WINDOW_DAYS * 24L * 60L * 60L * 1000L
        private const val PREFS = "bl_review_prompt"
        private const val KEY_LAUNCH_TIMESTAMPS = "launch_timestamps"
        private const val KEY_PROMPT_COUNT = "prompt_count"
        private const val KEY_LAST_PROMPT_AT = "last_prompt_at"
        private const val KEY_COMPLETED_PLAY = "completed_play_flow"
        private const val KEY_NEVER_ASK = "never_ask"
    }
}
