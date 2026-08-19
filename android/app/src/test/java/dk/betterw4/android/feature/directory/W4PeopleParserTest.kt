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

    private val classHtml = javaClass.classLoader!!
        .getResourceAsStream("w4/class-mtaa.html")!!
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
        assertEquals("1", jonathan.year)
        assertNull(jonathan.avatarUrl)
        val elena = people.first { it.id == "nc25eros" }
        assertEquals("Elena Rossi", elena.name)
        assertEquals("2", elena.year)
        assertTrue(elena.avatarUrl!!.contains("/files/user_photos/nc25eros_photo.jpg"))
        val staff = people.first { it.id == "nc16jmac" }
        assertEquals(DirectoryEntityKind.TEACHER, staff.kind)
        assertEquals("Jane MacLeod", staff.name)
        assertTrue(staff.avatarUrl!!.contains("/files/user_photos/nc16jmac_photo.jpg"))
    }

    @Test
    fun name_link_does_not_clobber_photo_url() {
        val people = W4PeopleParser.parse(html)
        val elena = people.first { it.id == "nc25eros" }
        assertTrue(elena.avatarUrl!!.contains("/files/user_photos/"))
        assertTrue(!elena.avatarUrl!!.contains("/photos/nc25eros"))
    }

    @Test
    fun parses_class_roster_teachers_and_students() {
        val people = W4PeopleParser.parse(classHtml)
        assertEquals(listOf("nc00jjen", "nc00aaa", "nc00bbb", "nc00ccc"), people.map { it.id })
        assertEquals(DirectoryEntityKind.TEACHER, people.first().kind)
        assertEquals("Jens Jensen", people.first().name)
        assertEquals(DirectoryEntityKind.STUDENT, people[1].kind)
        assertEquals("Alex Andersen", people[1].name)
        assertNull(people.first { it.id == "nc00bbb" }.avatarUrl)
    }

    @Test
    fun class_roster_ignores_user_panel_chrome() {
        val wrapped = """
            <div id="user-panel">
              <a href="/index.php?r=people/students/student&amp;uwc_id=nc26jban">Welcome, Jonathan</a>
            </div>
            $classHtml
        """.trimIndent()
        val people = W4PeopleParser.parse(wrapped)
        assertTrue(people.none { it.id == "nc26jban" })
        assertEquals(4, people.size)
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
        assertTrue(profile.entity.avatarUrl!!.contains("/files/user_photos/nc26jban_photo.jpg"))
    }

    @Test
    fun upgrades_list_thumb_and_bare_jpg_to_photo() {
        assertEquals(
            "https://w4.uwcrcn.no/files/user_photos/nc25eros_photo.jpg",
            W4PeopleParser.fullSizePhotoUrl(
                "https://w4.uwcrcn.no/files/user_photos/nc25eros_thumb.jpg",
            ),
        )
        assertEquals(
            "https://w4.uwcrcn.no/files/user_photos/nc25eros_photo.jpg",
            W4PeopleParser.fullSizePhotoUrl(
                "https://w4.uwcrcn.no/files/user_photos/nc25eros.jpg",
            ),
        )
        assertEquals(
            "https://w4.uwcrcn.no/files/user_photos/nc25eros_photo.jpg",
            W4PeopleParser.fullSizePhotoUrl(
                "https://w4.uwcrcn.no/files/user_photos/nc25eros_photo.jpg",
            ),
        )
        assertEquals(
            "https://w4.uwcrcn.no/files/user_photos/nc25eros_photo.jpg",
            W4PeopleParser.guessPhotoUrl("nc25eros"),
        )
    }

    @Test
    fun parses_staff_profile_for_students() {
        val html = javaClass.classLoader!!
            .getResourceAsStream("w4/staff-profile.html")!!
            .bufferedReader()
            .readText()
        val profile = W4PeopleParser.parseProfile(html, DirectoryEntityKind.TEACHER)!!
        assertEquals("nc00ccc", profile.entity.id)
        assertEquals("Chris Chen", profile.entity.name)
        assertEquals(DirectoryEntityKind.TEACHER, profile.entity.kind)
        assertEquals("chris.chen@uwcrcn.no", profile.email)
        assertEquals("China", profile.country)
        assertEquals("7022", profile.officeTel)
        assertEquals("40432379", profile.mobile)
        assertEquals("17-Nov", profile.birthday)
        assertEquals(
            listOf("Advisor", "EA Leader", "Economics", "Mathematics", "Teacher"),
            profile.positions,
        )
        assertTrue(profile.entity.avatarUrl!!.contains("/files/user_photos/nc00ccc_photo.jpg"))
        assertEquals(3, profile.classes.size)
        val econ = profile.classes.first { it.id == "1EA16CECOX" }
        assertEquals("Economics", econ.name)
        assertEquals("1", econ.year)
        assertEquals("HL/SL", econ.levelLabel)
        assertEquals("A 1.6", econ.room)
        val advisor = profile.classes.first { it.id == "Chris" }
        assertEquals("Advisor group", advisor.name)
        assertEquals("Leif Høegh", advisor.room)
        assertEquals(2, profile.activities.size)
        assertEquals("Campus responsibility Peer tutoring Economics", profile.activities[0].name)
        assertEquals("01-Apr-2026 to 31-Mar-2027", profile.activities[0].dates)
        assertEquals("service", profile.activities[0].category)
    }

    @Test
    fun kitchen_staff_profile_has_role_and_no_classes() {
        val html = javaClass.classLoader!!
            .getResourceAsStream("w4/staff-kitchen.html")!!
            .bufferedReader()
            .readText()
        val profile = W4PeopleParser.parseProfile(html)!!
        assertEquals("nc00ddd", profile.entity.id)
        assertEquals(DirectoryEntityKind.TEACHER, profile.entity.kind)
        assertEquals(listOf("Kitchen"), profile.positions)
        assertEquals("dana.dahl@uwcrcn.no", profile.email)
        assertNull(profile.officeTel)
        assertNull(profile.mobile)
        assertTrue(profile.classes.isEmpty())
        assertTrue(profile.activities.isEmpty())
        assertEquals("Norway", profile.country)
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
        assertTrue(people.single().avatarUrl!!.contains("/files/user_photos/nc25wnas_photo.jpg"))
    }
}
