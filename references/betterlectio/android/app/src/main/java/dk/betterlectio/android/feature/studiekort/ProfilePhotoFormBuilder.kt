package dk.betterlectio.android.feature.studiekort

import dk.betterlectio.android.core.lectio.scrape.AspNetForm
import java.util.Base64

/**
 * Builds Lectio PhotoDialog form fields for profile picture change.
 * Flutter parity: ProfileController.changeProfilePicture → PhotoDialog.aspx
 *
 * Pure field map (testable without network). Image is sent as a data-URL in
 * `ctl00$Content$imageDataUrlHidden` (Flutter field name).
 */
object ProfilePhotoFormBuilder {

    const val PHOTO_DIALOG_PATH_TEMPLATE = "PhotoDialog.aspx?selectedEntityId=S%s"
    const val IMAGE_FIELD = "ctl00\$Content\$imageDataUrlHidden"
    const val EVENT_ARGUMENT_SAVE = "GEM"
    const val DEFAULT_EVENT_TARGET = "__Page"

    fun dialogPath(studentId: String): String =
        PHOTO_DIALOG_PATH_TEMPLATE.format(studentId)

    /**
     * @param pageHtml GET response of PhotoDialog
     * @param imageBytes JPEG/PNG bytes
     * @param mimeType e.g. image/jpeg
     */
    fun buildFormFields(
        pageHtml: String,
        imageBytes: ByteArray,
        mimeType: String = "image/jpeg",
        eventTarget: String = DEFAULT_EVENT_TARGET,
    ): Map<String, String> {
        require(imageBytes.isNotEmpty()) { "imageBytes must not be empty" }
        val asp = AspNetForm.extractAspData(pageHtml, eventTarget).toMutableMap()
        // Merge full form fields so Lectio gets every hidden input
        AspNetForm.parseAllFormFields(pageHtml).forEach { (k, v) ->
            if (k !in asp) asp[k] = v
        }
        asp["__EVENTTARGET"] = eventTarget
        asp["__EVENTARGUMENT"] = EVENT_ARGUMENT_SAVE
        asp[IMAGE_FIELD] = toDataUrl(imageBytes, mimeType)
        return asp
    }

    fun toDataUrl(imageBytes: ByteArray, mimeType: String = "image/jpeg"): String {
        val b64 = Base64.getEncoder().encodeToString(imageBytes)
        return "data:$mimeType;base64,$b64"
    }

    /**
     * Lectio rejects with a rights message containing "rettigheder" (Flutter check).
     */
    fun isUploadAccepted(responseHtml: String): Boolean {
        if (responseHtml.isBlank()) return false
        return !responseHtml.contains("rettigheder", ignoreCase = true)
    }
}
