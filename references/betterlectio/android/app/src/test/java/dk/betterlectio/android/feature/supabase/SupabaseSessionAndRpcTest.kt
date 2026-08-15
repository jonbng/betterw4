package dk.betterlectio.android.feature.supabase

import kotlinx.coroutines.test.runTest
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SupabaseSessionGateTest {
    @Test
    fun unconfigured_manager_is_unavailable_immediately() = runTest {
        val manager = SupabaseManager(SupabaseConfig("", ""))

        assertEquals(
            SupabaseSessionState.Unavailable(SupabaseUnavailableReason.NOT_CONFIGURED),
            manager.awaitSessionReady(),
        )
    }

    @Test
    fun configured_gate_does_not_treat_timeout_as_ready() = runTest {
        val gate = SupabaseSessionGate(enabled = true)

        assertEquals(
            SupabaseSessionState.Unavailable(SupabaseUnavailableReason.TIMEOUT),
            gate.await(timeoutMs = 1),
        )

        gate.complete(SupabaseSessionState.Ready)
        assertEquals(SupabaseSessionState.Ready, gate.await(timeoutMs = 1))
    }
}

class SupabaseScheduleRpcPayloadTest {
    private val json = Json

    @Test
    fun week_sync_payload_uses_rpc_parameter_names_and_server_owned_week_key() {
        val payload = SupabaseScheduleService.SyncWeekParams(
            studentId = "123",
            weekKey = "2026-W31",
            lessons = listOf(
                SupabaseScheduleService.SupabaseLessonRecord(
                    lessonKey = "lesson-1",
                    lessonDate = "2026-07-27",
                    startTime = "08:00",
                    endTime = "09:30",
                    title = "Matematik",
                    status = "normal",
                    sourceUpdatedAt = "2026-07-27T08:00:00.000Z",
                ),
            ),
        )

        val encoded = json.parseToJsonElement(json.encodeToString(payload)).jsonObject
        assertEquals("123", encoded.getValue("p_student_id").jsonPrimitive.content)
        assertEquals("2026-W31", encoded.getValue("p_week_key").jsonPrimitive.content)
        val lesson = encoded.getValue("p_lessons").jsonArray.single().jsonObject
        assertEquals("lesson-1", lesson.getValue("lesson_key").jsonPrimitive.content)
        assertFalse("week_key" in lesson)
        assertFalse("updated_at" in lesson)
    }

    @Test
    fun content_update_payload_uses_ownership_validating_rpc_parameters() {
        val payload = SupabaseScheduleService.UpdateLessonContentParams(
            studentId = "123",
            lessonKey = "lesson-1",
            content = SupabaseScheduleService.LessonContentPayload(teacherNote = "Note"),
            clientUpdatedAt = "2026-07-27T08:00:00.000Z",
        )

        val encoded = json.parseToJsonElement(json.encodeToString(payload)).jsonObject
        assertTrue("p_student_id" in encoded)
        assertTrue("p_lesson_key" in encoded)
        assertTrue("p_content" in encoded)
        assertTrue("p_client_updated_at" in encoded)
    }
}
