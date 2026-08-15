package dk.betterlectio.android.feature.attachments

import java.util.Locale

/**
 * Decide whether a resource should be downloaded with the Lectio session or opened as a web link.
 */
object AttachmentClassifier {

    fun classify(ref: AttachmentRef): AttachmentKind {
        val url = ref.url.trim()
        val name = ref.name.trim()
        val lowerUrl = url.lowercase(Locale.ROOT)
        val ext = AttachmentMime.extensionOf(name)
            ?: AttachmentMime.extensionOf(url)

        if (AttachmentMime.isImageExtension(ext)) {
            return AttachmentKind.IMAGE
        }

        val lectio = isLectioUrl(lowerUrl)
        val fileSignals =
            ref.isFileHint ||
                lowerUrl.contains("getfile", ignoreCase = true) ||
                lowerUrl.contains("documentid", ignoreCase = true) ||
                lowerUrl.contains("showdocument", ignoreCase = true) ||
                AttachmentMime.isKnownFileExtension(ext)

        return when {
            fileSignals && AttachmentMime.isImageExtension(ext) -> AttachmentKind.IMAGE
            fileSignals && lectio -> AttachmentKind.FILE
            fileSignals && !lectio -> {
                // Non-Lectio direct file URL — still download-or-open via system when possible.
                // Prefer WEB_LINK for external hosts (no auth); browser handles it.
                AttachmentKind.WEB_LINK
            }
            lectio && looksLikeHtmlPage(lowerUrl) -> AttachmentKind.WEB_LINK
            lectio && fileSignals -> AttachmentKind.FILE
            else -> AttachmentKind.WEB_LINK
        }
    }

    fun isLectioUrl(url: String): Boolean {
        val lower = url.lowercase(Locale.ROOT)
        return lower.contains("lectio.dk") ||
            lower.startsWith("/lectio/") ||
            (lower.startsWith("/") && !lower.startsWith("//"))
    }

    private fun looksLikeHtmlPage(lowerUrl: String): Boolean {
        if (lowerUrl.contains("getfile") || lowerUrl.contains("documentid")) return false
        return lowerUrl.contains(".aspx")
    }

    fun absolutize(url: String): String {
        val t = url.trim()
        return when {
            t.startsWith("http://", ignoreCase = true) ||
                t.startsWith("https://", ignoreCase = true) -> t
            t.startsWith("//") -> "https:$t"
            t.startsWith("/") -> "https://www.lectio.dk$t"
            else -> "https://www.lectio.dk/$t"
        }
    }
}
