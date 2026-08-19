package dk.betterw4.android.feature.schedule

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ClassRosterTest {

    @Test
    fun class_id_comes_from_the_brick_href() {
        assertEquals(
            "1EA16CECOX",
            ClassRoster.classId("/index.php?r=academics/classes/class&class_id=1EA16CECOX"),
        )
        assertEquals(
            "1DA13HMTAA",
            ClassRoster.classId("index.php?r=academics/classes/class&class_id=1DA13HMTAA"),
        )
    }

    @Test
    fun team_is_used_when_it_looks_like_a_class_id() {
        assertEquals("1EA16CECOX", ClassRoster.classId(null, "1EA16CECOX"))
        assertNull(ClassRoster.classId(null, "Breakfast"))
        assertNull(ClassRoster.classId(null, "Economics"))
    }

    @Test
    fun breakfast_and_blank_hrefs_have_no_class() {
        assertNull(ClassRoster.classId(null))
        assertNull(ClassRoster.classId(""))
        assertNull(ClassRoster.classId("/index.php?r=academics/timetable/room&room_id=a16"))
    }
}
