package dk.betterlectio.android.feature.messages

/**
 * BetterLectio signature injected at send/reply time (extension parity).
 *
 * BBCode so Lectio renders a download link.
 */
object MessageSignature {
    const val BBCODE =
        "\n\n[url=https://betterlectio.dk/download]Sendt med BetterLectio[/url]"

    /**
     * Skip when user disabled signatures, or any recipient is a teacher (`T…` context id).
     * Extension: `shouldSkipSignature` in `beskeder-thread-parser.ts`.
     */
    fun shouldSkipSignature(
        recipientIds: Collection<String>,
        disableSignature: Boolean = false,
    ): Boolean {
        if (disableSignature) return true
        return recipientIds.any { it.trimStart().startsWith("T") }
    }

    fun appendIfNeeded(
        body: String,
        recipientIds: Collection<String>,
        disableSignature: Boolean,
    ): String {
        if (shouldSkipSignature(recipientIds, disableSignature)) return body
        if (body.contains("Sendt med BetterLectio", ignoreCase = true)) return body
        return body + BBCODE
    }
}
