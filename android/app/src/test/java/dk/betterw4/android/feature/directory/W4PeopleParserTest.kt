package dk.betterw4.android.feature.directory

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class W4PeopleParserTest {
    private val html = javaClass.classLoader!!
        .getResourceAsStream("w4/people-all.html")!!
        .bufferedReader()
        .readText()

    private val profileHtml = javaClass.classLoader!!
        .getResourceAsStream("w4/site-profile.html")!!
        .bufferedReader()
        .readText()

    @Test
    fun parses_students_and_staff() {
        val people = W4PeopleParser.parse(html)
        assertEquals(3, people.size)
        val jonathan = people.first { it.id == "nc26jban" }
        assertEquals("Jonathan Bangert", jonathan.name)
        assertEquals(DirectoryEntityKind.STUDENT, jonathan.kind)
        assertTrue(jonathan.subtitle!!.contains("Denmark"))
        assertNull(jonathan.avatarUrl)
        val elena = people.first { it.id == "nc25eros" }
        assertEquals("Elena Rossi", elena.name)
        assertTrue(elena.avatarUrl!!.contains("/files/user_photos/nc25eros_thumb.jpg"))
        val staff = people.first { it.id == "nc16jmac" }
        assertEquals(DirectoryEntityKind.TEACHER, staff.kind)
        assertEquals("Jane MacLeod", staff.name)
        assertTrue(staff.avatarUrl!!.contains("/files/user_photos/nc16jmac_thumb.jpg"))
    }

    @Test
    fun name_link_does_not_clobber_photo_url() {
        val people = W4PeopleParser.parse(html)
        val elena = people.first { it.id == "nc25eros" }
        assertTrue(elena.avatarUrl!!.contains("/files/user_photos/"))
        assertTrue(!elena.avatarUrl!!.contains("/photos/nc25eros"))
    }

    @Test
    fun parses_site_profile() {
        val profile = W4PeopleParser.parseProfile(profileHtml)!!
        assertEquals("nc26jban", profile.entity.id)
        assertEquals("Jonathan Bangert", profile.entity.name)
        assertEquals("he/him", profile.pronouns)
        assertEquals("Haugland", profile.house)
        assertEquals("Denmark", profile.country)
        assertEquals("nc26jban@uwcrcn.no", profile.email)
        assertEquals("1", profile.year)
        assertEquals("1 January 2008", profile.birthday)
        assertTrue(profile.entity.subtitle!!.contains("Year 1"))
        assertTrue(profile.entity.avatarUrl!!.contains("/files/user_photos/nc26jban.jpg"))
    }

    @Test
    fun birthday_photos_from_home() {
        val home = """
            <div id="birthdays">
              <li><a href="https://w4.uwcrcn.no/index.php?r=people/students/student&amp;uwc_id=nc25wnas">
                <img class="photo" src="/files/user_photos/nc25wnas_thumb.jpg" alt="Photo of nc25wnas"/>
              </a></li>
            </div>
        """.trimIndent()
        val people = W4PeopleParser.parse(home)
        assertEquals("nc25wnas", people.single().id)
        assertEquals(DirectoryEntityKind.STUDENT, people.single().kind)
        assertTrue(people.single().avatarUrl!!.contains("/files/user_photos/nc25wnas_thumb.jpg"))
    }
}
