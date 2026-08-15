package dk.betterlectio.android.core.lectio.model

import okhttp3.HttpUrl

data class LectioResponse(
    val body: String,
    val bytes: ByteArray,
    val finalUrl: HttpUrl,
    val statusCode: Int,
    /** Raw Content-Type header (may include charset). Useful for file downloads. */
    val contentType: String? = null,
    /** Raw Content-Disposition header (filename hints for GetFile). */
    val contentDisposition: String? = null,
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is LectioResponse) return false
        return body == other.body &&
            bytes.contentEquals(other.bytes) &&
            finalUrl == other.finalUrl &&
            statusCode == other.statusCode &&
            contentType == other.contentType &&
            contentDisposition == other.contentDisposition
    }

    override fun hashCode(): Int {
        var result = body.hashCode()
        result = 31 * result + bytes.contentHashCode()
        result = 31 * result + finalUrl.hashCode()
        result = 31 * result + statusCode
        result = 31 * result + (contentType?.hashCode() ?: 0)
        result = 31 * result + (contentDisposition?.hashCode() ?: 0)
        return result
    }
}
