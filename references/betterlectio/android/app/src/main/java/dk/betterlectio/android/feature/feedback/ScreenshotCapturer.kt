package dk.betterlectio.android.feature.feedback

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.PixelCopy
import android.view.View
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.math.roundToInt

/**
 * Captures the current activity window as a downscaled JPEG-friendly bitmap.
 * Prefers [PixelCopy] (accurate for hardware layers); falls back to software draw.
 */
object ScreenshotCapturer {

    suspend fun capture(activity: Activity, maxWidth: Int = DEFAULT_MAX_WIDTH): Bitmap? {
        val window = activity.window ?: return null
        val decor = window.decorView
        val width = decor.width
        val height = decor.height
        if (width <= 0 || height <= 0) {
            // Layout not ready — try content root sizes.
            val content = activity.findViewById<View>(android.R.id.content) ?: return null
            if (content.width <= 0 || content.height <= 0) return null
            return captureViewSoftware(content, maxWidth)
        }

        val full = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            capturePixelCopy(activity, width, height) ?: captureViewSoftware(decor, maxWidth)
        } else {
            captureViewSoftware(decor, maxWidth)
        } ?: return null

        return scaleDown(full, maxWidth)
    }

    private suspend fun capturePixelCopy(
        activity: Activity,
        width: Int,
        height: Int,
    ): Bitmap? = suspendCancellableCoroutine { cont ->
        val bitmap = try {
            Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        } catch (_: OutOfMemoryError) {
            cont.resume(null)
            return@suspendCancellableCoroutine
        }
        val window = activity.window
        if (window == null) {
            cont.resume(null)
            return@suspendCancellableCoroutine
        }
        try {
            PixelCopy.request(
                window,
                bitmap,
                { result ->
                    if (result == PixelCopy.SUCCESS) {
                        cont.resume(bitmap)
                    } else {
                        bitmap.recycle()
                        cont.resume(null)
                    }
                },
                Handler(Looper.getMainLooper()),
            )
        } catch (_: Throwable) {
            bitmap.recycle()
            cont.resume(null)
        }
    }

    private fun captureViewSoftware(view: View, maxWidth: Int): Bitmap? {
        return try {
            val w = view.width
            val h = view.height
            if (w <= 0 || h <= 0) return null
            val full = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(full)
            view.draw(canvas)
            scaleDown(full, maxWidth)
        } catch (_: OutOfMemoryError) {
            null
        } catch (_: Throwable) {
            null
        }
    }

    private fun scaleDown(source: Bitmap, maxWidth: Int): Bitmap {
        if (source.width <= maxWidth) return source
        val ratio = maxWidth.toFloat() / source.width
        val targetH = (source.height * ratio).roundToInt().coerceAtLeast(1)
        val scaled = try {
            Bitmap.createScaledBitmap(source, maxWidth, targetH, true)
        } catch (_: OutOfMemoryError) {
            return source
        }
        if (scaled !== source) {
            source.recycle()
        }
        return scaled
    }

    const val DEFAULT_MAX_WIDTH = 720
}
