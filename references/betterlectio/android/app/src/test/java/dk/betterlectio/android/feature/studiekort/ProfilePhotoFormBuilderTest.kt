package dk.betterlectio.android.feature.studiekort

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ProfilePhotoFormBuilderTest {

    @Test
    fun dialogPath_includes_student_entity() {
        assertEquals(
            "PhotoDialog.aspx?selectedEntityId=S12345",
            ProfilePhotoFormBuilder.dialogPath("12345"),
        )
    }

    @Test
    fun buildFormFields_includes_image_data_url_and_save_argument() {
        val pageHtml = """
            <html><body>
            <input type="hidden" name="__VIEWSTATE" id="__VIEWSTATE" value="vs1"/>
            <input type="hidden" name="__EVENTVALIDATION" id="__EVENTVALIDATION" value="ev1"/>
            <input type="hidden" name="ctl00${'$'}Content${'$'}other" value="x"/>
            </body></html>
        """.trimIndent()
        val jpegish = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0x01, 0x02, 0x03)
        val fields = ProfilePhotoFormBuilder.buildFormFields(
            pageHtml = pageHtml,
            imageBytes = jpegish,
            mimeType = "image/jpeg",
        )
        assertEquals("__Page", fields["__EVENTTARGET"])
        assertEquals("GEM", fields["__EVENTARGUMENT"])
        assertEquals("vs1", fields["__VIEWSTATE"])
        val dataUrl = fields[ProfilePhotoFormBuilder.IMAGE_FIELD]
        requireNotNull(dataUrl)
        assertTrue(dataUrl.startsWith("data:image/jpeg;base64,"))
        assertTrue(dataUrl.length > "data:image/jpeg;base64,".length)
        // Real base64 of our bytes must be present (not empty payload)
        val b64Part = dataUrl.removePrefix("data:image/jpeg;base64,")
        val decoded = java.util.Base64.getDecoder().decode(b64Part)
        assertEquals(jpegish.toList(), decoded.toList())
    }

    @Test
    fun isUploadAccepted_rejects_rights_message() {
        assertFalse(ProfilePhotoFormBuilder.isUploadAccepted("Du har ikke rettigheder til dette"))
        assertTrue(ProfilePhotoFormBuilder.isUploadAccepted("<html>ok</html>"))
    }
}
