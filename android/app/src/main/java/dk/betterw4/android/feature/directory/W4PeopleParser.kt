package dk.betterw4.android.feature.directory

import dk.betterw4.android.core.w4.W4Hosts
import dk.betterw4.android.core.w4.W4Html
import dk.betterw4.android.core.w4.W4Urls
import dk.betterw4.android.feature.classes.ClassLevel
import dk.betterw4.android.feature.classes.W4ClassParser
import dk.betterw4.android.feature.schedule.PersonClass
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
        val root = doc.getElementById("content_inner") ?: doc
        val byId = linkedMapOf<String, DirectoryEntity>()

        fun merge(entity: DirectoryEntity) {
            byId[entity.id] = DirectoryParser.mergeEntity(byId[entity.id], entity)
        }

        for (link in root.select("a[href*=uwc_id]")) {
            parseLink(link)?.let { merge(it) }
        }

        for (row in root.select("table.items tbody tr, table.items tr")) {
            parseTableRow(row)?.let { merge(it) }
        }

        return byId.values.toList()
    }

    fun parseProfile(
        html: String,
        explicitKind: DirectoryEntityKind? = null,
    ): W4PersonProfile? {
        val doc = Jsoup.parse(html, W4Hosts.ORIGIN)
        val root = doc.getElementById("content_inner") ?: doc
        val fields = linkedMapOf<String, String>()

        val view = root.selectFirst("table.detail-view") ?: root
        view.select("tr").forEach { tr ->
            val th = tr.selectFirst("th")?.text()?.trim().orEmpty()
            val td = tr.selectFirst("td")?.text()?.trim().orEmpty()
            if (th.isNotEmpty() && td.isNotEmpty()) {
                fields.putIfAbsent(th.lowercase(), td)
            }
        }
        root.select("dl dt").forEach { dt ->
            val label = dt.text().trim()
            val dd = dt.nextElementSibling()?.takeIf { it.tagName().equals("dd", ignoreCase = true) }
            val value = dd?.text()?.trim().orEmpty()
            if (label.isNotEmpty() && value.isNotEmpty()) {
                fields.putIfAbsent(label.lowercase(), value)
            }
        }

        val uwcId = personId(fields.entry("uwc id", "uwc_id", "id"))
            ?: personId(root.selectFirst("img.user-photo, img.photo")?.attr("alt"))
            ?: personId(root.selectFirst("img.user-photo, img.photo")?.attr("src"))
            ?: return null
        val first = fields.entry("first name", "firstname", "given name")
        val last = fields.entry("last name", "lastname", "family name", "surname")
        val preferred = fields.entry("preferred name", "preferred")
        val fullName = fields.entry("name", "full name")
        val name = listOfNotNull(first, last).joinToString(" ").ifBlank { null }
            ?: fullName
            ?: preferred
        val year = fields.entry("year", "ib year")
        val house = fields.entry("house")
        val country = fields.entry("country", "nationality")
            ?: sidebarCountry(root)
        val pronouns = fields.entry("pronouns")
        val email = fields.entry("email", "e-mail", "e mail")
            ?: "$uwcId@uwcrcn.no"
        val positions = StaffRoles.parse(fields.entry("position", "positions", "role", "roles"))
        val officeTel = fields.entry("office tel", "office telephone", "office phone", "office")
        val mobile = fields.entry("mobile", "mobile phone", "cell", "phone")
        val birthday = fields.entry("birthday", "date of birth", "birth date", "dob")
        val classes = parseTaughtClasses(root)
        val activities = parseStaffActivities(root)
        val photo = profilePhoto(root, uwcId)
        val kind = explicitKind
            ?: profileKind(root, uwcId)
            ?: if (positions.isNotEmpty() || classes.isNotEmpty() || activities.isNotEmpty()) {
                DirectoryEntityKind.TEACHER
            } else {
                DirectoryEntityKind.STUDENT
            }
        val subtitle = if (kind == DirectoryEntityKind.TEACHER) {
            listOfNotNull(
                positions.take(3).joinToString(" · ").ifBlank { null },
                country,
            ).joinToString(" · ").ifBlank { null }
        } else {
            listOfNotNull(year?.let { "Year $it" }, house, country)
                .filter { it.isNotBlank() }
                .joinToString(" · ")
                .ifBlank { null }
        }
        return W4PersonProfile(
            entity = DirectoryEntity(
                id = uwcId,
                name = name?.trim().orEmpty().ifBlank { uwcId },
                kind = kind,
                subtitle = subtitle,
                avatarUrl = photo,
                year = DirectoryYear.parse(year),
            ),
            email = email,
            house = house,
            country = country,
            pronouns = pronouns,
            year = year,
            birthday = birthday,
            officeTel = officeTel,
            mobile = mobile,
            positions = positions,
            classes = classes,
            activities = activities,
        )
    }

    fun guessPhotoUrl(uwcId: String): String =
        "${W4Hosts.ORIGIN}/files/user_photos/${uwcId.lowercase()}_photo.jpg"

    /**
     * List pages print `{id}_thumb.jpg`; the matching full portrait is `{id}_photo.jpg`.
     * A guessed `{id}.jpg` 404s on live W4 and is upgraded too. Already-full URLs stay.
     */
    fun fullSizePhotoUrl(url: String): String {
        val stripped = url.replace(THUMB_IN_NAME, ".")
        return BARE_USER_PHOTO.replace(stripped) { match ->
            "${match.groupValues[1]}${match.groupValues[2].lowercase()}_photo${match.groupValues[3]}"
        }
    }

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
        val li = link.parents().firstOrNull { it.tagName() == "li" }
        val year = DirectoryYear.parse(subtitle) ?: DirectoryYear.parse(li?.text())
        return DirectoryEntity(
            id = id,
            name = name,
            kind = kind,
            subtitle = subtitle,
            avatarUrl = photo,
            year = year,
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
        val year = entity.year ?: DirectoryYear.parse(subtitle) ?: DirectoryYear.parse(extra.joinToString(" "))
        return entity.copy(subtitle = subtitle, avatarUrl = photo, year = year)
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
     * Live portraits live at `/files/user_photos/{id}_photo.jpg`.
     * List pages print `{id}_thumb.jpg`; we upgrade to the matching full file.
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
        return fullSizePhotoUrl(resolved)
    }

    private val THUMB_IN_NAME = Regex("""_thumb\.""", RegexOption.IGNORE_CASE)
    private val BARE_USER_PHOTO = Regex(
        """(/files/user_photos/)([A-Za-z0-9]+)(\.[A-Za-z0-9]+)""",
        RegexOption.IGNORE_CASE,
    )

    private fun Map<String, String>.entry(vararg keys: String): String? {
        for (key in keys) {
            entries.firstOrNull { it.key == key }?.value?.takeIf { it.isNotBlank() }?.let { return it }
            entries.firstOrNull { it.key.contains(key) }?.value?.takeIf { it.isNotBlank() }?.let { return it }
        }
        return null
    }

    private fun parseTaughtClasses(root: Element): List<PersonClass> {
        val heading = root.select("h3").firstOrNull { it.text().contains("class", ignoreCase = true) }
            ?: return emptyList()
        val list = heading.nextElementSiblings().firstOrNull { it.tagName().equals("ul", ignoreCase = true) }
            ?: return emptyList()
        val out = linkedMapOf<String, PersonClass>()
        for (anchor in list.select("a[href*=class_id]")) {
            val href = anchor.attr("abs:href").ifBlank { anchor.attr("href") }
            val id = W4ClassParser.classIdFromHref(href) ?: continue
            val caption = anchor.text().replace('\u00a0', ' ').trim()
            val parsed = W4ClassParser.parseCaption(caption)
            val item = PersonClass(
                id = id,
                name = parsed?.subject ?: caption.substringAfter(": ").ifBlank { caption },
                year = parsed?.year,
                levelLabel = parsed?.level?.badge?.takeIf { it.isNotEmpty() }
                    ?: parsed?.level?.takeIf { it != ClassLevel.UNKNOWN && it != ClassLevel.NONE }
                        ?.name,
                room = parsed?.room,
            )
            out.putIfAbsent(id.lowercase(), item)
        }
        return out.values.toList()
    }

    private fun parseStaffActivities(root: Element): List<StaffActivity> {
        val heading = root.select("h3").firstOrNull { heading ->
            val text = heading.text()
            text.contains("EA activit", ignoreCase = true) ||
                text.contains("extra academic", ignoreCase = true)
        } ?: return emptyList()
        val list = heading.nextElementSiblings().firstOrNull { it.tagName().equals("ul", ignoreCase = true) }
            ?: return emptyList()
        return list.select("li").mapNotNull { li ->
            val parts = li.html()
                .split(Regex("""(?i)<br\s*/?>"""))
                .map { Jsoup.parse(it).text().replace('\u00a0', ' ').trim() }
                .filter { it.isNotEmpty() }
            val name = parts.firstOrNull() ?: return@mapNotNull null
            val rest = parts.drop(1)
            val dates = rest.firstOrNull { it.contains(" to ", ignoreCase = true) }
            val category = rest.firstOrNull { it != dates }
            StaffActivity(name = name, dates = dates, category = category)
        }
    }

    private fun sidebarCountry(root: Element): String? {
        val sidebar = root.selectFirst(".image-sidebar") ?: return null
        return sidebar.select("div").map { it.text().trim() }
            .firstOrNull { it.isNotEmpty() && it.length in 3..40 && !it.contains("flag", ignoreCase = true) }
    }

    private fun profilePhoto(root: Element, uwcId: String): String? {
        val image = root.selectFirst("img.user-photo, img.photo")
            ?: root.select("img[src]").firstOrNull { img ->
                val src = img.attr("src")
                src.contains(uwcId, ignoreCase = true) && !img.hasClass("flag")
            }
        val fromImg = image?.let { absPhotoUrl(it.absUrl("src").ifBlank { it.attr("src") }, uwcId) }
        if (fromImg != null) return fromImg
        val pretty = root.selectFirst("a.pretty[href]")
        return pretty?.let { absPhotoUrl(it.absUrl("href").ifBlank { it.attr("href") }, uwcId) }
    }

    private fun profileKind(root: Element, uwcId: String): DirectoryEntityKind? {
        for (anchor in root.select("a[href*=uwc_id]")) {
            val href = anchor.attr("abs:href").ifBlank { anchor.attr("href") }
            val id = personId(href) ?: continue
            if (!id.equals(uwcId, ignoreCase = true)) continue
            if (href.contains("people/staff", ignoreCase = true)) return DirectoryEntityKind.TEACHER
            if (href.contains("people/students/student", ignoreCase = true)) return DirectoryEntityKind.STUDENT
        }
        return null
    }

    /**
     * Accepts `nc26jban` and the other two-letter staff prefixes W4 actually
     * uses (`ac91aosl`, `ad98jkra`, `wk11lbon`).
     */
    private fun personId(raw: String?): String? {
        val value = raw?.trim().orEmpty()
        if (value.isEmpty()) return null
        PERSON_ID.find(value)?.groupValues?.get(1)?.lowercase()?.let { return it }
        return W4Html.UWC_ID.find(value)?.groupValues?.get(1)?.lowercase()
    }

    private val PERSON_ID = Regex("""\b([A-Za-z]{2}\d{2}[A-Za-z]+)\b""")
}

data class W4PersonProfile(
    val entity: DirectoryEntity,
    val email: String? = null,
    val house: String? = null,
    val country: String? = null,
    val pronouns: String? = null,
    val year: String? = null,
    val birthday: String? = null,
    val officeTel: String? = null,
    val mobile: String? = null,
    val positions: List<String> = emptyList(),
    val classes: List<PersonClass> = emptyList(),
    val activities: List<StaffActivity> = emptyList(),
)
