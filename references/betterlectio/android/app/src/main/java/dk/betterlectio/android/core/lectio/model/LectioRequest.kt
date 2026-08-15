package dk.betterlectio.android.core.lectio.model

import okhttp3.HttpUrl

data class LectioRequest(
    val url: HttpUrl,
    val method: String = "GET",
    val body: ByteArray? = null,
    val headers: Map<String, String> = emptyMap(),
    val priority: FetchPriority = FetchPriority.Important,
    /** When set, engine re-reads credentials from store before each attempt. */
    val studentId: String? = null,
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is LectioRequest) return false
        return url == other.url &&
            method == other.method &&
            body.contentEquals(other.body) &&
            headers == other.headers &&
            priority == other.priority &&
            studentId == other.studentId
    }

    override fun hashCode(): Int {
        var result = url.hashCode()
        result = 31 * result + method.hashCode()
        result = 31 * result + (body?.contentHashCode() ?: 0)
        result = 31 * result + headers.hashCode()
        result = 31 * result + priority.hashCode()
        result = 31 * result + (studentId?.hashCode() ?: 0)
        return result
    }
}
