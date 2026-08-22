package dk.betterw4.android.feature.teachers

import dk.betterw4.android.core.w4.W4Hosts
import dk.betterw4.android.feature.classes.ClassLevel
import dk.betterw4.android.feature.directory.W4PeopleParser
import org.jsoup.Jsoup
import org.jsoup.nodes.Element
import java.net.URLDecoder
import java.nio.charset.StandardCharsets

/**
 * `people/students/staff` — My teachers and group leaders.
 *
 * Live capture 21 Aug 2026. `#content_inner` holds a type filter and a
 * `ul.user-list` of photo + name anchors plus a role caption. Staff ids come
 * from `uwc_id=` and are not always `nc…`.
 */
object W4TeacherParser {

    private val UWC_ID_QUERY = Regex("""(?:^|[?&])uwc_id=([^&#]+)""", RegexOption.IGNORE_CASE)

    fun parse(html: String): List<MyTeacher> {
        val doc = Jsoup.parse(html, W4Hosts.ORIGIN)
        val root = doc.getElementById("content_inner") ?: doc.body() ?: return emptyList()
        val list = root.selectFirst("ul.user-list") ?: root
        val out = linkedMapOf<String, MyTeacher>()
        val rows = list.select("> li").ifEmpty { root.select("ul.user-list > li") }
        for (item in rows) {
            parseRow(item)?.let { out.putIfAbsent(it.id, it) }
        }
        if (out.isEmpty()) {
            for (anchor in root.select("a[href*=uwc_id]")) {
                val owner = anchor.parents().firstOrNull { it.tagName() == "li" } ?: continue
                parseRow(owner)?.let { out.putIfAbsent(it.id, it) }
            }
        }
        return out.values.toList()
    }

    /** `uwc_id=` value, lowercased. Does not require the student-shaped `nc` regex. */
    fun staffId(fromHref: String): String? {
        if (fromHref.isBlank()) return null
        val decoded = runCatching {
            URLDecoder.decode(fromHref, StandardCharsets.UTF_8.name())
        }.getOrDefault(fromHref)
        val raw = UWC_ID_QUERY.find(decoded)?.groupValues?.get(1) ?: return null
        val id = runCatching {
            URLDecoder.decode(raw, StandardCharsets.UTF_8.name())
        }.getOrDefault(raw).trim().lowercase()
        return id.takeIf { it.isNotEmpty() }
    }

    fun parseRole(raw: String?): Pair<String?, ClassLevel> {
        val text = raw?.replace('\u00a0', ' ')?.replace(Regex("""\s+"""), " ")?.trim().orEmpty()
        if (text.isEmpty()) return null to ClassLevel.UNKNOWN
        val parts = text.split(Regex("""\s+""")).filter { it.isNotBlank() }
        val last = parts.lastOrNull() ?: return text to ClassLevel.UNKNOWN
        val level = levelFromToken(last)
        if (level == ClassLevel.UNKNOWN) return text to ClassLevel.UNKNOWN
        val role = parts.dropLast(1).joinToString(" ").ifBlank { null }
        return role to level
    }

    private fun parseRow(item: Element): MyTeacher? {
        val links = item.select("a[href*=uwc_id]")
        if (links.isEmpty()) return null
        val named = links.firstOrNull { it.selectFirst("img") == null }
            ?: links.firstOrNull()
            ?: return null
        val href = named.attr("abs:href").ifBlank { named.attr("href") }
        val id = staffId(href) ?: return null
        val name = named.ownText().ifBlank { named.text() }.trim()
            .replace(Regex("""Photo of\s+""", RegexOption.IGNORE_CASE), "")
            .ifBlank { id }
            .takeIf { !it.equals(id, ignoreCase = true) }
            ?: id
        val img = item.selectFirst("img.photo, img")
        val photo = img?.let {
            W4PeopleParser.absPhotoUrl(it.absUrl("src").ifBlank { it.attr("src") }, id)
        }
        val (role, level) = parseRole(roleCaption(item, name, id))
        return MyTeacher(
            id = id,
            name = name,
            role = role,
            level = level,
            photoUrl = photo,
        )
    }

    private fun roleCaption(item: Element, name: String, id: String): String? {
        var rest = item.text()
        for (needle in listOf(name, "Photo of $id", "Photo of ${id.uppercase()}", id)) {
            rest = rest.replace(needle, "", ignoreCase = true)
        }
        return rest.replace(Regex("""\s+"""), " ").trim().ifBlank { null }
    }

    private fun levelFromToken(raw: String): ClassLevel {
        val compact = raw.lowercase().filter { it.isLetter() || it == '/' }
        return when {
            compact == "hl/sl" || compact == "hlsl" -> ClassLevel.COMBINED
            compact == "hl" || compact.startsWith("higher") -> ClassLevel.HIGHER
            compact == "sl" || compact.startsWith("standard") -> ClassLevel.STANDARD
            compact.startsWith("combined") -> ClassLevel.COMBINED
            else -> ClassLevel.UNKNOWN
        }
    }
}
