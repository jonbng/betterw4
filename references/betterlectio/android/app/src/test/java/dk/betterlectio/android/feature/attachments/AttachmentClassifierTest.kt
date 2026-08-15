package dk.betterlectio.android.feature.attachments

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AttachmentClassifierTest {

    @Test
    fun getFile_isFile() {
        val ref = AttachmentRef(
            name = "Skema.pdf",
            url = "https://www.lectio.dk/lectio/94/GetFile.aspx?documentid=99",
            isFileHint = false,
        )
        assertEquals(AttachmentKind.FILE, ref.kind)
    }

    @Test
    fun imageExtension_isImage() {
        val ref = AttachmentRef(
            name = "foto.jpg",
            url = "https://www.lectio.dk/lectio/94/GetFile.aspx?documentid=1",
        )
        assertEquals(AttachmentKind.IMAGE, ref.kind)
    }

    @Test
    fun externalLink_isWeb() {
        val ref = AttachmentRef(
            name = "Geogebra",
            url = "https://www.geogebra.org/",
            isFileHint = false,
        )
        assertEquals(AttachmentKind.WEB_LINK, ref.kind)
    }

    @Test
    fun scheduleFileHint_withoutExtension_isFile() {
        val ref = AttachmentRef(
            name = "Opgavesæt",
            url = "/lectio/94/GetFile.aspx?documentid=5",
            isFileHint = true,
        )
        assertEquals(AttachmentKind.FILE, ref.kind)
    }

    @Test
    fun absolutize_relative() {
        assertEquals(
            "https://www.lectio.dk/lectio/1/GetFile.aspx?documentid=1",
            AttachmentClassifier.absolutize("/lectio/1/GetFile.aspx?documentid=1"),
        )
        assertTrue(AttachmentClassifier.isLectioUrl("https://www.lectio.dk/x"))
    }
}
