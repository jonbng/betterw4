package dk.betterw4.android.core.analytics

import android.os.SystemClock
import android.view.Choreographer

/** Lightweight foreground-only detector for main-thread stalls severe enough to be user-visible. */
class UiStallMonitor(
    private val report: (Long) -> Unit = AppTelemetry::reportSevereUiStall,
) : Choreographer.FrameCallback {
    private var running = false
    private var previousFrameNanos = 0L
    private var lastReportAtMs = 0L

    fun start() {
        if (running) return
        running = true
        previousFrameNanos = 0L
        Choreographer.getInstance().postFrameCallback(this)
    }

    fun stop() {
        running = false
        previousFrameNanos = 0L
        Choreographer.getInstance().removeFrameCallback(this)
    }

    override fun doFrame(frameTimeNanos: Long) {
        if (!running) return
        if (previousFrameNanos != 0L) {
            val durationMs = (frameTimeNanos - previousFrameNanos) / 1_000_000L
            val now = SystemClock.elapsedRealtime()
            if (durationMs >= AppTelemetry.SEVERE_UI_STALL_THRESHOLD_MS &&
                (lastReportAtMs == 0L || now - lastReportAtMs >= REPORT_COOLDOWN_MS)
            ) {
                lastReportAtMs = now
                report(durationMs)
            }
        }
        previousFrameNanos = frameTimeNanos
        Choreographer.getInstance().postFrameCallback(this)
    }

    private companion object {
        const val REPORT_COOLDOWN_MS = 60_000L
    }
}
