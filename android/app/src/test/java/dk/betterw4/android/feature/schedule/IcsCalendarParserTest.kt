package dk.betterw4.android.feature.schedule

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.LocalTime

class IcsCalendarParserTest {
    private val ics = javaClass.classLoader!!
        .getResourceAsStream("w4/school-calendar.ics")!!
        .bufferedReader()
        .readText()

    @Test
    fun week_33_includes_all_day_and_timed_oslo_events() {
        val monday = LocalDate.of(2026, 8, 10)
        val events = IcsCalendarParser.eventsOverlapping(ics, monday, monday.plusDays(7))
        val titles = events.map { it.title }.toSet()
        assertTrue(titles.contains("Year 1 arrival in Bergen"))
        assertTrue(titles.contains("Year 2 Red Cross Day"))
        assertTrue(titles.contains("Staff Intro week, campus"))
        assertTrue(titles.contains("Partial eclipse visible in Norway"))
        assertFalse(titles.contains("Should not appear"))
        assertFalse(titles.contains("First College Meeting")) // Tuesday week 34

        val arrival = events.single { it.title == "Year 1 arrival in Bergen" }
        assertTrue(arrival.isAllDay)
        assertEquals(LocalDate.of(2026, 8, 14), arrival.date)
        assertEquals("gcal-", arrival.id.take(5))
        assertEquals(SCHOOL_CALENDAR_TEAM_TOKEN, arrival.team)
        assertTrue(arrival.notes.orEmpty().contains("Welcome to RCN"))

        val eclipse = events.single { it.title == "Partial eclipse visible in Norway" }
        assertFalse(eclipse.isAllDay)
        assertEquals(LocalTime.of(14, 0), eclipse.start?.toLocalTime())
        assertEquals(LocalTime.of(15, 0), eclipse.end?.toLocalTime())
        assertEquals("Outside", eclipse.room)
    }

    @Test
    fun exclusive_all_day_dtend_covers_middle_days_only() {
        val monday = LocalDate.of(2026, 8, 10)
        val events = IcsCalendarParser.eventsOverlapping(ics, monday, monday.plusDays(7))
        val redCross = events.single { it.title == "Year 2 Red Cross Day" }
        val expanded = ScheduleMultiDay.expandEventAcrossDays(redCross)
        assertEquals(
            listOf(
                LocalDate.of(2026, 8, 13),
                LocalDate.of(2026, 8, 14),
                LocalDate.of(2026, 8, 15),
            ),
            expanded.map { it.date },
        )
    }

    @Test
    fun utc_datetime_converts_to_oslo() {
        val monday = LocalDate.of(2026, 8, 17)
        val events = IcsCalendarParser.eventsOverlapping(ics, monday, monday.plusDays(7))
        val meeting = events.single { it.title == "First College Meeting" }
        // 11:30Z in August is 13:30 Europe/Oslo (CEST).
        assertEquals(LocalTime.of(13, 30), meeting.start?.toLocalTime())
        assertEquals(LocalTime.of(14, 30), meeting.end?.toLocalTime())
        assertEquals("Auditorium", meeting.room)
    }

    @Test
    fun weekly_rrule_from_previous_year_hits_requested_monday() {
        val monday = LocalDate.of(2026, 8, 17)
        val events = IcsCalendarParser.eventsOverlapping(ics, monday, monday.plusDays(7))
        val advisor = events.single { it.title == "Advisor check in" }
        assertEquals(LocalDate.of(2026, 8, 17), advisor.date)
        assertEquals(LocalTime.of(8, 30), advisor.start?.toLocalTime())
        assertEquals(LocalTime.of(9, 0), advisor.end?.toLocalTime())
    }

    @Test
    fun merge_pads_weekend_days_onto_weekday_only_week() {
        val ac = ScheduleWeek(
            year = 2026,
            week = 33,
            days = listOf(
                ScheduleDay(
                    date = LocalDate.of(2026, 8, 10),
                    events = listOf(
                        ScheduleEvent(
                            id = "ac-1",
                            title = "Biology HL",
                            date = LocalDate.of(2026, 8, 10),
                        ),
                    ),
                ),
            ),
        )
        val extra = IcsCalendarParser.eventsOverlapping(
            ics,
            LocalDate.of(2026, 8, 10),
            LocalDate.of(2026, 8, 17),
        )
        val merged = SchoolCalendar.mergeIntoWeek(ac, extra)
        assertEquals(7, merged.days.size)
        assertTrue(merged.days[0].events.any { it.title == "Biology HL" })
        assertTrue(merged.days[4].events.any { it.title == "Year 1 arrival in Bergen" })
        assertTrue(SchoolCalendar.isSchoolCalendarEvent(merged.days[4].events.first { it.title.startsWith("Year 1") }))
    }

    @Test
    fun visibleEvents_hidesSchoolCalendarWhenToggledOff() {
        val monday = LocalDate.of(2026, 8, 10)
        val lesson = ScheduleEvent(
            id = "ac-1",
            title = "Biology HL",
            date = monday,
        )
        val calendar = IcsCalendarParser.eventsOverlapping(ics, monday, monday.plusDays(7))
            .first { it.title == "Year 1 arrival in Bergen" }
        val events = listOf(lesson, calendar)

        val shown = SchoolCalendar.visibleEvents(events, showSchoolCalendar = true)
        assertEquals(events, shown)

        val hidden = SchoolCalendar.visibleEvents(events, showSchoolCalendar = false)
        assertEquals(listOf(lesson), hidden)
        assertFalse(hidden.any(SchoolCalendar::isSchoolCalendarEvent))
    }

    @Test
    fun description_html_breaks_become_newlines() {
        val ics = """
            BEGIN:VCALENDAR
            BEGIN:VEVENT
            DTSTART;VALUE=DATE:20260818
            DTEND;VALUE=DATE:20260819
            SUMMARY:Economics
            DESCRIPTION:Bring calculator&lt;br /&gt;Sit in A 1.2
            UID:html-desc
            END:VEVENT
            END:VCALENDAR
        """.trimIndent()
        val event = IcsCalendarParser.eventsOverlapping(
            ics,
            LocalDate.of(2026, 8, 18),
            LocalDate.of(2026, 8, 19),
        ).single()
        assertEquals("Bring calculator\nSit in A 1.2", event.notes)
    }
}
