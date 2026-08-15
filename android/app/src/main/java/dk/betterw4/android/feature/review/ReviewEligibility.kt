package dk.betterw4.android.feature.review

import android.content.Context
import android.content.pm.PackageManager
import dagger.hilt.android.qualifiers.ApplicationContext
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import javax.inject.Inject
import javax.inject.Singleton

enum class ReviewTrigger(val analyticsName: String) {
    HomeworkDone("homework_done"),
    ScheduleLoaded("schedule_loaded"),
    PrivateEventCreated("private_event_created"),
    MessageSent("message_sent"),
}

/**
 * Pure eligibility checks for the soft rating pre-filter.
 */
@Singleton
class ReviewEligibility @Inject constructor(
    @ApplicationContext private val context: Context,
    private val store: ReviewPromptStore,
) {
    fun isEligible(
        now: Instant = Instant.now(),
        zone: ZoneId = ZoneId.systemDefault(),
        sessionStartedAt: Instant?,
        lastErrorAt: Instant?,
    ): Boolean {
        if (store.neverAsk() || store.completedPlayFlow()) return false
        if (store.promptCount() >= MAX_LIFETIME_PROMPTS) return false
        if (!installedLongEnough(now)) return false
        if (store.launchCountInWindow(now) < MIN_LAUNCHES_IN_WINDOW) {
            return false
        }
        if (!inPromptWindow(LocalTime.ofInstant(now, zone), LocalDate.ofInstant(now, zone).dayOfWeek)) {
            return false
        }
        if (!cooldownElapsed(now)) return false
        if (!sessionCalm(now, sessionStartedAt, lastErrorAt)) return false
        return true
    }

    fun installedLongEnough(now: Instant = Instant.now()): Boolean {
        val installedAt = firstInstallInstant() ?: return false
        return ChronoUnit.DAYS.between(installedAt, now) >= MIN_INSTALL_AGE_DAYS
    }

    private fun firstInstallInstant(): Instant? {
        return try {
            val info = context.packageManager.getPackageInfo(context.packageName, 0)
            Instant.ofEpochMilli(info.firstInstallTime)
        } catch (_: PackageManager.NameNotFoundException) {
            null
        }
    }

    private fun inPromptWindow(time: LocalTime, day: DayOfWeek): Boolean {
        if (day !in PROMPT_WEEKDAYS) return false
        val hour = time.hour
        return hour in PROMPT_HOUR_START until PROMPT_HOUR_END
    }

    private fun cooldownElapsed(now: Instant): Boolean {
        val last = store.lastPromptAtMillis()
        if (last <= 0L) return true
        val elapsedDays = ChronoUnit.DAYS.between(Instant.ofEpochMilli(last), now)
        return elapsedDays >= COOLDOWN_DAYS
    }

    private fun sessionCalm(
        now: Instant,
        sessionStartedAt: Instant?,
        lastErrorAt: Instant?,
    ): Boolean {
        if (sessionStartedAt == null) return false
        if (ChronoUnit.SECONDS.between(sessionStartedAt, now) < MIN_SESSION_SECONDS) return false
        if (lastErrorAt != null &&
            ChronoUnit.SECONDS.between(lastErrorAt, now) < ERROR_COOLDOWN_SECONDS
        ) {
            return false
        }
        return true
    }

    companion object {
        const val MIN_INSTALL_AGE_DAYS = 14L
        const val MIN_LAUNCHES_IN_WINDOW = 8
        const val PROMPT_HOUR_START = 16
        const val PROMPT_HOUR_END = 21
        const val COOLDOWN_DAYS = 90L
        const val MAX_LIFETIME_PROMPTS = 3
        const val MIN_SESSION_SECONDS = 30L
        const val ERROR_COOLDOWN_SECONDS = 60L
        val PROMPT_WEEKDAYS = setOf(
            DayOfWeek.MONDAY,
            DayOfWeek.TUESDAY,
            DayOfWeek.WEDNESDAY,
            DayOfWeek.THURSDAY,
        )
    }
}
