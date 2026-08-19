package dk.betterw4.android.feature.settings

import kotlin.math.pow

/**
 * Pure subject → ARGB resolution.
 * Prefer [SettingsStore.colorForSubject] which uses live lesson mappings;
 * this helper remains for tests and callers with an explicit map.
 */
object SubjectColorResolver {
    const val SUBJECT_SATURATION = 0.62f
    const val SUBJECT_VALUE = 0.88f
    const val WHITE_ARGB = 0xFFFFFFFFL
    const val DARK_SURFACE_ARGB = 0xFF121212L
    const val MIN_TEXT_CONTRAST = 4.5f

    fun resolve(
        subjectKey: String,
        custom: Map<String, Long>,
        palette: List<Long> = SettingsStore.DEFAULT_PALETTE,
    ): Long {
        val key = subjectKey.trim()
        if (key.isEmpty()) return palette.first()
        custom[key]?.let { return it }
        val canonical = SubjectMapper.canonicalKey(key)
        if (canonical != null) {
            custom[canonical]?.let { return it }
            return hueToArgb(SubjectMapper.defaultColorHue(canonical))
        }
        return palette[kotlin.math.abs(key.hashCode()) % palette.size]
    }

    fun resolveHue(
        subjectKey: String,
        customHues: Map<String, Int> = emptyMap(),
    ): Int {
        val key = subjectKey.trim()
        if (key.isEmpty()) return 215
        customHues[key]?.let { return it }
        val canonical = SubjectMapper.canonicalKey(key)
        if (canonical != null) {
            customHues[canonical]?.let { return it }
            return SubjectMapper.defaultColorHue(canonical)
        }
        return 215
    }

    /** Convert 0–360 hue to ARGB (fixed S/V, matching the previous iOS lesson colors). */
    fun hueToArgb(hue: Int): Long = hsvToArgb(hue, SUBJECT_SATURATION, SUBJECT_VALUE)

    fun hsvToArgb(hue: Int, saturation: Float, value: Float): Long {
        val h = ((hue % 360) + 360) % 360 / 360f
        val s = saturation.coerceIn(0f, 1f)
        val v = value.coerceIn(0f, 1f)
        val i = (h * 6).toInt()
        val f = h * 6 - i
        val p = v * (1 - s)
        val q = v * (1 - f * s)
        val t = v * (1 - (1 - f) * s)
        val (r, g, b) = when (i % 6) {
            0 -> Triple(v, t, p)
            1 -> Triple(q, v, p)
            2 -> Triple(p, v, t)
            3 -> Triple(p, q, v)
            4 -> Triple(t, p, v)
            else -> Triple(v, p, q)
        }
        val ri = (r * 255).toInt().coerceIn(0, 255)
        val gi = (g * 255).toInt().coerceIn(0, 255)
        val bi = (b * 255).toInt().coerceIn(0, 255)
        return 0xFF000000L or (ri.toLong() shl 16) or (gi.toLong() shl 8) or bi.toLong()
    }

    fun argbToHue(argb: Long): Int = argbToHsv(argb).first

    fun argbToHsv(argb: Long): Triple<Int, Float, Float> {
        val r = ((argb shr 16) and 0xFF) / 255f
        val g = ((argb shr 8) and 0xFF) / 255f
        val b = (argb and 0xFF) / 255f
        val max = maxOf(r, g, b)
        val min = minOf(r, g, b)
        val d = max - min
        val s = if (max < 1e-6f) 0f else d / max
        val v = max
        if (d < 1e-6f) return Triple(0, s, v)
        val h = when (max) {
            r -> ((g - b) / d + if (g < b) 6 else 0)
            g -> (b - r) / d + 2
            else -> (r - g) / d + 4
        } / 6f
        val hue = ((h * 360f).toInt() % 360 + 360) % 360
        return Triple(hue, s, v)
    }

    fun relativeLuminance(argb: Long): Float {
        fun lin(shift: Int): Float {
            val c = ((argb shr shift) and 0xFF) / 255f
            return if (c <= 0.04045f) c / 12.92f else ((c + 0.055f) / 1.055f).pow(2.4f)
        }
        return 0.2126f * lin(16) + 0.7152f * lin(8) + 0.0722f * lin(0)
    }

    fun contrastRatio(a: Long, b: Long): Float {
        val l1 = relativeLuminance(a)
        val l2 = relativeLuminance(b)
        val light = maxOf(l1, l2)
        val dark = minOf(l1, l2)
        return (light + 0.05f) / (dark + 0.05f)
    }

    /**
     * Darken or lighten [argb] (preserving hue) until WCAG contrast against [against]
     * is at least [minRatio]. Swatch / fill colours stay on [hueToArgb]; this is for
     * text, icons, and labels sitting on a light or dark surface.
     *
     * Yellows and limes drop further than blues because they start much lighter.
     */
    fun ensureContrast(
        argb: Long,
        against: Long = WHITE_ARGB,
        minRatio: Float = MIN_TEXT_CONTRAST,
    ): Long {
        if (contrastRatio(argb, against) >= minRatio) return argb
        val (hue, saturation, value) = argbToHsv(argb)
        val darken = relativeLuminance(against) > 0.5f
        val sat = if (darken) (saturation * 1.15f).coerceAtMost(0.88f) else saturation

        var lo: Float
        var hi: Float
        var best: Long
        if (darken) {
            lo = 0.18f
            hi = value
            best = hsvToArgb(hue, sat, lo)
        } else {
            lo = value
            hi = 1f
            best = hsvToArgb(hue, sat, hi)
        }
        repeat(12) {
            val mid = (lo + hi) / 2f
            val candidate = hsvToArgb(hue, sat, mid)
            if (contrastRatio(candidate, against) >= minRatio) {
                best = candidate
                if (darken) lo = mid else hi = mid
            } else {
                if (darken) hi = mid else lo = mid
            }
        }
        return best
    }

    fun readableArgb(argb: Long, darkSurface: Boolean): Long =
        ensureContrast(argb, if (darkSurface) DARK_SURFACE_ARGB else WHITE_ARGB)
}
