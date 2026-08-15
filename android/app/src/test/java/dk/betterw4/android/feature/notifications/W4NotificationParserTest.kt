package dk.betterw4.android.feature.notifications

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class W4NotificationParserTest {
    private val html = javaClass.classLoader!!
        .getResourceAsStream("w4/notifications-refresh.html")!!
        .bufferedReader()
        .readText()

    @Test
    fun parses_count_groups_and_items() {
        val snap = W4NotificationParser.parse(html)
        assertEquals(3, snap.count)
        assertEquals(W4NotificationSeverity.NEW, snap.severity)
        assertEquals(1, snap.taskGroups.size)
        assertEquals("Assessments", snap.taskGroups[0].title)
        assertEquals("assessment", snap.taskGroups[0].type)
        assertEquals(2, snap.taskGroups[0].items.size)
        val lab = snap.taskGroups[0].items.first { it.id == "12" }
        assertEquals("Lab report", lab.title)
        assertEquals(W4NotificationSeverity.OVERDUE, lab.severity)
        assertTrue(lab.href!!.contains("academics/deadlines"))
        assertEquals(1, snap.emailGroups.size)
        assertEquals("88", snap.emailGroups[0].items.single().id)
        assertTrue(snap.emailGroups[0].items.single().href!!.contains("mailer/view"))
    }

    @Test
    fun parses_ajax_wrapper_fragment() {
        val fragment = """
            <div><div class="btn-group"><div class="alert overdue">1</div>
            <h3 class="tasks">Tasks</h3>
            <dl><dt>Other</dt><dd><ul><li>
              <a href="/x">Ping</a>
              <a class="read" data-notification-id="9">read</a>
            </li></ul></dd></dl></div></div>
        """.trimIndent()
        val snap = W4NotificationParser.parse(fragment)
        assertEquals(1, snap.count)
        assertEquals(W4NotificationSeverity.OVERDUE, snap.severity)
        assertEquals("9", snap.items.single().id)
        assertEquals("Ping", snap.items.single().title)
    }
}
