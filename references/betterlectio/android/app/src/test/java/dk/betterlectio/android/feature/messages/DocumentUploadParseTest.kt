package dk.betterlectio.android.feature.messages

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DocumentUploadParseTest {

    @Test
    fun parse_json_serializedId() {
        val id = DocumentUpload.parseSerializedId("""{"serializedId":"abc-123"}""")
        assertEquals("abc-123", id)
    }

    @Test
    fun parse_regex_fallback() {
        val id = DocumentUpload.parseSerializedId("""result: serializedId: "xyz-99" ok""")
        assertEquals("xyz-99", id)
    }

    @Test
    fun parse_empty_null() {
        assertNull(DocumentUpload.parseSerializedId(""))
        assertNull(DocumentUpload.parseSerializedId("{}"))
    }
}
