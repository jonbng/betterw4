package dk.betterw4.android.feature.schedule

import dk.betterw4.android.core.cache.CachedValue
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TimetableWeekCacheTest {

    @Test
    fun keys_keep_own_schedule_ac_stable_and_namespace_person_weeks() {
        assertEquals("schedule_nc26test_2026_35", TimetableWeekCache.ownAcKey("nc26test", 2026, 35))
        assertEquals("schedule_ea_nc26test_2026_35", TimetableWeekCache.ownEaKey("nc26test", 2026, 35))
        assertEquals("person_schedule_nc25eros_2026_35", TimetableWeekCache.personAcKey("nc25eros", 2026, 35))
        assertEquals("person_schedule_ea_nc25eros_2026_35", TimetableWeekCache.personEaKey("nc25eros", 2026, 35))
        assertEquals("room_schedule_a16_2026_34", TimetableWeekCache.roomAcKey("a16", 2026, 34))
    }

    @Test
    fun mergeHtml_parses_ac_and_overlays_ea() {
        val ac = javaClass.classLoader!!
            .getResourceAsStream("w4/timetable-week.html")!!
            .bufferedReader()
            .readText()
        val acOnly = TimetableWeekCache.mergeHtml(ac, null, 2026, 33)
        assertNotNull(acOnly)
        assertEquals("Biology HL", acOnly!!.days[0].events.single().title)

        val merged = TimetableWeekCache.mergeHtml(ac, ac, 2026, 33)
        assertNotNull(merged)
        assertTrue(merged!!.days[0].events.size >= 1)
    }

    @Test
    fun isFresh_follows_timetable_ttl() {
        val now = System.currentTimeMillis()
        val fresh = CachedValue("<html/>", now - 5 * 60_000L)
        val stale = CachedValue("<html/>", now - 40 * 60_000L)
        assertTrue(TimetableWeekCache.isFresh(fresh, null))
        assertFalse(TimetableWeekCache.isFresh(stale, null))
        assertFalse(TimetableWeekCache.isFresh(fresh, stale))
        assertTrue(TimetableWeekCache.isFresh(fresh, fresh))
    }
}
