package dk.betterw4.android.feature.teachers

import dk.betterw4.android.feature.classes.ClassLevel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class W4TeacherParserTest {
    private val html = javaClass.classLoader!!
        .getResourceAsStream("w4/myteachers.html")!!
        .bufferedReader()
        .readText()

    @Test
    fun lists_teachers_in_document_order() {
        val teachers = W4TeacherParser.parse(html)
        assertEquals(
            listOf("nc00aore", "nc00ccc", "nc00lbro", "wk00lbon", "nc00fff", "nc00mons", "nc00pszy"),
            teachers.map { it.id },
        )
        assertEquals(
            listOf(
                "Avery Ortega",
                "Chris Chen",
                "Lila Brown",
                "Yara Young",
                "Frankie Fossum",
                "Zane Zhao",
                "Priya Shah",
            ),
            teachers.map { it.name },
        )
    }

    @Test
    fun reads_role_caption_and_trailing_level() {
        val teachers = W4TeacherParser.parse(html)
        val core = teachers.first { it.id == "nc00aore" }
        assertEquals("Core meetings", core.role)
        assertEquals(ClassLevel.UNKNOWN, core.level)

        val english = teachers.first { it.id == "nc00lbro" }
        assertEquals("English Language & Literature", english.role)
        assertEquals(ClassLevel.STANDARD, english.level)
        assertEquals("SL", english.displayLevel)

        val math = teachers.first { it.id == "nc00pszy" }
        assertEquals("Mathematics Analysis and Approaches", math.role)
        assertEquals(ClassLevel.HIGHER, math.level)
        assertEquals("HL", math.displayLevel)
    }

    @Test
    fun keeps_non_nc_staff_ids() {
        val danish = W4TeacherParser.parse(html).first { it.id == "wk00lbon" }
        assertEquals("Yara Young", danish.name)
        assertEquals("Danish Literature", danish.role)
        assertEquals(
            "https://w4.uwcrcn.no/files/user_photos/wk00lbon_photo.jpg",
            danish.photoUrl,
        )
    }

    @Test
    fun upgrades_thumb_to_full_portrait() {
        val chris = W4TeacherParser.parse(html).first { it.id == "nc00ccc" }
        assertEquals(
            "https://w4.uwcrcn.no/files/user_photos/nc00ccc_photo.jpg",
            chris.photoUrl,
        )
    }

    @Test
    fun placeholder_photo_is_nil() {
        val html = """
            <div id="content_inner">
              <ul class="user-list">
                <li>
                  <a href="/index.php?r=people/staff/staff&amp;uwc_id=nc00ccc">
                    <img class="photo" src="/images/user.png" alt="Photo of nc00ccc" />
                  </a>
                  <a href="/index.php?r=people/staff/staff&amp;uwc_id=nc00ccc">Chris Chen</a>
                  <br />Advisor group
                </li>
              </ul>
            </div>
        """.trimIndent()
        val teachers = W4TeacherParser.parse(html)
        assertEquals(1, teachers.size)
        assertNull(teachers.first().photoUrl)
        assertEquals("Advisor group", teachers.first().role)
    }

    @Test
    fun staff_id_reads_uwc_id_without_nc_shape() {
        assertEquals(
            "wk00lbon",
            W4TeacherParser.staffId("/index.php?r=people/staff/staff&uwc_id=WK00LBON"),
        )
        assertEquals(
            "nc00ccc",
            W4TeacherParser.staffId(
                "https://w4.uwcrcn.no/index.php?r=people%2Fstaff%2Fstaff&uwc_id=nc00ccc",
            ),
        )
        assertNull(W4TeacherParser.staffId("/index.php?r=site/index"))
    }

    @Test
    fun parse_role_splits_trailing_level() {
        val math = W4TeacherParser.parseRole("Mathematics Analysis and Approaches HL")
        assertEquals("Mathematics Analysis and Approaches", math.first)
        assertEquals(ClassLevel.HIGHER, math.second)

        val english = W4TeacherParser.parseRole("English Language & Literature SL")
        assertEquals("English Language & Literature", english.first)
        assertEquals(ClassLevel.STANDARD, english.second)

        val core = W4TeacherParser.parseRole("Core meetings")
        assertEquals("Core meetings", core.first)
        assertEquals(ClassLevel.UNKNOWN, core.second)

        assertNull(W4TeacherParser.parseRole("").first)
        assertNull(W4TeacherParser.parseRole(null).first)
    }

    @Test
    fun empty_and_garbage_do_not_throw() {
        assertTrue(W4TeacherParser.parse("").isEmpty())
        assertTrue(W4TeacherParser.parse("<html></html>").isEmpty())
        assertTrue(
            W4TeacherParser.parse(
                """<div id="content_inner"><div class="note">No users found</div></div>""",
            ).isEmpty(),
        )
    }

    @Test
    fun each_person_appears_once_despite_two_anchors() {
        val teachers = W4TeacherParser.parse(html)
        assertEquals(teachers.map { it.id }.toSet().size, teachers.size)
    }
}
