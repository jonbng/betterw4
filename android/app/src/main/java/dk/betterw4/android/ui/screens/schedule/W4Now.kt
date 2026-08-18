package dk.betterw4.android.ui.screens.schedule

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import dk.betterw4.android.core.w4.W4Dates
import kotlinx.coroutines.delay
import java.time.LocalDateTime

/**
 * Oslo wall-clock that jumps at the start of every Europe/Oslo minute and
 * again the moment the screen comes back to the foreground. The now-line and
 * the live header must share this so they can never disagree.
 */
@Composable
fun rememberW4Now(): LocalDateTime {
    var now by remember { mutableStateOf(W4Dates.now()) }
    val lifecycleOwner = LocalLifecycleOwner.current
    LaunchedEffect(lifecycleOwner) {
        lifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
            while (true) {
                now = W4Dates.now()
                delay(W4Dates.millisUntilNextMinute())
            }
        }
    }
    return now
}

/** Pure placement of the red now-line on a day's timeline. */
internal object ScheduleNowLine {
    /**
     * Minutes below the timeline origin, or `null` when the line must not
     * draw: a different Oslo day, or a time above / past the painted span.
     */
    fun minutesFromOrigin(
        now: LocalDateTime,
        date: java.time.LocalDate,
        originHour: Int,
        spanMinutes: Int,
    ): Int? {
        if (now.toLocalDate() != date) return null
        val minutes = now.hour * 60 + now.minute - originHour * 60
        if (minutes !in 0 until spanMinutes) return null
        return minutes
    }
}
