package dk.betterw4.android.ui.screens.schedule

import dk.betterw4.android.feature.schedule.EventStatus
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
}
