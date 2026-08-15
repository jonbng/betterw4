package dk.betterlectio.android.feature.directory

/**
 * Lectio profile-image URLs.
 *
 * Lectio serves photos at `GetImage.aspx?pictureid={id}` — the picture id is **not**
 * the student/teacher entity id and must be scraped from the person page header
 * (`s_m_HeaderContent_picctrlthumbimage`) or member-list thumbnails.
 */
object AvatarUrls {

    fun fromPictureId(gymId: Int, pictureId: String, fullSize: Boolean = true): String {
        val id = pictureId.trim()
        require(id.isNotEmpty()) { "pictureId must not be blank" }
        val full = if (fullSize) "&fullsize=1" else ""
        return "https://www.lectio.dk/lectio/$gymId/GetImage.aspx?pictureid=$id$full"
    }

    /**
     * Extract a picture id from a GetImage URL or raw `pictureid=…` fragment.
     */
    fun pictureIdFromUrl(url: String?): String? {
        if (url.isNullOrBlank()) return null
        return Regex("""pictureid=(\d+)""", RegexOption.IGNORE_CASE)
            .find(url)
            ?.groupValues
            ?.getOrNull(1)
            ?.takeIf { it.isNotBlank() }
    }

    /** True when [url] is a Lectio GetImage avatar (needs session cookies). */
    fun isLectioAvatar(url: String?): Boolean {
        if (url.isNullOrBlank()) return false
        return url.contains("lectio.dk", ignoreCase = true) &&
            (url.contains("GetImage", ignoreCase = true) || url.contains("pictureid", ignoreCase = true))
    }
}
