package dk.betterlectio.android.feature.supabase

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.LocalDate

class SupabaseConfigTest {
    @Test
    fun config_not_configured_when_empty() {
        val c = SupabaseConfig("", "")
        assertFalse(c.isConfigured)
    }

    @Test
    fun config_configured_with_url_and_key() {
        val c = SupabaseConfig("https://example.supabase.co", "eyJhbGciOi")
        assertTrue(c.isConfigured)
    }

    @Test
    fun config_rejects_placeholder() {
        val c = SupabaseConfig("https://YOUR_PROJECT.supabase.co", "YOUR_KEY")
        assertFalse(c.isConfigured)
    }
}

class ScheduleIdentityTest {
    @Test
    fun weekKey_formats_iso() {
        assertEquals("2026-W10", ScheduleIdentity.weekKey(2026, 10))
    }

    @Test
    fun lessonKey_uses_event_id_when_present() {
        val event = dk.betterlectio.android.feature.schedule.ScheduleEvent(
            id = "ABS123",
            title = "Mat",
            date = LocalDate.of(2026, 3, 10),
        )
        assertEquals("ABS123", ScheduleIdentity.lessonKey(event, "42"))
    }
}

class SupabaseHomeworkParseTest {
    @Test
    fun parseTimestamp_iso() {
        val t = SupabaseHomeworkService.parseTimestamp("2026-03-10T12:00:00.000Z")
        assertEquals(Instant.parse("2026-03-10T12:00:00.000Z"), t)
    }

    @Test
    fun parseDay_iso() {
        assertEquals(LocalDate.of(2026, 3, 10), SupabaseHomeworkService.parseDay("2026-03-10"))
    }

    @Test
    fun isSyncable_numeric_only() {
        assertTrue(SupabaseHomeworkService.isSyncableEntryId("123456"))
        assertFalse(SupabaseHomeworkService.isSyncableEntryId(""))
        assertFalse(SupabaseHomeworkService.isSyncableEntryId("ABS123"))
        assertFalse(SupabaseHomeworkService.isSyncableEntryId("12a"))
    }
}

class LessonContentPayloadTest {
    @Test
    fun fromDetail_maps_homework_and_blocks() {
        val detail = dk.betterlectio.android.feature.schedule.LessonDetail(
            eventId = "99",
            title = "Mat",
            note = "Lærer note",
            homework = "Læs s. 12",
            contentBlocks = listOf(
                dk.betterlectio.android.feature.schedule.LessonContentBlock("paragraph", "Mere"),
            ),
        )
        val payload = SupabaseScheduleService.LessonContentPayload.fromDetail(detail)
        assertEquals("Lærer note", payload.teacherNote)
        assertTrue(payload.items.any { it.isHomework })
        assertTrue(payload.items.any { !it.isHomework })
    }
}

class SupabaseSubjectColorTest {
    @Test
    fun hue_roundtrip_roughly_stable() {
        val argb = SupabaseSubjectService.hueToArgb(210)
        val hue = SupabaseSubjectService.argbToHue(argb)
        // Allow a few degrees of conversion error
        assertTrue(kotlin.math.abs(hue - 210) < 15)
    }
}
