package dk.betterlectio.android.feature.directory

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RoomParserTest {

    @Test
    fun parseAvailabilities_marks_in_use_when_booking_table_has_data() {
        val html = """
            <html><body>
            <div id="m_Content_LectioDetailIsland1_pa">
              <div id="printSingleControl1">
                <h2>201 - Bygning A</h2>
                <table><tr><td>Ma 08:15 Matematik</td></tr></table>
              </div>
              <div id="printSingleControl2">
                <h2>105 - Bygning B</h2>
                <table><tr><td>Der er ingen data</td></tr></table>
              </div>
            </div>
            </body></html>
        """.trimIndent()
        val avail = RoomParser.parseAvailabilities(html)
        assertEquals(2, avail.size)
        val r201 = avail.first { it.shortName == "201" }
        val r105 = avail.first { it.shortName == "105" }
        assertTrue(r201.inUse)
        assertEquals("Bygning A", r201.name)
        assertFalse(r105.inUse)
        assertEquals("Bygning B", r105.name)
    }

    @Test
    fun parseRooms_extracts_id_short_and_name() {
        val html = """
            <html><body>
            <div id="m_Content_listecontainer">
              <table>
                <tr><td><a href="SkemaNy.aspx?type=lokale&id=42">201 Bygning A</a></td></tr>
                <tr><td><a href="SkemaNy.aspx?type=lokale&id=99">Lab1 Naturfag</a></td></tr>
              </table>
            </div>
            </body></html>
        """.trimIndent()
        val rooms = RoomParser.parseRooms(html)
        assertEquals(2, rooms.size)
        assertEquals("42", rooms[0].id)
        assertEquals("201", rooms[0].shortName)
        assertEquals("Bygning A", rooms[0].name)
        assertEquals("99", rooms[1].id)
    }

    @Test
    fun mergeOccupancy_matches_by_name_or_short() {
        val rooms = listOf(
            RoomParser.RoomListItem("1", "201", "Bygning A"),
            RoomParser.RoomListItem("2", "105", "Bygning B"),
            RoomParser.RoomListItem("3", "X", "Ukendt"),
        )
        val avail = listOf(
            RoomParser.RoomAvailability("201", "Bygning A", inUse = true),
            RoomParser.RoomAvailability("105", "Bygning B", inUse = false),
        )
        val merged = RoomParser.mergeOccupancy(rooms, avail)
        assertEquals(3, merged.size)
        assertTrue(merged.first { it.id == "1" }.inUse)
        assertFalse(merged.first { it.id == "2" }.inUse)
        assertFalse(merged.first { it.id == "3" }.inUse)
    }
}
