package dk.betterw4.android.feature.attachments

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AttachmentClassifierTest {

    @Test
    fun w4Document_isFile() {
        val ref = AttachmentRef(
            name = "Skema.pdf",
            url = "https://w4.uwcrcn.no/index.php?r=documents/file&id=99",
            isFileHint = true,
        )
        assertEquals(AttachmentKind.FILE, ref.kind)
    }

    @Test
    fun imageExtension_isImage() {
        val ref = AttachmentRef(
            name = "foto.jpg",
            url = "https://w4.uwcrcn.no/uploads/foto.jpg",
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
    fun relativeFileHint_isFile() {
        val ref = AttachmentRef(
            name = "Opgavesæt",
            url = "/uploads/task.pdf",
            isFileHint = true,
        )
        assertEquals(AttachmentKind.FILE, ref.kind)
    }

    @Test
    fun absolutize_relative() {
        assertEquals(
            "https://w4.uwcrcn.no/uploads/file.pdf",
            AttachmentClassifier.absolutize("/uploads/file.pdf"),
        )
        assertTrue(AttachmentClassifier.isLectioUrl("https://w4.uwcrcn.no/x"))
    }
}
