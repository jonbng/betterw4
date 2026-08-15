package dk.betterw4.android.feature.settings

/**
 * Pure subject → ARGB resolution.
 * Prefer [SettingsStore.colorForSubject] which uses live lesson mappings;
 * this helper remains for tests and callers with an explicit map.
 */
object SubjectColorResolver {
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
    fun hueToArgb(hue: Int): Long {
        val h = ((hue % 360) + 360) % 360 / 360f
        val s = 0.62f
        val v = 0.88f
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

    fun argbToHue(argb: Long): Int {
        val r = ((argb shr 16) and 0xFF) / 255f
        val g = ((argb shr 8) and 0xFF) / 255f
        val b = (argb and 0xFF) / 255f
        val max = maxOf(r, g, b)
        val min = minOf(r, g, b)
        val d = max - min
        if (d < 1e-6f) return 0
        val h = when (max) {
            r -> ((g - b) / d + if (g < b) 6 else 0)
            g -> (b - r) / d + 2
            else -> (r - g) / d + 4
        } / 6f
        return ((h * 360f).toInt() % 360 + 360) % 360
    }
}
