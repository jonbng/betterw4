package dk.betterw4.android.feature.onduty

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

class W4OnDutyParserTest {
    private val todayHtml = javaClass.classLoader!!
        .getResourceAsStream("w4/onduty.html")!!
        .bufferedReader()
        .readText()

    private val scheduleHtml = javaClass.classLoader!!
        .getResourceAsStream("w4/onduty-schedule.html")!!
        .bufferedReader()
        .readText()

    @Test
    fun parses_live_today_page() {
        val page = W4OnDutyParser.parseToday(todayHtml)
        assertEquals("People on duty 19-Aug-2026", page.title)
        assertEquals(LocalDate.of(2026, 8, 19), page.date)
        assertEquals(1, page.groups.size)
        assertEquals("House Leader on Call", page.groups[0].role)
        val person = page.people.single()
        assertEquals("nc26lguz", person.uwcId)
        assertEquals("Luis Guzmán García Valdecasas", person.name)
        assertEquals("+34 691 701579", person.phone)
        assertEquals("luis.guzman.garcia.valdecasas@uwcrcn.no", person.email)
        assertNull(person.location)
        assertTrue(person.photoUrl!!.contains("/files/user_photos/nc26lguz_photo.jpg"))
    }

    @Test
    fun parses_live_schedule() {
        val schedule = W4OnDutyParser.parseSchedule(scheduleHtml)
        assertEquals("August 2026", schedule.monthLabel)
        assertEquals(2026, schedule.year)
        assertEquals(8, schedule.month)
        val today = schedule.days.first { it.isToday }
        assertEquals(LocalDate.of(2026, 8, 19), today.date)
        assertEquals("House Leader on Call", today.groups.single().role)
        assertEquals("Luis Guzmán García Valdecasas", today.people.single().name)

        val friday = schedule.days.first { it.date == LocalDate.of(2026, 8, 21) }
        assertEquals("Weekend OVERNIGHT House Leader", friday.groups.single().role)
        assertEquals("Mariya Georgieva", friday.people.single().name)

        val saturday = schedule.days.first { it.date == LocalDate.of(2026, 8, 22) }
        assertEquals(2, saturday.groups.size)
        assertEquals("Cary Reid", schedule.days.first { it.date == LocalDate.of(2026, 8, 20) }.people.single().name)
    }

    @Test
    fun upcoming_skips_today_and_keeps_order() {
        val upcoming = W4OnDutyParser.upcomingDays(
            W4OnDutyParser.parseSchedule(scheduleHtml),
            from = LocalDate.of(2026, 8, 19),
        )
        assertEquals(
            listOf(
                LocalDate.of(2026, 8, 20),
                LocalDate.of(2026, 8, 21),
                LocalDate.of(2026, 8, 22),
            ),
            upcoming.map { it.date },
        )
    }

    @Test
    fun parses_two_roles_and_empty_location() {
        val html = """
            <div id="content_inner">
              <h2>People on duty 20-Aug-2026</h2>
              <h3>House Leader on Call</h3>
              <table><tr><td><table><tr>
                <td><img src="/files/user_photos/nc00fff_thumb.jpg" alt="Photo of nc00fff" /></td>
                <td>
                  <b>Frankie Fossum</b><br />
                  <b>Phone:</b> +47 12 34 56 78<br />
                  <b>E-mail:</b> frankie@uwcrcn.no<br />
                  <b>Location:</b> Haugland<br />
                </td>
              </tr></table></td></tr></table>
              <h3>Nurse on Call</h3>
              <table><tr><td><table><tr>
                <td><img src="/files/user_photos/nc00ccc_thumb.jpg" alt="Photo of nc00ccc" /></td>
                <td>
                  <b>Chris Chen</b><br />
                  <b>Phone:</b> +47 98 76 54 32<br />
                  <b>E-mail:</b> chris@uwcrcn.no<br />
                  <b>Location:</b> <br />
                </td>
              </tr></table></td></tr></table>
            </div>
        """.trimIndent()
        val page = W4OnDutyParser.parseToday(html)
        assertEquals(2, page.groups.size)
        val house = page.groups[0].people.single()
        assertEquals("Frankie Fossum", house.name)
        assertEquals("Haugland", house.location)
        val nurse = page.groups[1].people.single()
        assertEquals("Chris Chen", nurse.name)
        assertNull(nurse.location)
    }

    @Test
    fun telephone_digits_strip_spaces() {
        assertEquals("+34691701579", OnDutyContact.digitsForDialing("+34 691 701579"))
        assertEquals("4712345678", OnDutyContact.digitsForDialing("47 12 34 56 78"))
        assertNull(OnDutyContact.digitsForDialing("n/a"))
        assertNull(OnDutyContact.digitsForDialing("123"))
    }

    @Test
    fun enrich_copies_phone_onto_schedule_name_match() {
        val today = W4OnDutyParser.parseToday(todayHtml).people
        val saturday = W4OnDutyParser.parseSchedule(scheduleHtml)
            .days.first { it.date == LocalDate.of(2026, 8, 22) }
        val enriched = W4OnDutyParser.enrich(saturday, today)
        val luis = enriched.people.first { it.name.contains("Luis") }
        assertEquals("+34 691 701579", luis.phone)
        assertEquals("nc26lguz", luis.uwcId)
    }
}
