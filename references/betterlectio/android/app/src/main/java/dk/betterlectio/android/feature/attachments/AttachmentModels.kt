package dk.betterlectio.android.feature.attachments

/**
 * How to handle a tapped resource: authenticated file download, in-app image, or external link.
 */
enum class AttachmentKind {
    FILE,
    IMAGE,
    WEB_LINK,
}

data class AttachmentRef(
    val name: String,
    val url: String,
    /** Parser hint (e.g. schedule `isFile`). Classifier may still reclassify. */
    val isFileHint: Boolean = false,
) {
    val kind: AttachmentKind get() = AttachmentClassifier.classify(this)
}

sealed class AttachmentActionResult {
    data object Opened : AttachmentActionResult()
    data object ImagePreview : AttachmentActionResult()
    data object WebLinkOpened : AttachmentActionResult()
    data object Saved : AttachmentActionResult()
    data object Shared : AttachmentActionResult()
    data class Failed(val error: AttachmentError) : AttachmentActionResult()
}

enum class AttachmentError {
    OFFLINE,
    SESSION,
    ROBOT,
    EMPTY,
    HTML_INSTEAD_OF_FILE,
    NO_APP,
    GENERIC,
}
