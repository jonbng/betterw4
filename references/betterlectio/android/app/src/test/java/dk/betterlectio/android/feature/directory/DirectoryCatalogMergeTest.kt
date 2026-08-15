package dk.betterlectio.android.feature.directory

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DirectoryCatalogMergeTest {

    @Test
    fun parseMembers_extracts_students_with_parent_subtitle() {
        val html = """
            <html><body>
            <table id="s_m_Content_Content_laerereleverpanel_alm_gv">
              <tr><td data-lectiocontextcard="S10">Anna Andersen</td></tr>
              <tr><td data-lectiocontextcard="S11">Bo Berg</td></tr>
            </table>
            </body></html>
        """.trimIndent()
        val parent = DirectoryEntity("HE1", "3x Ma", DirectoryEntityKind.HOLD)
        val members = DirectoryParser.parseMembers(html, parent)
        assertEquals(2, members.size)
        assertEquals("S10", members[0].id)
        assertEquals("Anna Andersen", members[0].name)
        assertEquals(DirectoryEntityKind.STUDENT, members[0].kind)
        assertEquals("3x Ma", members[0].subtitle)
    }

    @Test
    fun parseMembers_withpics_uses_fornavn_efternavn_not_id_column() {
        val html = """
            <html><body>
            <table id="s_m_Content_Content_laerereleverpanel_alm_gv">
              <tr>
                <th>Foto</th><th>Type</th><th>ID</th><th>Fornavn</th><th>Efternavn</th>
              </tr>
              <tr>
                <td data-lectiocontextcard="T99">
                  <img src="/lectio/94/GetImage.aspx?pictureid=111"/>
                </td>
                <td>Lærer</td>
                <td><span class="noWrap">JK</span></td>
                <td><a href="#">Jens</a></td>
                <td><span class="noWrap">Jensen</span></td>
              </tr>
              <tr>
                <td data-lectiocontextcard="S10">
                  <img src="/lectio/94/GetImage.aspx?pictureid=74096247556"/>
                </td>
                <td>Elev</td>
                <td><span class="noWrap">2x 02</span></td>
                <td><a href="#">Anna</a></td>
                <td><span class="noWrap">Andersen</span></td>
              </tr>
              <tr>
                <td data-lectiocontextcard="S11">
                  <img src="/lectio/94/GetImage.aspx?pictureid=2"/>
                </td>
                <td>Elev</td>
                <td><span class="noWrap">2x 03</span></td>
                <td><a href="#">Bo</a></td>
                <td><span class="noWrap">Berg</span></td>
              </tr>
            </table>
            </body></html>
        """.trimIndent()
        val parent = DirectoryEntity("HE1", "2x Ma", DirectoryEntityKind.HOLD)
        val members = DirectoryParser.parseMembers(html, parent, gymId = 94)
        assertEquals(3, members.size)
        assertEquals("Jens Jensen", members[0].name)
        assertEquals(DirectoryEntityKind.TEACHER, members[0].kind)
        assertEquals("Anna Andersen", members[1].name)
        assertEquals("2x", members[1].subtitle)
        assertEquals("Bo Berg", members[2].name)
        assertFalse(members.any { it.name == "2x 02" || it.name == "JK" || it.name == "2x 03" })
        assertEquals(
            "https://www.lectio.dk/lectio/94/GetImage.aspx?pictureid=74096247556&fullsize=1",
            members[1].avatarUrl,
        )
    }

    @Test
    fun parseMembers_extracts_pictureid_thumbnails() {
        val html = """
            <html><body>
            <table id="s_m_Content_Content_laerereleverpanel_alm_gv">
              <tr>
                <td><img src="/lectio/94/GetImage.aspx?pictureid=74096247556"/></td>
                <td data-lectiocontextcard="S10">Anna Andersen</td>
              </tr>
              <tr>
                <td data-lectiocontextcard="S11">Bo Berg</td>
              </tr>
            </table>
            </body></html>
        """.trimIndent()
        val parent = DirectoryEntity("HE1", "3x Ma", DirectoryEntityKind.HOLD)
        val members = DirectoryParser.parseMembers(html, parent, gymId = 94)
        assertEquals(2, members.size)
        assertEquals(
            "https://www.lectio.dk/lectio/94/GetImage.aspx?pictureid=74096247556&fullsize=1",
            members[0].avatarUrl,
        )
        assertNull(members[1].avatarUrl)
    }

    @Test
    fun mergeCatalog_preserves_avatar_when_incoming_lacks_one() {
        val existing = listOf(
            DirectoryEntity(
                "S1",
                "Old Name",
                DirectoryEntityKind.STUDENT,
                "2x",
                avatarUrl = "https://www.lectio.dk/lectio/94/GetImage.aspx?pictureid=1&fullsize=1",
            ),
        )
        val incoming = listOf(
            DirectoryEntity("S1", "New Name", DirectoryEntityKind.STUDENT, "3x"),
        )
        val merged = DirectoryParser.mergeCatalog(existing, incoming)
        val s1 = merged.first { it.id == "S1" }
        assertEquals("New Name", s1.name)
        assertEquals(
            "https://www.lectio.dk/lectio/94/GetImage.aspx?pictureid=1&fullsize=1",
            s1.avatarUrl,
        )
    }

    @Test
    fun mergeEntity_does_not_overwrite_real_name_with_class_code() {
        val existing = DirectoryEntity("S10", "Anna Andersen", DirectoryEntityKind.STUDENT, "2x")
        val polluted = DirectoryEntity("S10", "2x 02", DirectoryEntityKind.STUDENT, "Hold")
        val merged = DirectoryParser.mergeEntity(existing, polluted)
        assertEquals("Anna Andersen", merged.name)
    }

    @Test
    fun looksLikeIdColumnLabel_detects_seat_and_initials() {
        assertTrue(DirectoryParser.looksLikeIdColumnLabel("2x 02"))
        assertTrue(DirectoryParser.looksLikeIdColumnLabel("JK"))
        assertFalse(DirectoryParser.looksLikeIdColumnLabel("Anna Andersen"))
        assertFalse(DirectoryParser.looksLikeIdColumnLabel("Jens Jensen"))
    }

    @Test
    fun parseMembers_ignores_nav_chrome_links() {
        val html = """
            <html><body>
            <a href="#">hjælp</a>
            <a href="#">import_contactsBøger</a>
            <a href="#">starKarakterer</a>
            <a data-lectiocontextcard="S99">Real Student</a>
            <table>
              <tr><td><a href="/FindSkema.aspx">Find skema</a></td></tr>
              <tr><td data-lectiocontextcard="S100">Valid Elev</td></tr>
            </table>
            </body></html>
        """.trimIndent()
        val parent = DirectoryEntity("HE1", "Hold", DirectoryEntityKind.HOLD)
        val members = DirectoryParser.parseMembers(html, parent)
        assertEquals(2, members.size)
        assertTrue(members.all { it.id.startsWith("S") })
        assertFalse(members.any { it.name.contains("hjælp", ignoreCase = true) })
        assertFalse(members.any { it.name.contains("import", ignoreCase = true) })
        assertFalse(members.any { it.name.contains("star", ignoreCase = true) })
    }

    @Test
    fun mergeCatalog_later_wins_on_id_collision() {
        val existing = listOf(
            DirectoryEntity("S1", "Old Name", DirectoryEntityKind.STUDENT, "2x"),
            DirectoryEntity("T1", "Teacher", DirectoryEntityKind.TEACHER),
        )
        val incoming = listOf(
            DirectoryEntity("S1", "New Name", DirectoryEntityKind.STUDENT, "3x"),
            DirectoryEntity("C1", "3x", DirectoryEntityKind.CLASS),
        )
        val merged = DirectoryParser.mergeCatalog(existing, incoming)
        assertEquals(3, merged.size)
        val s1 = merged.first { it.id == "S1" }
        assertEquals("New Name", s1.name)
        assertEquals("3x", s1.subtitle)
        assertTrue(merged.any { it.id == "T1" })
        assertTrue(merged.any { it.id == "C1" })
    }

    @Test
    fun parseFindList_only_accepts_context_cards_for_kind() {
        val html = """
            <html><body>
            <a href="#">hjælp</a>
            <a href="FindSkema.aspx?type=lokale">Lokaler</a>
            <a data-lectiocontextcard="RO1" href="FindSkema.aspx?type=lokale&id=1">201</a>
            <a data-lectiocontextcard="RO2" href="FindSkema.aspx?type=lokale&id=2">105</a>
            <a data-lectiocontextcard="S1">Wrong kind student</a>
            </body></html>
        """.trimIndent()
        val rooms = DirectoryParser.parseFindList(html, DirectoryEntityKind.ROOM)
        assertEquals(2, rooms.size)
        assertEquals(DirectoryEntityKind.ROOM, rooms[0].kind)
        assertEquals("RO1", rooms[0].id)
        assertFalse(rooms.any { it.name == "hjælp" || it.name == "Lokaler" })
    }

    @Test
    fun parseDropdownUrl_extracts_relative_path() {
        val html = """
            <script>
            Autocomplete.registerDataSetUrl('AvanceretSkema_94_2025',
              '/lectio/94/cache/DropDown.aspx?type=AvanceretSkema&afdeling=1&subcache=2025');
            </script>
        """.trimIndent()
        val url = DirectoryParser.parseDropdownUrl(html)
        assertEquals(
            "/lectio/94/cache/DropDown.aspx?type=AvanceretSkema&afdeling=1&subcache=2025",
            url,
        )
    }

    @Test
    fun parseDropdownJson_parses_all_kinds_and_skips_inactive() {
        val json = """
            {
              "key": "AvanceretSkema_94_2025",
              "items": [
                ["Anna Andersen (3x 12)", "S100", "", "11", " fs", null, true],
                ["Bo Berg (2y 5)", "S101", "i", "11", " fs", null, true],
                ["Jens Jensen (JJ)", "T200", "", "11", " ft", null, true],
                ["3x Ma A", "HE300", "", "11", " fh", null, true],
                ["201 - Bygning A", "RO400", "", "11", " fr", null, true],
                ["3x", "SC500", "", "11", " fk", null, true],
                ["Alle 3. G. elever", "GE600", "", "11", "groupuser", null, true],
                ["Projector", "RE700", "", "11", " fre", null, true],
                ["Broken", "NOTANID", "", "11", "", null, true],
                ["hjælp", "S", "", "11", "", null, true]
              ]
            }
        """.trimIndent()
        val entities = DirectoryParser.parseDropdownJson(json)
        // S100, T200, HE300, RO400, SC500, GE600, RE700 (inactive S101 + invalid ids skipped)
        assertEquals(7, entities.size)

        val student = entities.first { it.id == "S100" }
        assertEquals("Anna Andersen", student.name)
        assertEquals("3x", student.subtitle)
        assertEquals(DirectoryEntityKind.STUDENT, student.kind)

        // Inactive student skipped
        assertFalse(entities.any { it.id == "S101" })

        val teacher = entities.first { it.id == "T200" }
        assertEquals("Jens Jensen", teacher.name)
        assertEquals("JJ", teacher.subtitle)

        assertEquals(DirectoryEntityKind.HOLD, entities.first { it.id == "HE300" }.kind)
        assertEquals(DirectoryEntityKind.ROOM, entities.first { it.id == "RO400" }.kind)
        assertEquals(DirectoryEntityKind.CLASS, entities.first { it.id == "SC500" }.kind)
        assertEquals(DirectoryEntityKind.GROUP, entities.first { it.id == "GE600" }.kind)
        assertEquals(DirectoryEntityKind.RESOURCE, entities.first { it.id == "RE700" }.kind)
    }

    @Test
    fun parseDropdownJson_cleans_kostelev_suffix() {
        val json = """
            {"items":[["Iris Schibsbye Møller(k) (3a 10)", "S42", "", "11", " fs", null, true]]}
        """.trimIndent()
        val entities = DirectoryParser.parseDropdownJson(json)
        assertEquals(1, entities.size)
        assertEquals("Iris Schibsbye Møller", entities[0].name)
        assertEquals("3a", entities[0].subtitle)
    }

    @Test
    fun looksLikeNavChrome_flags_material_icon_mashups() {
        assertTrue(DirectoryParser.looksLikeNavChrome("hjælp"))
        assertTrue(DirectoryParser.looksLikeNavChrome("import_contactsBøger"))
        assertTrue(DirectoryParser.looksLikeNavChrome("starKarakterer"))
        assertFalse(DirectoryParser.looksLikeNavChrome("Anna Andersen"))
        assertFalse(DirectoryParser.looksLikeNavChrome("3x Ma"))
    }

    @Test
    fun numericId_strips_letter_prefix() {
        assertEquals("123", DirectoryParser.numericId("HE123"))
        assertEquals("456", DirectoryParser.numericId("S456"))
        assertEquals("99", DirectoryParser.numericId("RO99"))
        assertEquals("", DirectoryParser.numericId("HE"))
    }

    @Test
    fun normalizeLectioPath_avoids_double_gym_prefix() {
        assertEquals(
            "https://www.lectio.dk/lectio/94/cache/DropDown.aspx?type=AvanceretSkema",
            DirectorySyncService.normalizeLectioPath(
                "/lectio/94/cache/DropDown.aspx?type=AvanceretSkema",
            ),
        )
        assertEquals(
            "cache/DropDown.aspx?x=1",
            DirectorySyncService.normalizeLectioPath("cache/DropDown.aspx?x=1"),
        )
        assertNull(DirectoryParser.parseDropdownUrl("no dropdown here"))
    }
}
