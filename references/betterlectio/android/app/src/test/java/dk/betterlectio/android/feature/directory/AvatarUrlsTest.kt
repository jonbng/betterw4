package dk.betterlectio.android.feature.directory

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AvatarUrlsTest {

    @Test
    fun fromPictureId_builds_lectio_getimage_url() {
        val url = AvatarUrls.fromPictureId(94, "74096247556")
        assertEquals(
            "https://www.lectio.dk/lectio/94/GetImage.aspx?pictureid=74096247556&fullsize=1",
            url,
        )
    }

    @Test
    fun fromPictureId_can_omit_fullsize() {
        val url = AvatarUrls.fromPictureId(517, "12", fullSize = false)
        assertEquals(
            "https://www.lectio.dk/lectio/517/GetImage.aspx?pictureid=12",
            url,
        )
    }

    @Test
    fun pictureIdFromUrl_extracts_id() {
        assertEquals(
            "99887",
            AvatarUrls.pictureIdFromUrl(
                "/lectio/517/GetImage.aspx?pictureid=99887&fullsize=1",
            ),
        )
        assertNull(AvatarUrls.pictureIdFromUrl("https://example.com/photo.png"))
        assertNull(AvatarUrls.pictureIdFromUrl(null))
    }

    @Test
    fun isLectioAvatar_detects_getimage() {
        assertTrue(
            AvatarUrls.isLectioAvatar(
                "https://www.lectio.dk/lectio/94/GetImage.aspx?pictureid=1",
            ),
        )
        assertFalse(AvatarUrls.isLectioAvatar("https://www.gravatar.com/avatar/x"))
    }
}
