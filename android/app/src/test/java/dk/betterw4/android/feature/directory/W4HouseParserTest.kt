package dk.betterw4.android.feature.directory

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class W4HouseParserTest {
    private val indexHtml = javaClass.classLoader!!
        .getResourceAsStream("w4/houses-index.html")!!
        .bufferedReader()
        .readText()

    private val denmarkHtml = javaClass.classLoader!!
        .getResourceAsStream("w4/houses-denmark.html")!!
        .bufferedReader()
        .readText()

    @Test
    fun index_lists_houses_in_document_order() {
        val houses = W4HouseParser.parseIndex(indexHtml)
        assertEquals(
            listOf("denmark", "finland", "grad", "iceland", "norway", "sweden"),
            houses.map { it.id },
        )
        assertEquals("Denmark", houses.first().name)
        assertEquals("Graduated", houses.first { it.id == "grad" }.name)
        assertTrue(houses.none { it.loaded })
    }

    @Test
    fun house_page_groups_leader_rooms_and_unassigned() {
        val house = W4HouseParser.parseHouse(denmarkHtml)
        assertEquals("denmark", house.id)
        assertEquals("Denmark", house.name)
        assertTrue(house.loaded)
        assertEquals(1, house.leaders.size)
        assertEquals("nc00lead", house.leaders.single().id)
        assertEquals("Chris Chen", house.leaders.single().entity.name)
        assertEquals(DirectoryEntityKind.TEACHER, house.leaders.single().entity.kind)
        assertEquals(listOf("Room 101", "Room 102"), house.rooms.map { it.name })
        assertEquals(listOf("nc00aaa", "nc00bbb"), house.rooms[0].residents.map { it.id })
        assertEquals(listOf("nc00ddd"), house.rooms[1].residents.map { it.id })
        assertEquals(listOf("nc00eee"), house.unassigned.map { it.id })
        assertEquals(4, house.studentCount)
    }

    @Test
    fun resident_fields_come_from_the_list_item() {
        val house = W4HouseParser.parseHouse(denmarkHtml)
        val alex = house.rooms[0].residents.first { it.id == "nc00aaa" }
        assertEquals("Alex Andersen", alex.entity.name)
        assertEquals("Denmark", alex.country)
        assertEquals("1", alex.year)
        assertEquals("On campus", alex.status)
        assertNull(alex.entity.avatarUrl)
        assertTrue(alex.detailLine!!.contains("1st year"))

        val bea = house.rooms[0].residents.first { it.id == "nc00bbb" }
        assertEquals("Italy", bea.country)
        assertEquals("2", bea.year)
        assertTrue(bea.entity.avatarUrl!!.contains("/files/user_photos/nc00bbb_photo.jpg"))

        val dana = house.rooms[1].residents.single()
        assertTrue(dana.status!!.startsWith("Off campus"))
        assertTrue(dana.status!!.contains("01-May-2026"))
    }

    @Test
    fun placement_finds_room_and_unassigned_students() {
        val house = W4HouseParser.parseHouse(denmarkHtml)
        val alex = house.placementOf("nc00aaa")
        assertEquals("denmark", alex!!.house.id)
        assertEquals("Room 101", alex.room!!.name)
        assertEquals("Alex Andersen", alex.resident.entity.name)

        val eli = house.placementOf("NC00EEE")
        assertEquals("denmark", eli!!.house.id)
        assertEquals(null, eli.room)
        assertEquals("nc00eee", eli.resident.id)

        assertEquals(null, house.placementOf("nc00lead"))
        assertEquals(null, house.placementOf(""))
    }

    @Test
    fun house_id_is_read_from_the_sibling_query() {
        assertEquals(
            "denmark",
            W4HouseParser.houseIdFromHref(
                "/index.php?r=people/students/byhouse/index&house_id=denmark",
            ),
        )
        assertEquals("grad", W4HouseParser.slugFromName("Graduated"))
    }
}
