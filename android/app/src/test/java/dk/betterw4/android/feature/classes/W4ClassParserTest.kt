package dk.betterw4.android.feature.classes

import dk.betterw4.android.feature.directory.DirectoryEntityKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class W4ClassParserTest {
    private val indexHtml = javaClass.classLoader!!
        .getResourceAsStream("w4/myclasses.html")!!
        .bufferedReader()
        .readText()

    private val mathHtml = javaClass.classLoader!!
        .getResourceAsStream("w4/class-mtaa.html")!!
        .bufferedReader()
        .readText()

    private val econHtml = javaClass.classLoader!!
        .getResourceAsStream("w4/class-ecox.html")!!
        .bufferedReader()
        .readText()

    @Test
    fun index_lists_classes_in_document_order() {
        val classes = W4ClassParser.parseIndex(indexHtml)
        assertEquals(
            listOf("1ZAUDXCORE", "1EA16CECOX", "1YA25SLALI", "1DA13HMTAA"),
            classes.map { it.id },
        )
        assertEquals(
            listOf("Core meetings", "Economics", "English Language & Literature", "Mathematics Analysis and Approaches"),
            classes.map { it.subject },
        )
        assertTrue(classes.none { it.loaded })
    }

    @Test
    fun caption_reads_teacher_from_with_clause() {
        val parsed = W4ClassParser.parseCaption(
            "1EA16CECOX: Economics 1st Year C level with Mona Eide Onstad in room A 1.6",
        )!!
        assertEquals("Economics", parsed.subject)
        assertEquals("1", parsed.year)
        assertEquals(ClassLevel.COMBINED, parsed.level)
        assertEquals("Mona Eide Onstad", parsed.teacher)
        assertEquals("A 1.6", parsed.room)
    }

    @Test
    fun index_reads_level_teacher_and_room_from_the_caption() {
        val classes = W4ClassParser.parseIndex(indexHtml)
        val math = classes.first { it.id == "1DA13HMTAA" }
        assertEquals(ClassLevel.HIGHER, math.level)
        assertEquals("HL", math.displayLevel)
        assertEquals("1", math.year)
        assertEquals("D", math.block)
        assertEquals("MTAA", math.subjectCode)
        assertEquals("Jens Jensen", math.teacherNames)
        assertEquals("A 1.3", math.room?.name)
        assertNull(math.room?.id)

        val english = classes.first { it.id == "1YA25SLALI" }
        assertEquals(ClassLevel.STANDARD, english.level)
        assertEquals("SL", english.displayLevel)
        assertEquals("Liusaidh Brown", english.teacherNames)

        val econ = classes.first { it.id == "1EA16CECOX" }
        assertEquals(ClassLevel.COMBINED, econ.level)
        assertEquals("HL/SL", econ.displayLevel)

        val core = classes.first { it.id == "1ZAUDXCORE" }
        assertEquals(ClassLevel.NONE, core.level)
        assertEquals("", core.displayLevel)
        assertEquals("Auditorium", core.room?.name)
    }

    @Test
    fun class_page_reads_details_teacher_and_students() {
        val item = W4ClassParser.parseClass(mathHtml)
        assertEquals("1DA13HMTAA", item.id)
        assertEquals("Mathematics Analysis and Approaches", item.subject)
        assertEquals("MTAA", item.subjectCode)
        assertEquals("1", item.year)
        assertEquals("D", item.block)
        assertEquals(ClassLevel.HIGHER, item.level)
        assertEquals("HL", item.displayLevel)
        assertEquals("a13", item.room?.id)
        assertEquals("A 1.3", item.room?.name)
        assertTrue(item.loaded)

        val teacher = item.teachers.single()
        assertEquals("nc00jjen", teacher.id)
        assertEquals("Jens Jensen", teacher.name)
        assertEquals(DirectoryEntityKind.TEACHER, teacher.kind)
        assertTrue(teacher.photoUrl!!.contains("/files/user_photos/nc00jjen_photo.jpg"))

        assertEquals(listOf("nc00aaa", "nc00bbb", "nc00ccc"), item.students.map { it.id })
        assertEquals("Alex Andersen", item.students.first().name)
        assertEquals(DirectoryEntityKind.STUDENT, item.students.first().kind)
        assertTrue(item.students.first().photoUrl!!.contains("/files/user_photos/nc00aaa_photo.jpg"))
        assertNull(item.students.first { it.id == "nc00bbb" }.photoUrl)
    }

    @Test
    fun combined_class_keeps_per_student_hl_sl_overlay() {
        val item = W4ClassParser.parseClass(econHtml)
        assertEquals(ClassLevel.COMBINED, item.level)
        assertEquals("Combined", item.levelLabel)
        assertEquals("Economics", item.subject)
        assertEquals(ClassLevel.HIGHER, item.students.first { it.id == "nc00ddd" }.level)
        assertEquals(ClassLevel.STANDARD, item.students.first { it.id == "nc00eee" }.level)
        assertEquals("HL", item.students.first { it.id == "nc00ddd" }.entity.subtitle)
    }

    @Test
    fun merge_prefers_list_subject_name_and_detail_roster() {
        val listed = W4ClassParser.parseIndex(indexHtml).first { it.id == "1DA13HMTAA" }
        val detail = W4ClassParser.parseClass(mathHtml)
        val merged = W4ClassParser.merge(listed, detail)
        assertEquals("Mathematics Analysis and Approaches", merged.subject)
        assertEquals("nc00jjen", merged.teachers.single().id)
        assertEquals(3, merged.students.size)
        assertEquals("a13", merged.room?.id)
        assertTrue(merged.loaded)
        assertFalse(listed.loaded)
    }

    @Test
    fun class_id_and_room_id_are_sibling_query_keys() {
        assertEquals(
            "1DA13HMTAA",
            W4ClassParser.classIdFromHref("/index.php?r=academics/classes/class&class_id=1DA13HMTAA"),
        )
        assertEquals(
            "a13",
            W4ClassParser.roomIdFromHref("/index.php?r=academics/timetable/room&room_id=a13"),
        )
    }

    @Test
    fun level_parse_accepts_hl_sl_and_w4_letters() {
        assertEquals(ClassLevel.HIGHER, ClassLevel.parse("H Higher"))
        assertEquals(ClassLevel.STANDARD, ClassLevel.parse("SL"))
        assertEquals(ClassLevel.COMBINED, ClassLevel.parse("C Combined"))
        assertEquals(ClassLevel.COMBINED, ClassLevel.parse("HL/SL"))
        assertEquals(ClassLevel.NONE, ClassLevel.parse("X None"))
        assertEquals(ClassLevel.UNKNOWN, ClassLevel.parse(""))
    }

    @Test
    fun only_real_uwc_member_ids_can_open_profiles() {
        val teacher = ClassMember("teacher-jane-doe", "Jane Doe", DirectoryEntityKind.TEACHER)
        val malformed = ClassMember("some-caption", "Some Caption", DirectoryEntityKind.STUDENT)
        val student = ClassMember("nc26abcd", "A Student", DirectoryEntityKind.STUDENT)

        assertFalse(teacher.canOpenProfile)
        assertFalse(malformed.canOpenProfile)
        assertTrue(student.canOpenProfile)
    }
}
