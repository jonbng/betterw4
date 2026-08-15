package dk.betterw4.android.feature.documents

import org.junit.Assert.assertEquals
import org.junit.Test

class W4DocumentsParserTest {
    private val html = javaClass.classLoader!!
        .getResourceAsStream("w4/documents-index.html")!!
        .bufferedReader()
        .readText()

    @Test
    fun parses_root_folders() {
        val listing = W4DocumentsParser.parse(html)
        assertEquals(2, listing.items.size)
        assertEquals("Internal Information", listing.items[0].title)
        assertEquals("27", listing.items[0].id)
        assertEquals(W4DocumentKind.FOLDER, listing.items[0].kind)
    }
}
