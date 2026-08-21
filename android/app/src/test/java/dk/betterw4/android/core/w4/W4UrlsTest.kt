package dk.betterw4.android.core.w4

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class W4UrlsTest {

    @Test
    fun route_keeps_slash_unencoded_and_extra_params_are_siblings() {
        val url = W4Urls.route(
            W4Urls.Routes.STUDENT_PROFILE,
            mapOf("uwc_id" to "nc26jban"),
        )
        assertEquals("w4.uwcrcn.no", url.host)
        assertEquals("/index.php", url.encodedPath)
        assertEquals("people/students/student", url.queryParameter("r"))
        assertEquals("nc26jban", url.queryParameter("uwc_id"))
        assertEquals(setOf("r", "uwc_id"), url.queryParameterNames)
        assertTrue(url.toString().contains("r=people/students/student"))
        assertFalse(url.queryParameter("r")!!.contains("uwc_id"))
    }

    @Test
    fun resolve_splits_inline_ampersand_query_out_of_r() {
        val url = W4Urls.resolve("people/students/student&uwc_id=nc26jban")
        assertEquals("people/students/student", url.queryParameter("r"))
        assertEquals("nc26jban", url.queryParameter("uwc_id"))
        assertEquals("people/students/student", W4Urls.routeOf(url))
    }

    @Test
    fun person_timetable_query_is_sibling_keys_not_stuffed_in_r() {
        val url = W4Urls.route(
            W4Urls.Routes.PERSON_TIMETABLE_INDEX,
            mapOf("uwc_id" to "nc25eros", "year" to "2026", "week" to "35"),
        )
        assertEquals("academics/timetable/timetable/index", url.queryParameter("r"))
        assertEquals("nc25eros", url.queryParameter("uwc_id"))
        assertEquals("2026", url.queryParameter("year"))
        assertEquals("35", url.queryParameter("week"))
        assertFalse(url.queryParameter("r")!!.contains("uwc_id"))
    }

    @Test
    fun by_house_query_is_a_sibling_key() {
        val url = W4Urls.route(
            W4Urls.Routes.STUDENTS_BY_HOUSE_INDEX,
            mapOf("house_id" to "denmark"),
        )
        assertEquals("people/students/byhouse/index", url.queryParameter("r"))
        assertEquals("denmark", url.queryParameter("house_id"))
        assertFalse(url.queryParameter("r")!!.contains("house_id"))
    }

    @Test
    fun on_duty_route_is_a_sibling_query() {
        val url = W4Urls.route(W4Urls.Routes.ON_DUTY)
        assertEquals("people/onduty", url.queryParameter("r"))
        val schedule = W4Urls.route(W4Urls.Routes.ON_DUTY_SCHEDULE)
        assertEquals("people/onduty/schedule", schedule.queryParameter("r"))
    }

    @Test
    fun birthdays_month_query_is_a_sibling_key() {
        val url = W4Urls.route(
            W4Urls.Routes.BIRTHDAYS_INDEX,
            mapOf("month" to "8", "year" to "2026"),
        )
        assertEquals("people/birthdays/index", url.queryParameter("r"))
        assertEquals("8", url.queryParameter("month"))
        assertEquals("2026", url.queryParameter("year"))
        assertFalse(url.queryParameter("r")!!.contains("month"))
    }

    @Test
    fun class_page_query_is_a_sibling_key() {
        val url = W4Urls.route(
            W4Urls.Routes.CLASS,
            mapOf("class_id" to "1EA16CECOX"),
        )
        assertEquals("academics/classes/class", url.queryParameter("r"))
        assertEquals("1EA16CECOX", url.queryParameter("class_id"))
        assertFalse(url.queryParameter("r")!!.contains("class_id"))
        val list = W4Urls.route(W4Urls.Routes.MY_CLASSES)
        assertEquals("academics/classes/myclasses", list.queryParameter("r"))
    }

    @Test
    fun student_helper_matches_captured_profile_links() {
        val url = W4Urls.student("nc26jban")
        assertEquals(
            "https://w4.uwcrcn.no/index.php?r=people/students/student&uwc_id=nc26jban",
            url.toString(),
        )
    }

    @Test
    fun routeOf_decodes_percent_encoded_r() {
        assertEquals(
            "site/login",
            W4Urls.routeOf("https://w4.uwcrcn.no/index.php?r=site%2Flogin"),
        )
        assertEquals(
            "site/otp",
            W4Urls.routeOf("https://w4.uwcrcn.no/index.php?r=site/otp"),
        )
        assertEquals(
            "site/verify2fa",
            W4Urls.routeOf("https://w4.uwcrcn.no/index.php?r=site/verify2fa"),
        )
        assertNull(W4Urls.routeOf("https://w4.uwcrcn.no/"))
    }

    @Test
    fun resolve_absolute_and_index_paths() {
        val absolute = W4Urls.resolve("https://w4.uwcrcn.no/index.php?r=site/login")
        assertEquals("site/login", W4Urls.routeOf(absolute))
        val path = W4Urls.resolve("/index.php?r=academics/timetable/mytimetable")
        assertEquals(W4Urls.Routes.MY_TIMETABLE, W4Urls.routeOf(path))
        val index = W4Urls.resolve("index.php?r=site/index")
        assertEquals(W4Urls.Routes.HOME, W4Urls.routeOf(index))
    }
}
