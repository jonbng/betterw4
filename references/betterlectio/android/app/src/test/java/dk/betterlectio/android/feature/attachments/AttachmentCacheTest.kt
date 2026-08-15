package dk.betterlectio.android.feature.attachments

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class AttachmentCacheTest {

    @Test
    fun keyIsStable() {
        val a = AttachmentCache.sha256Hex("https://lectio.dk/a")
        val b = AttachmentCache.sha256Hex("https://lectio.dk/a")
        val c = AttachmentCache.sha256Hex("https://lectio.dk/b")
        assertEquals(a, b)
        assertTrue(a != c)
        assertEquals(64, a.length)
    }

    @Test
    fun putFindClearAndEvict() {
        val dir = createTempDir(prefix = "att-cache")
        try {
            val cache = AttachmentCache(dir)
            val url = "https://www.lectio.dk/lectio/1/GetFile.aspx?documentid=1"
            assertNull(cache.find(url))
            val file = cache.put(url, "Skema.pdf", "%PDF".toByteArray())
            assertTrue(file.exists())
            assertNotNull(cache.find(url))
            assertEquals("%PDF", cache.find(url)!!.readText())

            cache.evictIfNeeded(maxBytes = 0, maxFiles = 0)
            assertNull(cache.find(url))

            cache.put(url, "Skema.pdf", "%PDF".toByteArray())
            cache.clear()
            assertNull(cache.find(url))
        } finally {
            dir.deleteRecursively()
        }
    }

    @Test
    fun putReplacesSameUrlDifferentName() {
        val dir = createTempDir(prefix = "att-cache2")
        try {
            val cache = AttachmentCache(dir)
            val url = "https://www.lectio.dk/file"
            cache.put(url, "a.pdf", byteArrayOf(1))
            cache.put(url, "b.pdf", byteArrayOf(2))
            val found = cache.find(url)!!
            assertTrue(found.name.endsWith("b.pdf"))
            assertEquals(1, dir.listFiles()?.count { it.isFile })
        } finally {
            dir.deleteRecursively()
        }
    }
}
