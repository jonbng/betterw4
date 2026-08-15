package dk.betterw4.android.feature.directory

import dk.betterw4.android.core.w4.W4Hosts
import dk.betterw4.android.core.w4.W4Html
import dk.betterw4.android.core.w4.W4Urls
import org.jsoup.Jsoup
import org.jsoup.nodes.Element

/**
 * People lists + birthdays + public profile links (`uwc_id`).
 *
 * Defensive: captured student-list HTML is sparse, so any `a[href*=uwc_id]` counts.
 */
object W4PeopleParser {

    fun parse(html: String): List<DirectoryEntity> {
        val doc = Jsoup.parse(html, W4Hosts.ORIGIN)
        val byId = linkedMapOf<String, DirectoryEntity>()

        fun merge(entity: DirectoryEntity) {
            byId[entity.id] = DirectoryParser.mergeEntity(byId[entity.id], entity)
        }

        for (link in doc.select("a[href*=uwc_id]")) {
            parseLink(link)?.let { merge(it) }
        }

        for (row in doc.select("table.items tbody tr, table.items tr")) {
            parseTableRow(row)?.let { merge(it) }
        }

        return byId.values.toList()
    }

    fun parseProfile(html: String): W4PersonProfile? {
        val doc = Jsoup.parse(html, W4Hosts.ORIGIN)
        val fields = linkedMapOf<String, String>()
        val view = doc.selectFirst("table.detail-view") ?: doc.getElementById("content_inner")
        view?.select("tr")?.forEach { tr ->
            val th = tr.selectFirst("th")?.text()?.trim().orEmpty()
            val td = tr.selectFirst("td")?.text()?.trim().orEmpty()
            if (th.isNotEmpty() && td.isNotEmpty()) {
                fields[th.lowercase()] = td
            }
        }
        val uwcId = fields.entry("uwc id", "uwc_id", "id")?.lowercase()
            ?: W4Html.uwcId(html)
            ?: return null
        val first = fields.entry("first name", "firstname", "given name")
        val last = fields.entry("last name", "lastname", "family name", "surname")
        val preferred = fields.entry("preferred name", "preferred")
        val name = listOfNotNull(first, last).joinToString(" ").ifBlank { null }
            ?: preferred
            ?: W4Html.displayName(html)
        val year = fields.entry("year", "ib year")
        val house = fields.entry("house")
        val country = fields.entry("country", "nationality")
        val pronouns = fields.entry("pronouns")
        val email = fields.entry("email", "e-mail")
            ?: "$uwcId@uwcrcn.no"
        val photo = doc.selectFirst("#content_inner img.photo, img.photo, #content_inner img[src]")
            ?.let { absPhotoUrl(it.absUrl("src").ifBlank { it.attr("src") }, uwcId) }
        val subtitle = listOfNotNull(year?.let { "Year $it" }, house, country)
            .filter { it.isNotBlank() }
            .joinToString(" · ")
            .ifBlank { null }
        val kind = if (html.contains("people/staff", ignoreCase = true) &&
            !html.contains("people/students/student", ignoreCase = true)
        ) {
            DirectoryEntityKind.TEACHER
        } else {
            DirectoryEntityKind.STUDENT
        }
        return W4PersonProfile(
            entity = DirectoryEntity(
                id = uwcId,
                name = name?.trim().orEmpty().ifBlank { uwcId },
                kind = kind,
                subtitle = subtitle,
                avatarUrl = photo,
            ),
            email = email,
            house = house,
            country = country,
            pronouns = pronouns,
            year = year,
            birthday = fields.entry("birthday", "date of birth", "birth date", "dob"),
        )
    }

    fun guessPhotoUrl(uwcId: String): String =
        "${W4Hosts.ORIGIN}/files/user_photos/${uwcId.lowercase()}_thumb.jpg"

    private fun parseLink(link: Element): DirectoryEntity? {
        val href = link.attr("abs:href").ifBlank { link.attr("href") }
        val id = W4Html.UWC_ID.find(href)?.groupValues?.get(1)?.lowercase() ?: return null
        val img = link.selectFirst("img.photo, img")
        val photo = img?.let { absPhotoUrl(it.absUrl("src").ifBlank { it.attr("src") }, id) }
        val textName = link.ownText().ifBlank { link.text() }
            .replace(Regex("""Photo of\s+""", RegexOption.IGNORE_CASE), "")
            .trim()
        val name = textName.takeIf { it.isNotBlank() && !it.equals(id, ignoreCase = true) }
            ?: nearbyName(link)
            ?: id
        val kind = if (href.contains("people/staff", ignoreCase = true)) {
            DirectoryEntityKind.TEACHER
        } else {
            DirectoryEntityKind.STUDENT
        }
        val subtitle = nearbySubtitle(link, name)
        return DirectoryEntity(
            id = id,
            name = name,
            kind = kind,
            subtitle = subtitle,
            avatarUrl = photo,
        )
    }

    private fun parseTableRow(row: Element): DirectoryEntity? {
        val link = row.selectFirst("a[href*=uwc_id]") ?: return null
        val entity = parseLink(link) ?: return null
        val cells = row.select("td").map { it.text().trim() }.filter { it.isNotBlank() }
        val extra = cells.filter { cell ->
            !cell.equals(entity.name, ignoreCase = true) &&
                !cell.equals(entity.id, ignoreCase = true) &&
                W4Html.UWC_ID.find(cell) == null
        }
        val subtitle = extra.take(3).joinToString(" · ").ifBlank { entity.subtitle }
        val img = row.selectFirst("img.photo, img")
        val photo = img?.let { absPhotoUrl(it.absUrl("src").ifBlank { it.attr("src") }, entity.id) }
            ?: entity.avatarUrl
        return entity.copy(subtitle = subtitle, avatarUrl = photo)
    }

    private fun nearbyName(link: Element): String? {
        val row = link.parents().firstOrNull { it.tagName() == "tr" }
        row?.select("td")?.forEach { td ->
            val text = td.text().trim()
            if (text.isNotBlank() && W4Html.UWC_ID.find(text) == null && text.length > 2) {
                return text
            }
        }
        val li = link.parents().firstOrNull { it.tagName() == "li" }
        li?.select("a[href*=uwc_id]")?.forEach { a ->
            val text = a.ownText().ifBlank { a.text() }.trim()
            if (text.isNotBlank() && W4Html.UWC_ID.find(text) == null && !text.startsWith("Photo of")) {
                return text
            }
        }
        return link.attr("title").trim().takeIf { it.isNotBlank() }
    }

    private fun nearbySubtitle(link: Element, name: String): String? {
        val row = link.parents().firstOrNull { it.tagName() == "tr" }
        if (row != null) {
            val extras = row.select("td").map { it.text().trim() }.filter { cell ->
                cell.isNotBlank() &&
                    !cell.equals(name, ignoreCase = true) &&
                    W4Html.UWC_ID.find(cell) == null
            }
            return extras.drop(1).take(2).joinToString(" · ").ifBlank { null }
        }
        val li = link.parents().firstOrNull { it.tagName() == "li" } ?: return null
        val rest = li.text().replace(name, "", ignoreCase = true).trim()
        return rest.replace(Regex("""\s+"""), " ").takeIf { it.isNotBlank() }
    }

    /**
     * Live thumbs live at `/files/user_photos/{id}_thumb.jpg`.
     * `/images/user.png` is W4's missing-photo placeholder — not a real avatar.
     */
    internal fun absPhotoUrl(raw: String?, uwcId: String): String? {
        val src = raw?.trim().orEmpty()
        if (src.isBlank() || src.startsWith("data:")) return null
        // Browser "Save Page As" local folder, e.g. ./UWCRCN W4_files/nc16jmac_thumb.jpg
        if (src.contains("_files/") && !src.contains("/files/user_photos/")) {
            return guessPhotoUrl(uwcId)
        }
        val resolved = W4Urls.resolve(src).toString()
        if (resolved.contains("/images/user.png")) return null
        return resolved
    }

    private fun Map<String, String>.entry(vararg keys: String): String? {
        for (key in keys) {
            entries.firstOrNull { it.key == key }?.value?.takeIf { it.isNotBlank() }?.let { return it }
            entries.firstOrNull { it.key.contains(key) }?.value?.takeIf { it.isNotBlank() }?.let { return it }
        }
        return null
    }
}

data class W4PersonProfile(
    val entity: DirectoryEntity,
    val email: String? = null,
    val house: String? = null,
    val country: String? = null,
    val pronouns: String? = null,
    val year: String? = null,
    val birthday: String? = null,
)
