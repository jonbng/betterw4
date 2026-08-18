package dk.betterw4.android.ui.screens.schedule

import dk.betterw4.android.feature.schedule.EventStatus
import dk.betterw4.android.feature.schedule.SCHOOL_CALENDAR_TEAM_TOKEN
import dk.betterw4.android.feature.schedule.ScheduleEvent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime

class TimelineOverlapTest {
    private val day = LocalDate.of(2026, 8, 17)

    private fun event(
        id: String,
        startH: Int,
        startM: Int,
        endH: Int,
        endM: Int,
        status: EventStatus,
        title: String = id,
    ) = ScheduleEvent(
        id = id,
        title = title,
        start = LocalDateTime.of(day, LocalTime.of(startH, startM)),
        end = LocalDateTime.of(day, LocalTime.of(endH, endM)),
        date = day,
        status = status,
    )

    @Test
    fun cancelled_leftover_keeps_narrow_strip_beside_changed_lesson() {
        val historie = event("hi", 12, 35, 13, 50, EventStatus.CHANGED, "2bs HI")
        val math = event("ma", 12, 35, 13, 50, EventStatus.CANCELLED, "2bs(en) Ma")
        val layouts = calculateOverlapLayouts(listOf(historie, math), day, dayStartHour = 8)

        assertEquals(2, layouts.size)
        val hi = layouts.first { it.event.id == "hi" }
        val ma = layouts.first { it.event.id == "ma" }
        val hiPlace = overlapPlacement(hi, layouts)
        val maPlace = overlapPlacement(ma, layouts)

        assertEquals(0.70f, hiPlace.widthFraction, 0.001f)
        assertEquals(0.00f, hiPlace.xFraction, 0.001f)
        assertEquals(0.30f, maPlace.widthFraction, 0.001f)
        assertEquals(0.70f, maPlace.xFraction, 0.001f)
        assertTrue(hiPlace.xFraction + hiPlace.widthFraction <= maPlace.xFraction + 0.001f)
    }

    @Test
    fun two_live_overlaps_split_equally() {
        val a = event("a", 8, 0, 9, 15, EventStatus.NORMAL)
        val b = event("b", 8, 0, 9, 15, EventStatus.CHANGED)
        val layouts = calculateOverlapLayouts(listOf(a, b), day, dayStartHour = 8)
        val places = layouts.map { overlapPlacement(it, layouts) }

        assertEquals(2, places.size)
        assertEquals(0.5f, places[0].widthFraction, 0.001f)
        assertEquals(0.5f, places[1].widthFraction, 0.001f)
        assertEquals(1.0f, places.sumOf { it.widthFraction.toDouble() }.toFloat(), 0.001f)
    }

    @Test
    fun solo_lesson_uses_full_width() {
        val only = event("ke", 13, 55, 15, 10, EventStatus.NORMAL)
        val layouts = calculateOverlapLayouts(listOf(only), day, dayStartHour = 8)
        val place = overlapPlacement(layouts.single(), layouts)
        assertEquals(0f, place.xFraction, 0.001f)
        assertEquals(1f, place.widthFraction, 0.001f)
    }

    @Test
    fun school_calendar_yields_the_primary_column_to_a_lesson() {
        val lesson = event("ac-w4-econ", 8, 15, 9, 5, EventStatus.NORMAL, "Economics")
        val calendar = event("gcal-assembly", 8, 0, 12, 0, EventStatus.NORMAL, "Assembly").copy(
            team = SCHOOL_CALENDAR_TEAM_TOKEN,
            source = "gcal",
        )
        val layouts = calculateOverlapLayouts(listOf(calendar, lesson), day, dayStartHour = 8)
        val lessonLayout = layouts.first { it.event.id == "ac-w4-econ" }
        val calendarLayout = layouts.first { it.event.id == "gcal-assembly" }

        val lessonPlace = overlapPlacement(lessonLayout, layouts)
        val calendarPlace = overlapPlacement(calendarLayout, layouts)
        assertEquals(0.70f, lessonPlace.widthFraction, 0.001f)
        assertEquals(0.00f, lessonPlace.xFraction, 0.001f)
        assertEquals(0.30f, calendarPlace.widthFraction, 0.001f)
        assertEquals(0.70f, calendarPlace.xFraction, 0.001f)
    }

    @Test
    fun adjacent_break_stays_full_width_between_lessons() {
        val math = event("ma", 9, 5, 9, 55, EventStatus.NORMAL, "Mathematics")
        val pause = event("br", 9, 55, 10, 10, EventStatus.NORMAL, "Break")
        val tok = event("tok", 10, 10, 11, 30, EventStatus.NORMAL, "TOK")
        val layouts = calculateOverlapLayouts(listOf(math, pause, tok), day, dayStartHour = 8)

        val places = layouts.associate { it.event.id to overlapPlacement(it, layouts) }
        assertEquals(1f, places.getValue("ma").widthFraction, 0.001f)
        assertEquals(1f, places.getValue("br").widthFraction, 0.001f)
        assertEquals(1f, places.getValue("tok").widthFraction, 0.001f)

        val br = layouts.first { it.event.id == "br" }
        assertEquals(15, br.endMin - br.startMin)
        assertEquals(br.endMin, visualEndMin(br, layouts))
    }

    @Test
    fun isolated_short_block_grows_visually_without_inventing_overlap() {
        val pause = event("br", 9, 55, 10, 10, EventStatus.NORMAL, "Break")
        val layouts = calculateOverlapLayouts(listOf(pause), day, dayStartHour = 8)
        val br = layouts.single()
        val place = overlapPlacement(br, layouts)

        assertEquals(1f, place.widthFraction, 0.001f)
        assertEquals(15, br.endMin - br.startMin)
        assertEquals(br.startMin + 30, visualEndMin(br, layouts))
    }

    @Test
    fun short_block_grows_only_into_the_gap_before_the_next_lesson() {
        val pause = event("br", 9, 55, 10, 10, EventStatus.NORMAL, "Break")
        val tok = event("tok", 10, 20, 11, 30, EventStatus.NORMAL, "TOK")
        val layouts = calculateOverlapLayouts(listOf(pause, tok), day, dayStartHour = 8)
        val br = layouts.first { it.event.id == "br" }
        val tokLayout = layouts.first { it.event.id == "tok" }

        assertEquals(1f, overlapPlacement(br, layouts).widthFraction, 0.001f)
        assertEquals(tokLayout.startMin, visualEndMin(br, layouts))
        assertEquals(10, visualEndMin(br, layouts) - br.endMin)
    }

    @Test
    fun school_calendar_before_a_lesson_keeps_full_width() {
        val calendar = event("gcal-briefing", 7, 30, 8, 0, EventStatus.NORMAL, "Briefing").copy(
            team = SCHOOL_CALENDAR_TEAM_TOKEN,
            source = "gcal",
        )
        val lesson = event("ac-w4-econ", 8, 15, 9, 5, EventStatus.NORMAL, "Economics")
        val layouts = calculateOverlapLayouts(listOf(calendar, lesson), day, dayStartHour = 7)
        val places = layouts.associate { it.event.id to overlapPlacement(it, layouts) }
        assertEquals(1f, places.getValue("gcal-briefing").widthFraction, 0.001f)
        assertEquals(1f, places.getValue("ac-w4-econ").widthFraction, 0.001f)
    }
}
