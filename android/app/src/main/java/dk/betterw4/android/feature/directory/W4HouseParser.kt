package dk.betterw4.android.feature.directory

import dk.betterw4.android.core.w4.W4Hosts
import dk.betterw4.android.core.w4.W4Html
import org.jsoup.Jsoup
import org.jsoup.nodes.Element

/**
 * `people/students/byhouse` and `people/students/byhouse/index&house_id=`.
 *
 * Captured 19 Aug 2026. Each house page is:
 *
 *   * a `ul.menu-list` of house links (`house_id=denmark` …)
 *   * `h3` House leader + `ul.user-list`
 *   * `h3.Room NNN` + `ul.user-list` of students (photo, name, country, year, status)
 *   * optional `h3` Students with no room
 */
object W4HouseParser {

    fun parseIndex(html: String): List<House> {
        val doc = Jsoup.parse(html, W4Hosts.ORIGIN)
        val root = doc.getElementById("content_inner") ?: doc.body() ?: doc
        val byId = linkedMapOf<String, House>()
        for (anchor in root.select("a[href*=house_id]")) {
            val href = anchor.attr("abs:href").ifBlank { anchor.attr("href") }
            val id = houseIdFromHref(href) ?: continue
            val name = anchor.text().trim().ifBlank { displayNameForId(id) }
            byId.putIfAbsent(id, House(id = id, name = name))
        }
        root.select("ul.menu-list li").forEach { item ->
            if (item.selectFirst("a[href*=house_id]") != null) return@forEach
            val current = item.selectFirst("span.current")?.text()?.trim().orEmpty()
            if (current.isBlank()) return@forEach
            val id = slugFromName(current)
            byId.putIfAbsent(id, House(id = id, name = current))
        }
        return byId.values.toList()
    }

    fun parseHouse(html: String, houseId: String? = null): House {
        val doc = Jsoup.parse(html, W4Hosts.ORIGIN)
        val root = doc.getElementById("content_inner") ?: doc.body() ?: doc
        val listed = parseIndex(html)
        val currentName = root.selectFirst("ul.menu-list span.current")?.text()?.trim()
        val id = houseId
            ?: listed.firstOrNull { it.name.equals(currentName, ignoreCase = true) }?.id
            ?: currentName?.let { slugFromName(it) }
            ?: "unknown"
        val name = currentName
            ?.takeIf { it.isNotBlank() }
            ?: listed.firstOrNull { it.id == id }?.name
            ?: displayNameForId(id)

        val leaders = mutableListOf<HouseResident>()
        val rooms = mutableListOf<HouseRoom>()
        val unassigned = mutableListOf<HouseResident>()
        var section: Section = Section.None

        for (child in root.children()) {
            when (child.tagName().lowercase()) {
                "h3" -> {
                    val title = child.text().trim()
                    if (title.isBlank() || isStatusHeading(title)) continue
                    section = classifySection(title)
                }
                "ul" -> {
                    if (!child.classNames().any { it.equals("user-list", ignoreCase = true) }) {
                        continue
                    }
                    val residents = parseResidents(child)
                    when (val current = section) {
                        is Section.Leader -> leaders += residents
                        is Section.Room -> rooms += HouseRoom(
                            id = "${id}-${slugFromName(current.title)}",
                            name = current.title,
                            residents = residents,
                        )
                        is Section.Unassigned -> unassigned += residents
                        Section.None -> if (residents.isNotEmpty()) unassigned += residents
                    }
                }
            }
        }

        return House(
            id = id,
            name = name,
            leaders = leaders,
            rooms = rooms,
            unassigned = unassigned,
            loaded = true,
        )
    }

    fun houseIdFromHref(href: String): String? {
        val decoded = java.net.URLDecoder.decode(href, Charsets.UTF_8)
        return HOUSE_ID.find(decoded)?.groupValues?.get(1)?.lowercase()?.trim()
            ?.takeIf { it.isNotBlank() }
    }

    fun slugFromName(name: String): String {
        val trimmed = name.trim()
        if (trimmed.equals("graduated", ignoreCase = true)) return "grad"
        return trimmed.lowercase()
            .replace(Regex("""[^a-z0-9]+"""), "")
            .ifBlank { "unknown" }
    }

    fun displayNameForId(id: String): String = when (id.lowercase()) {
        "grad" -> "Graduated"
        else -> id.replaceFirstChar { it.titlecase() }
    }

    private fun parseResidents(list: Element): List<HouseResident> {
        val out = linkedMapOf<String, HouseResident>()
        for (item in list.select("> li")) {
            parseResident(item)?.let { out.putIfAbsent(it.id, it) }
        }
        return out.values.toList()
    }

    private fun parseResident(item: Element): HouseResident? {
        val link = item.selectFirst("a[href*=uwc_id]") ?: return null
        val href = link.attr("abs:href").ifBlank { link.attr("href") }
        val id = W4Html.UWC_ID.find(href)?.groupValues?.get(1)?.lowercase() ?: return null
        val kind = if (href.contains("people/staff", ignoreCase = true)) {
            DirectoryEntityKind.TEACHER
        } else {
            DirectoryEntityKind.STUDENT
        }
        val name = item.select("a[href*=uwc_id]")
            .map { it.ownText().ifBlank { it.text() }.trim() }
            .firstOrNull { it.isNotBlank() && !it.equals(id, ignoreCase = true) && !it.startsWith("Photo of") }
            ?: id
        val img = item.selectFirst("img.photo, img")
        val photo = img?.let {
            W4PeopleParser.absPhotoUrl(it.absUrl("src").ifBlank { it.attr("src") }, id)
        }
        val status = item.selectFirst("h3")?.text()?.trim()?.takeIf { it.isNotBlank() }
        val lines = textLines(item)
            .filter { line ->
                !line.equals(name, ignoreCase = true) &&
                    !line.equals(id, ignoreCase = true) &&
                    !line.equals(status, ignoreCase = true)
            }
        val year = lines.firstNotNullOfOrNull { statedYear(it) }
        val country = lines.firstOrNull { statedYear(it) == null }
        val subtitle = listOfNotNull(
            country,
            year?.let { if (it == "1") "1st year" else if (it == "2") "2nd year" else it },
        ).joinToString(" · ").ifBlank { null }
        return HouseResident(
            entity = DirectoryEntity(
                id = id,
                name = name,
                kind = kind,
                subtitle = subtitle,
                avatarUrl = photo,
            ),
            country = country,
            year = year,
            status = status,
        )
    }

    private fun textLines(item: Element): List<String> {
        val clone = item.clone()
        clone.select("a").remove()
        clone.select("h3").remove()
        clone.select("img").remove()
        return clone.html()
            .split(Regex("""<br\s*/?>""", RegexOption.IGNORE_CASE))
            .map { Jsoup.parse(it).text().trim() }
            .filter { it.isNotBlank() }
    }

    private fun statedYear(line: String): String? {
        YEAR_ORDINAL.find(line)?.groupValues?.get(1)?.let { return it }
        YEAR_PREFIX.find(line)?.groupValues?.get(1)?.let { return it }
        return null
    }

    private fun isStatusHeading(title: String): Boolean =
        STATUS_HEADING.containsMatchIn(title)

    private fun classifySection(title: String): Section {
        val lower = title.lowercase()
        return when {
            lower.contains("house leader") || lower.contains("houseparent") -> Section.Leader
            lower.contains("no room") || lower.contains("unassigned") -> Section.Unassigned
            ROOM_TITLE.containsMatchIn(title) -> Section.Room(title)
            else -> Section.Unassigned
        }
    }

    private sealed class Section {
        data object None : Section()
        data object Leader : Section()
        data object Unassigned : Section()
        data class Room(val title: String) : Section()
    }

    private val HOUSE_ID = Regex("""[?&]house_id=([^&#]+)""", RegexOption.IGNORE_CASE)
    private val YEAR_ORDINAL = Regex("""\b([12])\s*(?:st|nd|rd|th)\s*year\b""", RegexOption.IGNORE_CASE)
    private val YEAR_PREFIX = Regex("""\byears?\s*([12])\b""", RegexOption.IGNORE_CASE)
    private val ROOM_TITLE = Regex("""^room\b""", RegexOption.IGNORE_CASE)
    private val STATUS_HEADING = Regex(
        """^(on campus|off campus|on a walk|at raudbua|in flekke|in dale|other)\b""",
        RegexOption.IGNORE_CASE,
    )
}
