package dk.betterlectio.android.feature.attachments

import java.util.Locale

/**
 * MIME / extension helpers for Lectio attachments.
 */
object AttachmentMime {

    private val extensionMime: Map<String, String> = mapOf(
        "pdf" to "application/pdf",
        "doc" to "application/msword",
        "docx" to "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "xls" to "application/vnd.ms-excel",
        "xlsx" to "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "ppt" to "application/vnd.ms-powerpoint",
        "pptx" to "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        "odt" to "application/vnd.oasis.opendocument.text",
        "ods" to "application/vnd.oasis.opendocument.spreadsheet",
        "odp" to "application/vnd.oasis.opendocument.presentation",
        "txt" to "text/plain",
        "rtf" to "application/rtf",
        "csv" to "text/csv",
        "html" to "text/html",
        "htm" to "text/html",
        "jpg" to "image/jpeg",
        "jpeg" to "image/jpeg",
        "png" to "image/png",
        "gif" to "image/gif",
        "webp" to "image/webp",
        "bmp" to "image/bmp",
        "heic" to "image/heic",
        "svg" to "image/svg+xml",
        "zip" to "application/zip",
        "rar" to "application/vnd.rar",
        "7z" to "application/x-7z-compressed",
        "mp3" to "audio/mpeg",
        "mp4" to "video/mp4",
        "mov" to "video/quicktime",
        "pages" to "application/vnd.apple.pages",
        "numbers" to "application/vnd.apple.numbers",
        "key" to "application/vnd.apple.keynote",
    )

    private val imageExtensions = setOf(
        "jpg", "jpeg", "png", "gif", "webp", "bmp", "heic", "svg",
    )

    private val knownFileExtensions = extensionMime.keys

    fun extensionOf(nameOrUrl: String): String? {
        val cleaned = nameOrUrl
            .substringBefore('?')
            .substringBefore('#')
            .trim()
            .substringAfterLast('/')
        val dot = cleaned.lastIndexOf('.')
        if (dot < 0 || dot == cleaned.lastIndex) return null
        val ext = cleaned.substring(dot + 1).lowercase(Locale.ROOT)
        return ext.takeIf { it.length in 1..8 && it.all { c -> c.isLetterOrDigit() } }
    }

    fun mimeFromExtension(ext: String?): String? =
        ext?.lowercase(Locale.ROOT)?.let { extensionMime[it] }

    fun mimeFromNameOrUrl(nameOrUrl: String): String? =
        mimeFromExtension(extensionOf(nameOrUrl))

    fun isImageExtension(ext: String?): Boolean =
        ext != null && ext.lowercase(Locale.ROOT) in imageExtensions

    fun isKnownFileExtension(ext: String?): Boolean =
        ext != null && ext.lowercase(Locale.ROOT) in knownFileExtensions

    fun isImageMime(mime: String?): Boolean =
        mime?.lowercase(Locale.ROOT)?.startsWith("image/") == true

    /**
     * Strip parameters (`application/pdf; charset=binary` → `application/pdf`).
     */
    fun normalizeContentType(raw: String?): String? {
        if (raw.isNullOrBlank()) return null
        return raw.substringBefore(';').trim().lowercase(Locale.ROOT).takeIf { it.isNotBlank() }
    }

    /**
     * Best-effort MIME from name, Content-Type header, then magic bytes.
     */
    fun resolve(
        displayName: String,
        contentTypeHeader: String?,
        bytes: ByteArray,
    ): String {
        mimeFromNameOrUrl(displayName)?.let { return it }
        normalizeContentType(contentTypeHeader)
            ?.takeIf { it != "application/octet-stream" && !it.startsWith("text/html") }
            ?.let { return it }
        sniff(bytes)?.let { return it }
        return normalizeContentType(contentTypeHeader) ?: "application/octet-stream"
    }

    fun sniff(bytes: ByteArray): String? {
        if (bytes.isEmpty()) return null
        // PDF
        if (bytes.size >= 4 &&
            bytes[0] == 0x25.toByte() && bytes[1] == 0x50.toByte() &&
            bytes[2] == 0x44.toByte() && bytes[3] == 0x46.toByte()
        ) {
            return "application/pdf"
        }
        // PNG
        if (bytes.size >= 8 &&
            bytes[0] == 0x89.toByte() && bytes[1] == 0x50.toByte() &&
            bytes[2] == 0x4E.toByte() && bytes[3] == 0x47.toByte()
        ) {
            return "image/png"
        }
        // JPEG
        if (bytes.size >= 3 &&
            bytes[0] == 0xFF.toByte() && bytes[1] == 0xD8.toByte() && bytes[2] == 0xFF.toByte()
        ) {
            return "image/jpeg"
        }
        // GIF
        if (bytes.size >= 6) {
            val g = String(bytes, 0, 6, Charsets.US_ASCII)
            if (g == "GIF87a" || g == "GIF89a") return "image/gif"
        }
        // WEBP (RIFF....WEBP)
        if (bytes.size >= 12 &&
            bytes[0] == 'R'.code.toByte() && bytes[1] == 'I'.code.toByte() &&
            bytes[2] == 'F'.code.toByte() && bytes[3] == 'F'.code.toByte() &&
            bytes[8] == 'W'.code.toByte() && bytes[9] == 'E'.code.toByte() &&
            bytes[10] == 'B'.code.toByte() && bytes[11] == 'P'.code.toByte()
        ) {
            return "image/webp"
        }
        // ZIP / Office Open XML
        if (bytes.size >= 4 &&
            bytes[0] == 0x50.toByte() && bytes[1] == 0x4B.toByte() &&
            (bytes[2] == 0x03.toByte() || bytes[2] == 0x05.toByte() || bytes[2] == 0x07.toByte()) &&
            (bytes[3] == 0x04.toByte() || bytes[3] == 0x06.toByte() || bytes[3] == 0x08.toByte())
        ) {
            return "application/zip"
        }
        return null
    }

    /**
     * Parse filename from Content-Disposition.
     * Supports `filename="x.pdf"` and `filename*=UTF-8''x.pdf`.
     */
    fun filenameFromContentDisposition(header: String?): String? {
        if (header.isNullOrBlank()) return null
        val star = Regex(
            """filename\*\s*=\s*(?:UTF-8''|utf-8'')([^;]+)""",
            RegexOption.IGNORE_CASE,
        ).find(header)
        if (star != null) {
            val raw = star.groupValues[1].trim().trim('"', '\'')
            return runCatching {
                java.net.URLDecoder.decode(raw, Charsets.UTF_8.name())
            }.getOrDefault(raw).takeIf { it.isNotBlank() }
        }
        val plain = Regex(
            """filename\s*=\s*("?)([^";]+)\1""",
            RegexOption.IGNORE_CASE,
        ).find(header)
        return plain?.groupValues?.get(2)?.trim()?.takeIf { it.isNotBlank() }
    }

    fun sanitizeFileName(name: String, fallback: String = "attachment"): String {
        val cleaned = name
            .replace(Regex("""[\\/:*?"<>|\u0000-\u001F]"""), "_")
            .trim()
            .trim('.')
        return cleaned.take(120).ifBlank { fallback }
    }

    fun ensureExtension(fileName: String, mime: String): String {
        if (extensionOf(fileName) != null) return fileName
        val ext = when (mime.lowercase(Locale.ROOT)) {
            "application/pdf" -> "pdf"
            "image/jpeg" -> "jpg"
            "image/png" -> "png"
            "image/gif" -> "gif"
            "image/webp" -> "webp"
            "application/msword" -> "doc"
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document" -> "docx"
            "application/vnd.ms-excel" -> "xls"
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" -> "xlsx"
            "application/vnd.ms-powerpoint" -> "ppt"
            "application/vnd.openxmlformats-officedocument.presentationml.presentation" -> "pptx"
            "application/zip" -> "zip"
            "text/plain" -> "txt"
            else -> null
        } ?: return fileName
        return "$fileName.$ext"
    }
}
