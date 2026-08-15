package dk.betterlectio.android.core.i18n

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

/**
 * Ensures Danish default and English string resources stay in lockstep.
 * Follow-up translation agents must keep both files' key sets equal.
 */
class I18nStringParityTest {

    @Test
    fun danishAndEnglishStringKeysMatch() {
        val root = projectRoot()
        val da = stringKeys(File(root, "app/src/main/res/values/strings.xml"))
        val en = stringKeys(File(root, "app/src/main/res/values-en/strings.xml"))

        val missingInEn = da - en
        val missingInDa = en - da

        assertTrue(
            "Keys in Danish but missing in English: $missingInEn",
            missingInEn.isEmpty(),
        )
        assertTrue(
            "Keys in English but missing in Danish: $missingInDa",
            missingInDa.isEmpty(),
        )
        assertEquals(da.size, en.size)
        assertTrue("Expected non-empty string catalogs", da.isNotEmpty())
    }

    @Test
    fun noEmptyTranslationValues() {
        val root = projectRoot()
        for (rel in listOf(
            "app/src/main/res/values/strings.xml",
            "app/src/main/res/values-en/strings.xml",
        )) {
            val empties = emptyNamedStrings(File(root, rel))
            assertTrue("Empty string values in $rel: $empties", empties.isEmpty())
        }
    }

    private fun projectRoot(): File {
        var dir = File(System.getProperty("user.dir") ?: ".")
        // Unit tests may run with cwd = project root or :app module.
        repeat(4) {
            if (File(dir, "app/src/main/res/values/strings.xml").isFile) return dir
            if (File(dir, "src/main/res/values/strings.xml").isFile) {
                return dir.parentFile ?: dir
            }
            dir = dir.parentFile ?: return File(".")
        }
        return File(".")
    }

    private fun stringKeys(file: File): Set<String> {
        assertTrue("Missing ${file.absolutePath}", file.isFile)
        val doc = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(file)
        val nodes = doc.getElementsByTagName("string")
        val keys = mutableSetOf<String>()
        for (i in 0 until nodes.length) {
            val el = nodes.item(i) as Element
            keys += el.getAttribute("name")
        }
        return keys
    }

    private fun emptyNamedStrings(file: File): List<String> {
        val doc = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(file)
        val nodes = doc.getElementsByTagName("string")
        val empties = mutableListOf<String>()
        for (i in 0 until nodes.length) {
            val el = nodes.item(i) as Element
            val name = el.getAttribute("name")
            val text = el.textContent?.trim().orEmpty()
            if (text.isEmpty()) empties += name
        }
        return empties
    }
}
