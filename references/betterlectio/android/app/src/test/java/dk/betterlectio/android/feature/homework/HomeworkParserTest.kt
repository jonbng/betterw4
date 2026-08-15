package dk.betterlectio.android.feature.homework

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HomeworkParserTest {
    @Test
    fun parses_homework_fixture() {
        val html = javaClass.classLoader!!
            .getResourceAsStream("lectio/fixtures/homework_list.html")!!
            .bufferedReader().readText()
        val items = HomeworkParser.parse(html)
        assertEquals(1, items.size)
        assertTrue(items[0].activityTitle.contains("Matematik"))
        assertEquals("Læs kapitel 4", items[0].note)
        assertEquals("999", items[0].id)
        assertEquals("Ma A", items[0].team)
        assertEquals(java.time.LocalDate.of(2026, 3, 11), items[0].date)
        // Detail load requires a usable activity link (absid path).
        assertTrue(
            "href must carry absid for detail scrape",
            items[0].href != null && items[0].href!!.contains("absid=999"),
        )
    }
}

