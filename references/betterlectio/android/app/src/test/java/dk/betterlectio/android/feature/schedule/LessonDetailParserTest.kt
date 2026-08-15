package dk.betterlectio.android.feature.schedule

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LessonDetailParserTest {
    @Test
    fun parses_lesson_detail_fixture() {
        val html = javaClass.classLoader!!
            .getResourceAsStream("lectio/fixtures/lesson_detail.html")!!
            .bufferedReader().readText()
        val detail = LessonDetailParser.parse(html, "111", "Fallback")

        assertTrue(detail.note?.contains("regnemaskine") == true)
        assertEquals("HE4242", detail.holdId)
        assertTrue(detail.title.isNotBlank())

        val homework = detail.contentBlocks.filter { it.isHomework }
        val other = detail.contentBlocks.filter { !it.isHomework }
        assertTrue("expected homework blocks", homework.isNotEmpty())
        assertTrue(homework.any { it.text.contains("Opgaver") || it.text.contains("bogen") })
        assertTrue("expected other-content blocks", other.isNotEmpty())
        assertTrue(other.any { it.text.contains("opsamling") || it.text.contains("I timen") })

        assertTrue(detail.resources.any { it.title.contains("Opgavesæt") || it.isFile })
        val images = detail.contentBlocks.filter { it.kind == "image" }
        assertTrue("expected image content block from fixture", images.isNotEmpty())
        assertTrue(images.any { it.url?.contains("documentid=55") == true })

        // Participants come from members.aspx — never from detail HTML
        assertTrue(detail.participants.isEmpty())
        assertFalse(detail.contentBlocks.any { it.text.contains("Jens Jensen") })
    }

    @Test
    fun teacher_note_preserved_when_no_homework() {
        val html = """
            <div id="homeworkContentContainer" class="ls-paper">
              <div id="s_m_Content_Content_tocAndToolbar_actHeader">
                <textarea name="ActNoteTB" class="activity-note">Vi skal diskutere klimakrisen.</textarea>
              </div>
              <div id="s_m_Content_Content_tocAndToolbar_inlineHomeworkDiv">
                <p class="ls-hidden-smallscreen">Aktiviteten har ikke noget indhold.</p>
              </div>
            </div>
        """.trimIndent()
        val detail = LessonDetailParser.parse(html, "ABS99", "Fallback")
        assertEquals("Vi skal diskutere klimakrisen.", detail.note)
        assertTrue(detail.contentBlocks.isEmpty())
        assertNull(detail.homework)
    }

    @Test
    fun hold_id_from_context_card_fallback() {
        val html = """
            <div data-lectiocontextcard="HE777">Ma A</div>
            <div id="homeworkContentContainer">
              <div id="s_m_Content_Content_tocAndToolbar_inlineHomeworkDiv">
                <p>Aktiviteten har ikke noget indhold.</p>
              </div>
            </div>
        """.trimIndent()
        val detail = LessonDetailParser.parse(html, "1", "T")
        assertEquals("HE777", detail.holdId)
    }

    @Test
    fun private_event_draft_shape_is_usable() {
        val draft = PrivateEventDraft(
            title = "Læge",
            startDate = "10/07-2026",
            startTime = "10:00",
            endDate = "10/07-2026",
            endTime = "11:00",
            note = "Check-up",
        )
        assertEquals("Læge", draft.title)
        assertTrue(draft.startDate.contains("-2026"))
    }

    @Test
    fun participant_from_directory_maps_role_and_avatar() {
        val entity = dk.betterlectio.android.feature.directory.DirectoryEntity(
            id = "S10",
            name = "Anna Andersen",
            kind = dk.betterlectio.android.feature.directory.DirectoryEntityKind.STUDENT,
            subtitle = "3x",
            avatarUrl = "https://example.com/a.jpg",
        )
        val p = LessonParticipant.fromDirectory(entity)
        assertEquals("S10", p.id)
        assertEquals("Elev", p.role)
        assertEquals("https://example.com/a.jpg", p.avatarUrl)
    }
}
