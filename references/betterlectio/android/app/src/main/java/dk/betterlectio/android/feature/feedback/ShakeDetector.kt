package dk.betterlectio.android.feature.feedback

import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import kotlin.math.sqrt

/**
 * Deliberate shake detector (accelerometer).
 *
 * A single jolt or wrist twist is not enough — the user must produce several
 * hard acceleration peaks inside a short window (think vigorous up-and-down).
 * Call [start]/[stop] from the Activity lifecycle (or Compose DisposableEffect).
 */
class ShakeDetector(
    private val sensorManager: SensorManager,
    private val onShake: () -> Unit,
    private val accelerationThreshold: Float = DEFAULT_THRESHOLD,
    private val requiredPeaks: Int = DEFAULT_REQUIRED_PEAKS,
    private val windowMs: Long = DEFAULT_WINDOW_MS,
    private val minPeakGapMs: Long = DEFAULT_MIN_PEAK_GAP_MS,
    private val cooldownMs: Long = DEFAULT_COOLDOWN_MS,
) : SensorEventListener {

    private val accelerometer: Sensor? =
        sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)

    private val tracker = ShakeGestureTracker(
        accelerationThreshold = accelerationThreshold,
        requiredPeaks = requiredPeaks,
        windowMs = windowMs,
        minPeakGapMs = minPeakGapMs,
        cooldownMs = cooldownMs,
    )

    private var lastX = 0f
    private var lastY = 0f
    private var lastZ = 0f
    private var lastSampleAt = 0L
    private var seeded = false

    fun start() {
        val sensor = accelerometer ?: return
        sensorManager.registerListener(this, sensor, SensorManager.SENSOR_DELAY_UI)
    }

    fun stop() {
        sensorManager.unregisterListener(this)
        seeded = false
        tracker.reset()
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    override fun onSensorChanged(event: SensorEvent?) {
        if (event?.sensor?.type != Sensor.TYPE_ACCELEROMETER) return
        val now = System.currentTimeMillis()
        val x = event.values[0]
        val y = event.values[1]
        val z = event.values[2]

        if (!seeded) {
            lastX = x
            lastY = y
            lastZ = z
            lastSampleAt = now
            seeded = true
            return
        }

        val dt = now - lastSampleAt
        if (dt < MIN_SAMPLE_INTERVAL_MS) return
        lastSampleAt = now

        val dx = x - lastX
        val dy = y - lastY
        val dz = z - lastZ
        lastX = x
        lastY = y
        lastZ = z

        // Scaled delta-g / Δt heuristic — not raw m/s². Tune by feel on device.
        val speed = sqrt((dx * dx + dy * dy + dz * dz).toDouble()).toFloat() / dt * 10_000f
        if (tracker.onSpeed(now, speed)) {
            onShake()
        }
    }

    companion object {
        /**
         * Higher = harder. Still above the old single-jolt threshold (1200), but easier
         * than the confirm-chip-era peak — chip is the intentionality gate now.
         */
        const val DEFAULT_THRESHOLD = 1_800f
        /** Peaks needed inside [DEFAULT_WINDOW_MS] before we fire. */
        const val DEFAULT_REQUIRED_PEAKS = 3
        const val DEFAULT_WINDOW_MS = 1_200L
        /** Ignore samples that are just the same physical jolt re-read. */
        const val DEFAULT_MIN_PEAK_GAP_MS = 90L
        const val DEFAULT_COOLDOWN_MS = 2_800L
        private const val MIN_SAMPLE_INTERVAL_MS = 60L
    }
}

/**
 * Pure peak/window/cooldown logic — unit-testable without a SensorManager.
 *
 * Returns true from [onSpeed] exactly when a full deliberate shake completes.
 */
class ShakeGestureTracker(
    private val accelerationThreshold: Float = ShakeDetector.DEFAULT_THRESHOLD,
    private val requiredPeaks: Int = ShakeDetector.DEFAULT_REQUIRED_PEAKS,
    private val windowMs: Long = ShakeDetector.DEFAULT_WINDOW_MS,
    private val minPeakGapMs: Long = ShakeDetector.DEFAULT_MIN_PEAK_GAP_MS,
    private val cooldownMs: Long = ShakeDetector.DEFAULT_COOLDOWN_MS,
) {
    private var peakCount = 0
    private var windowStartedAt = 0L
    private var lastPeakAt = 0L
    private var lastTriggeredAt = Long.MIN_VALUE / 2

    fun reset() {
        peakCount = 0
        windowStartedAt = 0L
        lastPeakAt = 0L
    }

    fun onSpeed(now: Long, speed: Float): Boolean {
        if (speed < accelerationThreshold) return false
        if (now - lastTriggeredAt < cooldownMs) return false
        if (peakCount > 0 && now - lastPeakAt < minPeakGapMs) return false

        if (peakCount == 0 || now - windowStartedAt > windowMs) {
            peakCount = 1
            windowStartedAt = now
            lastPeakAt = now
            return false
        }

        peakCount += 1
        lastPeakAt = now

        if (peakCount < requiredPeaks) return false

        lastTriggeredAt = now
        reset()
        return true
    }
}
