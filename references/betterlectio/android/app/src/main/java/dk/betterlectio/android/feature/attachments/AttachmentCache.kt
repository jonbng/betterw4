package dk.betterlectio.android.feature.attachments

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import timber.log.Timber
import java.io.File
import java.security.MessageDigest
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Disk cache for authenticated Lectio downloads under `cacheDir/attachments/`.
 *
 * Filenames: `<sha256-of-url>__<sanitized-display-name>` so re-open is O(1) by URL.
 */
@Singleton
class AttachmentCache {
    private val dir: File

    @Inject
    constructor(@ApplicationContext context: Context) : this(
        File(context.cacheDir, "attachments").apply { mkdirs() },
    )

    /** Test / explicit directory constructor. */
    constructor(directory: File) {
        dir = directory.apply { mkdirs() }
    }

    fun keyFor(url: String): String = sha256Hex(url.trim())

    fun find(url: String): File? {
        val prefix = keyFor(url) + SEP
        return dir.listFiles()
            ?.firstOrNull { it.isFile && it.name.startsWith(prefix) && it.length() > 0L }
    }

    fun put(url: String, displayName: String, bytes: ByteArray): File {
        val safeName = AttachmentMime.sanitizeFileName(displayName)
        val target = File(dir, keyFor(url) + SEP + safeName)
        dir.listFiles()
            ?.filter { it.isFile && it.name.startsWith(keyFor(url) + SEP) && it != target }
            ?.forEach { it.delete() }
        target.writeBytes(bytes)
        evictIfNeeded()
        return target
    }

    fun clear() {
        try {
            dir.listFiles()?.forEach { it.delete() }
            Timber.i("Attachment cache cleared")
        } catch (e: Exception) {
            Timber.w(e, "Attachment cache clear failed")
        }
    }

    fun evictIfNeeded(
        maxBytes: Long = MAX_BYTES,
        maxFiles: Int = MAX_FILES,
    ) {
        val files = dir.listFiles()?.filter { it.isFile }?.sortedBy { it.lastModified() } ?: return
        var total = files.sumOf { it.length() }
        var count = files.size
        val mutable = files.toMutableList()
        while (mutable.isNotEmpty() && (total > maxBytes || count > maxFiles)) {
            val victim = mutable.removeAt(0)
            total -= victim.length()
            count--
            victim.delete()
        }
    }

    companion object {
        const val SEP = "__"
        const val MAX_BYTES = 50L * 1024L * 1024L
        const val MAX_FILES = 100

        fun sha256Hex(input: String): String {
            val dig = MessageDigest.getInstance("SHA-256").digest(input.toByteArray(Charsets.UTF_8))
            return dig.joinToString("") { "%02x".format(it) }
        }
    }
}
