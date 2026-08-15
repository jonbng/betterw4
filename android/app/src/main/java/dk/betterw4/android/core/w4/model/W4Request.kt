package dk.betterw4.android.core.w4.model

import okhttp3.HttpUrl

data class W4Request(
    val url: HttpUrl,
    val method: String = "GET",
    val body: ByteArray? = null,
    val headers: Map<String, String> = emptyMap(),
    val priority: FetchPriority = FetchPriority.Important,
    /** When set, engine re-reads credentials from store before each attempt. */
    val studentId: String? = null,
    /**
     * Native login GETs/POSTs land on `site/login` on purpose. When true, that is
     * not treated as session expiry.
     */
    val allowLoginPage: Boolean = false,
    /** jQuery `$.post` — 403/409 bodies follow `init_ajax.js` rules. */
    val ajax: Boolean = false,
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is W4Request) return false
        return url == other.url &&
            method == other.method &&
            body.contentEquals(other.body) &&
            headers == other.headers &&
            priority == other.priority &&
            studentId == other.studentId &&
            allowLoginPage == other.allowLoginPage &&
            ajax == other.ajax
    }

    override fun hashCode(): Int {
        var result = url.hashCode()
        result = 31 * result + method.hashCode()
        result = 31 * result + (body?.contentHashCode() ?: 0)
        result = 31 * result + headers.hashCode()
        result = 31 * result + priority.hashCode()
        result = 31 * result + (studentId?.hashCode() ?: 0)
        result = 31 * result + allowLoginPage.hashCode()
        result = 31 * result + ajax.hashCode()
        return result
    }
}
