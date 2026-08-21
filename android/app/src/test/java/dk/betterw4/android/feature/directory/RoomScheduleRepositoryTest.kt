package dk.betterw4.android.feature.directory

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RoomScheduleRepositoryTest {

    @Test
    fun person_and_room_cache_keys_do_not_collide_with_own_schedule() {
        assertEquals(
            "person_schedule_nc25eros_2026_35",
            dk.betterw4.android.feature.schedule.TimetableWeekCache.personAcKey("nc25eros", 2026, 35),
        )
        assertEquals(
            "room_schedule_a16_2026_34",
            dk.betterw4.android.feature.schedule.TimetableWeekCache.roomAcKey("a16", 2026, 34),
        )
        assertEquals(
            "schedule_nc26test_2026_35",
            dk.betterw4.android.feature.schedule.TimetableWeekCache.ownAcKey("nc26test", 2026, 35),
        )
    }

    @Test
    fun week_query_puts_id_year_and_week_as_siblings() {
        assertEquals(
            mapOf("uwc_id" to "nc25eros", "year" to "2026", "week" to "35"),
            W4TimetableTargets.weekQuery("uwc_id", "nc25eros", 2026, 35),
        )
        assertEquals(
            mapOf("room_id" to "a16", "year" to "2026", "week" to "34"),
            W4TimetableTargets.weekQuery("room_id", "a16", 2026, 34),
        )
    }

    @Test
    fun uwc_id_normalizes_and_rejects_junk() {
        assertEquals("nc25eros", W4TimetableTargets.uwcId("nc25eros"))
        assertEquals("nc16jmac", W4TimetableTargets.uwcId("NC16JMAC"))
        assertEquals("nc25eros", W4TimetableTargets.uwcId("  nc25eros  "))
        assertNull(W4TimetableTargets.uwcId(""))
        assertNull(W4TimetableTargets.uwcId("A 1.6"))
    }

    @Test
    fun room_id_keeps_named_rooms_and_compacts_classrooms() {
        assertEquals("a16", W4TimetableTargets.roomId("a16"))
        assertEquals("a16", W4TimetableTargets.roomId("A 1.6"))
        assertEquals("e11", W4TimetableTargets.roomId("E 1.1"))
        assertEquals("Lib", W4TimetableTargets.roomId("Lib"))
        assertEquals("TR", W4TimetableTargets.roomId("TR"))
        assertEquals("", W4TimetableTargets.roomId("  "))
    }
}
