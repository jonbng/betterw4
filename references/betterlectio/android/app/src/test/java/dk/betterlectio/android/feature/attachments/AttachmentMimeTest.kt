package dk.betterlectio.android.feature.attachments

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AttachmentMimeTest {

    @Test
    fun extensionOf_stripsQueryAndPath() {
        assertEquals("pdf", AttachmentMime.extensionOf("Skema.pdf"))
        assertEquals("pdf", AttachmentMime.extensionOf("https://lectio.dk/a/Skema.pdf?x=1"))
        // .aspx is not a known document extension we care about for MIME
        assertEquals("aspx", AttachmentMime.extensionOf("/lectio/1/GetFile.aspx?documentid=1"))
        assertNull(AttachmentMime.extensionOf("https://www.lectio.dk/lectio/1/GetFile"))
    }

    @Test
    fun mimeFromName() {
        assertEquals("application/pdf", AttachmentMime.mimeFromNameOrUrl("Opgave.pdf"))
        assertEquals(
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            AttachmentMime.mimeFromNameOrUrl("report.docx"),
        )
        assertEquals("image/png", AttachmentMime.mimeFromNameOrUrl("photo.PNG"))
    }

    @Test
    fun sniff_pdfAndPng() {
        val pdf = "%PDF-1.4".toByteArray()
        assertEquals("application/pdf", AttachmentMime.sniff(pdf))

        val png = byteArrayOf(
            0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        )
        assertEquals("image/png", AttachmentMime.sniff(png))
    }

    @Test
    fun contentDisposition_filenameAndStar() {
        assertEquals(
            "Skema.pdf",
            AttachmentMime.filenameFromContentDisposition("attachment; filename=\"Skema.pdf\""),
        )
        assertEquals(
            "Rapport.pdf",
            AttachmentMime.filenameFromContentDisposition(
                "attachment; filename*=UTF-8''Rapport.pdf",
            ),
        )
    }

    @Test
    fun sanitizeAndEnsureExtension() {
        val safe = AttachmentMime.sanitizeFileName("bad/name:file?.pdf")
        assertTrue(!safe.contains("/"))
        assertEquals(
            "notes.pdf",
            AttachmentMime.ensureExtension("notes", "application/pdf"),
        )
        assertEquals(
            "notes.pdf",
            AttachmentMime.ensureExtension("notes.pdf", "application/pdf"),
        )
    }

    @Test
    fun resolve_prefersNameThenSniff() {
        val pdfBytes = "%PDF-1.7".toByteArray()
        assertEquals(
            "application/pdf",
            AttachmentMime.resolve("file.bin", "application/octet-stream", pdfBytes),
        )
        assertEquals(
            "application/pdf",
            AttachmentMime.resolve("Opgave.pdf", null, ByteArray(0)),
        )
    }
}
