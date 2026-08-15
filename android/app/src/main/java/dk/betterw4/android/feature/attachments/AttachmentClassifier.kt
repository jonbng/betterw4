package dk.betterw4.android.feature.attachments

import dk.betterw4.android.core.w4.W4Hosts
import java.util.Locale

/**
 * Decide whether a resource should be downloaded with the W4 session or opened as a web link.
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

        val authenticated = isAuthenticatedHost(lowerUrl)
        val fileSignals =
            ref.isFileHint ||
                lowerUrl.contains("getfile", ignoreCase = true) ||
                lowerUrl.contains("documentid", ignoreCase = true) ||
                lowerUrl.contains("showdocument", ignoreCase = true) ||
                AttachmentMime.isKnownFileExtension(ext)

        return when {
            fileSignals && AttachmentMime.isImageExtension(ext) -> AttachmentKind.IMAGE
            fileSignals && authenticated -> AttachmentKind.FILE
            fileSignals && !authenticated -> AttachmentKind.WEB_LINK
            authenticated && looksLikeHtmlPage(lowerUrl) -> AttachmentKind.WEB_LINK
            authenticated && fileSignals -> AttachmentKind.FILE
            else -> AttachmentKind.WEB_LINK
        }
    }

    fun isLectioUrl(url: String): Boolean = isAuthenticatedHost(url)

    fun isAuthenticatedHost(url: String): Boolean {
        val lower = url.lowercase(Locale.ROOT)
        return lower.contains(W4Hosts.HOST) ||
            lower.contains("lectio.dk") ||
            lower.startsWith("/lectio/") ||
            (lower.startsWith("/") && !lower.startsWith("//"))
    }

    private fun looksLikeHtmlPage(lowerUrl: String): Boolean {
        if (lowerUrl.contains("getfile") || lowerUrl.contains("documentid")) return false
        return lowerUrl.contains(".aspx") || lowerUrl.contains("index.php")
    }

    fun absolutize(url: String): String {
        val t = url.trim()
        return when {
            t.startsWith("http://", ignoreCase = true) ||
                t.startsWith("https://", ignoreCase = true) -> t
            t.startsWith("//") -> "https:$t"
            t.startsWith("/") -> W4Hosts.ORIGIN + t
            else -> "${W4Hosts.ORIGIN}/$t"
        }
    }
}
