package dk.betterw4.android.feature.schedule

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDateTime
import java.time.LocalTime

class W4TimetableParserTest {
    private val html = javaClass.classLoader!!
        .getResourceAsStream("w4/timetable-week.html")!!
        .bufferedReader()
        .readText()

    @Test
    fun parses_header_dates_and_period_blocks() {
        val week = W4TimetableParser.parseWeek(html, year = 2026, week = 33)
        assertEquals(7, week.days.size)
        val monday = week.days[0]
        assertEquals(1, monday.events.size)
        val bio = monday.events[0]
        assertEquals("Biology HL", bio.title)
        assertEquals("A 2.1", bio.room)
        assertEquals(LocalTime.of(8, 0), bio.start?.toLocalTime())
        assertEquals(LocalTime.of(9, 0), bio.end?.toLocalTime())

        val wednesday = week.days[2]
        assertEquals("TOK", wednesday.events.single().title)
        assertEquals(LocalTime.of(9, 0), wednesday.events.single().start?.toLocalTime())
        assertEquals(LocalTime.of(11, 0), wednesday.events.single().end?.toLocalTime())

        assertTrue(week.days[5].events.isEmpty())
        assertTrue(week.days[6].events.isEmpty())
    }

    @Test
    fun parse_live_w4_class_ids_use_tooltip_subject_names() {
        val html = javaClass.classLoader!!
            .getResourceAsStream("w4/timetable-live-week.html")!!
            .bufferedReader()
            .readText()
        val week = W4TimetableParser.parseWeek(html, year = 2026, week = 35)
        val monday = week.days[0].events
        assertEquals("Breakfast", monday[0].title)
        assertEquals("Breakfast", monday[0].team)
        assertEquals(null, monday[0].notes)

        val econ = monday[1]
        assertEquals("Economics", econ.title)
        assertEquals("1EA16CECOX", econ.team)
        assertEquals("István Poór", econ.teacher)
        assertEquals(null, econ.teacherId)
        assertEquals("A 1.6", econ.room)
        assertEquals(null, econ.notes)
        assertEquals("ac-w4-1EA16CECOX", econ.id)
        assertEquals(LocalTime.of(8, 15), econ.start?.toLocalTime())
        assertEquals(LocalTime.of(9, 5), econ.end?.toLocalTime())

        val math = monday[2]
        assertEquals("Mathematics Analysis and Approaches", math.title)
        assertEquals("1DA13HMTAA", math.team)
        assertEquals("A 1.3", math.room)

        assertEquals("Break", monday[3].title)
    }

    @Test
    fun period_tooltip_extracts_class_teacher_and_room() {
        val tip = PeriodTooltip.parse(
            "Monday 08:15 - 09:05<br /> Class: <b>Economics</b><br />Teacher: <b>István Poór</b><br />Room: <b>A 1.6</b>",
        )
        assertEquals("Economics", tip.className)
        assertEquals("István Poór", tip.teacher)
        assertEquals("A 1.6", tip.room)
        assertEquals(null, tip.blockName)
        assertEquals(null, tip.extraNotes)

        val block = PeriodTooltip.parse("Monday 12:30 - 13:15<br /> Block: <b>X</b>")
        assertEquals("X", block.blockName)
        assertEquals(null, block.className)
        assertEquals(null, block.extraNotes)
    }

    @Test
    fun period_tooltip_strips_html_and_keeps_leftover_notes() {
        val tip = PeriodTooltip.parse(
            "Monday 08:15 - 09:05<br /> Class: <b>Economics</b><br />Teacher: <b>István Poór</b>" +
                "<br />Room: <b>A 1.6</b><br />Bring calculator<br/>Sit in A 1.2",
        )
        assertEquals("Economics", tip.className)
        assertEquals("Bring calculator\nSit in A 1.2", tip.extraNotes)

        val encoded = PeriodTooltip.parse(
            "Monday 08:15 - 09:05&lt;br /&gt; Class: &lt;b&gt;Economics&lt;/b&gt;&lt;br /&gt;Moved to A 1.2",
        )
        assertEquals("Economics", encoded.className)
        assertEquals("Moved to A 1.2", encoded.extraNotes)
        assertTrue(encoded.extraNotes.orEmpty().none { it == '<' })
    }

    @Test
    fun leftover_tooltip_notes_land_on_the_event() {
        val html = """
            <div id="timetable">
              <div class="column">
                <div class="period"
                     title="Monday 08:15 - 09:05<br /> Class: <b>Economics</b><br />Bring calculator<br/>Sit in A 1.2"
                     style="top: 0px; height: 50px;">
                  <div class="inner">
                    <div class="datetime">08:15 - 09:05</div>
                    <div class="title">1EA16CECOX</div>
                  </div>
                </div>
              </div>
            </div>
        """.trimIndent()
        val event = W4TimetableParser.parseWeek(html, year = 2026, week = 35).days.single().events.single()
        assertEquals("Economics", event.title)
        assertEquals("Bring calculator\nSit in A 1.2", event.notes)
        assertFalse(event.notes.orEmpty().contains("<"))
    }

    @Test
    fun teacher_uwc_id_is_kept_even_when_class_id_is_present() {
        val html = """
            <div id="timetable">
              <div class="column">
                <div class="period" title="Teacher: <b>Jane MacLeod</b>" style="top: 0px; height: 50px;">
                  <div class="inner">
                    <div class="datetime">08:00 - 09:00</div>
                    <div class="title">
                      <a href="/index.php?r=academics/classes/class&amp;class_id=1EA16CECOX&amp;uwc_id=nc16jmac">1EA16CECOX</a>
                    </div>
                  </div>
                </div>
              </div>
            </div>
        """.trimIndent()
        val week = W4TimetableParser.parseWeek(html, year = 2026, week = 35)
        val event = week.days.single().events.single()
        assertEquals("nc16jmac", event.teacherId)
        assertEquals("Jane MacLeod", event.teacher)
    }

    @Test
    fun merge_combines_ac_and_ea_without_dropping_days() {
        val ac = W4TimetableParser.parseWeek(html, 2026, 33, source = "ac")
        val ea = ac.copy(
            days = ac.days.map { day ->
                if (day.date.dayOfMonth == 10) {
                    day.copy(
                        events = listOf(
                            day.events.first().copy(
                                id = "ea-1",
                                title = "Badminton",
                                team = "EA",
                            ),
                        ),
                    )
                } else {
                    day.copy(events = emptyList())
                }
            },
        )
        val merged = W4TimetableParser.mergeWeeks(ac, ea)
        assertEquals(2, merged.days[0].events.size)
        assertEquals(7, merged.days.size)
    }

    @Test
    fun consecutive_same_class_blocks_merge_into_one() {
        val live = javaClass.classLoader!!
            .getResourceAsStream("w4/timetable-live-week.html")!!
            .bufferedReader()
            .readText()
        val secondEcon = """
            <div title="Monday 09:05 - 09:55&lt;br /&gt; Class: &lt;b&gt;Economics&lt;/b&gt;&lt;br /&gt;Teacher: &lt;b&gt;István Poór&lt;/b&gt;&lt;br /&gt;Room: &lt;b&gt;A 1.6&lt;/b&gt;" class="period pt_class first-year ontop" style="background-color: #CAE4FF; top: 126px; height: 49px;">
              <div class="inner">
                <div class="datetime">09:05 - 09:55</div>
                <div class="title">
                  <a href="/index.php?r=academics/classes/class&amp;class_id=1EA16CECOX">1EA16CECOX</a>
                </div>
                <div class="room">Room <a href="/index.php?r=academics/timetable/room&amp;room_id=a16">A 1.6</a></div>
              </div>
            </div>
        """.trimIndent()
        val html = live.replace(
            """<div title="Monday 09:05 - 09:55&lt;br /&gt; Class: &lt;b&gt;Mathematics""",
            "$secondEcon\n    <div title=\"Monday 09:05 - 09:55&lt;br /&gt; Class: &lt;b&gt;Mathematics",
        )
        val week = W4TimetableParser.parseWeek(html, year = 2026, week = 35)
        val econ = week.days[0].events.filter { it.team == "1EA16CECOX" }
        assertEquals(1, econ.size)
        assertEquals(LocalTime.of(8, 15), econ.single().start?.toLocalTime())
        assertEquals(LocalTime.of(9, 55), econ.single().end?.toLocalTime())
        assertEquals("ac-w4-1EA16CECOX", econ.single().id)
    }

    @Test
    fun same_class_later_in_the_day_stays_its_own_block() {
        val day = java.time.LocalDate.of(2026, 8, 24)
        val morning = event(
            id = "ac-w4-1EA16CECOX",
            team = "1EA16CECOX",
            title = "Economics",
            start = LocalDateTime.of(day, LocalTime.of(8, 15)),
            end = LocalDateTime.of(day, LocalTime.of(9, 5)),
            date = day,
        )
        val afternoon = morning.copy(
            start = LocalDateTime.of(day, LocalTime.of(14, 0)),
            end = LocalDateTime.of(day, LocalTime.of(14, 50)),
        )
        val merged = W4TimetableParser.mergeConsecutiveSameClass(listOf(morning, afternoon))
        assertEquals(2, merged.size)
        assertEquals(LocalTime.of(8, 15), merged[0].start?.toLocalTime())
        assertEquals(LocalTime.of(14, 0), merged[1].start?.toLocalTime())
        assertEquals("ac-w4-1EA16CECOX", merged[0].id)
        assertEquals("ac-w4-1EA16CECOX-1400", merged[1].id)
    }

    @Test
    fun cancelled_and_live_same_class_do_not_merge() {
        val day = java.time.LocalDate.of(2026, 8, 24)
        val live = event(
            id = "ac-w4-1EA16CECOX",
            team = "1EA16CECOX",
            title = "Economics",
            start = LocalDateTime.of(day, LocalTime.of(8, 15)),
            end = LocalDateTime.of(day, LocalTime.of(9, 5)),
            date = day,
        )
        val cancelled = live.copy(
            id = "ac-w4-1EA16CECOX-b",
            status = EventStatus.CANCELLED,
            start = LocalDateTime.of(day, LocalTime.of(9, 5)),
            end = LocalDateTime.of(day, LocalTime.of(9, 55)),
        )
        val merged = W4TimetableParser.mergeConsecutiveSameClass(listOf(live, cancelled))
        assertEquals(2, merged.size)
    }

    private fun event(
        id: String,
        team: String,
        title: String,
        start: LocalDateTime,
        end: LocalDateTime,
        date: java.time.LocalDate,
        status: EventStatus = EventStatus.NORMAL,
    ) = ScheduleEvent(
        id = id,
        title = title,
        team = team,
        start = start,
        end = end,
        date = date,
        status = status,
        source = "ac",
    )
}
