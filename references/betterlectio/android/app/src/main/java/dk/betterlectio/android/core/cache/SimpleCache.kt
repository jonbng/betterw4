package dk.betterlectio.android.core.cache

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

/**
 * File-backed string cache for Lectio HTML/JSON payloads (offline-readable).
 */
@Singleton
class SimpleCache @Inject constructor(
    @ApplicationContext context: Context,
) {
    private val dir = File(context.filesDir, "lectio_cache").also { it.mkdirs() }

    fun put(key: String, value: String) {
        safeFile(key).writeText(value)
    }

    fun get(key: String): String? {
        val f = safeFile(key)
        if (!f.exists()) return null
        return f.readText()
    }

    fun getWithMeta(key: String): CachedValue? {
        val f = safeFile(key)
        if (!f.exists()) return null
        return CachedValue(f.readText(), f.lastModified())
    }

    fun remove(key: String) {
        safeFile(key).delete()
    }

    fun clearAll() {
        dir.listFiles()?.forEach { it.deleteRecursively() }
    }

    private fun safeFile(key: String): File {
        val safe = key.replace(Regex("[^a-zA-Z0-9._-]"), "_")
        return File(dir, safe)
    }
}

data class CachedValue(val value: String, val updatedAtMs: Long)
