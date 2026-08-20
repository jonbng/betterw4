package dk.betterw4.android.feature.onduty

import dk.betterw4.android.core.w4.W4Dates
import dk.betterw4.android.core.w4.W4Hosts
import dk.betterw4.android.core.w4.W4Html
import dk.betterw4.android.feature.directory.W4PeopleParser
import org.jsoup.Jsoup
import org.jsoup.nodes.Element
import org.jsoup.nodes.TextNode
import java.time.LocalDate
import java.time.Month
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.util.Locale

/**
 * `people/onduty` (today's cards) and `people/onduty/schedule` (month calendar).
 *
 * Live capture 19 Aug 2026: each role is an `<h3>`, each person is a nested
 * table with a `{uwc_id}_thumb.jpg` photo, a bold name, and labelled Phone /
 * E-mail / Location rows. The calendar uses `.onduty-group-name` +
 * `.onduty-group` inside `td.day`.
 */
object W4OnDutyParser {

    private val DATE_IN_TEXT = Regex("""\d{1,2}-[A-Za-z]{3,9}-\d{2,4}""")
    private val MONTH_YEAR = Regex("""([A-Za-z]+)\s+(\d{4})""")
    private val FIELD_LABELS = setOf("phone", "e-mail", "email", "location")
    private val DISPLAY_DAY = DateTimeFormatter.ofPattern("EEE d MMM", Locale.UK)

    fun parseToday(html: String): OnDutyPage {
        val doc = Jsoup.parse(html, W4Hosts.ORIGIN)
        val root = doc.getElementById("content_inner") ?: doc.body() ?: return OnDutyPage()
        val heading = root.selectFirst("h2")?.text()?.trim()?.ifBlank { null }
        val date = dateFromHeading(heading)
        val groups = parseRoleGroups(root)
        return OnDutyPage(
            title = heading,
            date = date,
            dateLabel = heading?.removePrefix("People on duty")?.trim()?.ifBlank { null }
                ?: date?.let { W4Dates.format(it) },
            groups = groups,
        )
    }

    fun parseSchedule(html: String): OnDutySchedule {
        val doc = Jsoup.parse(html, W4Hosts.ORIGIN)
        val root = doc.getElementById("content_inner") ?: doc.body() ?: return OnDutySchedule()
        val navText = root.selectFirst(".calendar-div .nav, .nav")?.text().orEmpty()
        val monthYear = MONTH_YEAR.find(navText)
        val monthName = monthYear?.groupValues?.getOrNull(1)
        val year = monthYear?.groupValues?.getOrNull(2)?.toIntOrNull()
        val month = monthName?.let { parseMonth(it) }
        val days = root.select("table.calendar td.day").mapNotNull { cell ->
            parseCalendarDay(cell, year, month)
        }
        return OnDutySchedule(
            monthLabel = listOfNotNull(monthName, year?.toString()).joinToString(" ").ifBlank { null },
            year = year,
            month = month,
            days = days,
        )
    }

    fun upcomingDays(
        schedule: OnDutySchedule,
        from: LocalDate = W4Dates.today(),
        limit: Int = 14,
    ): List<OnDutyDay> {
        return schedule.days
            .asSequence()
            .filter { day ->
                val date = day.date
                !day.people.isEmpty() && (date == null || !date.isBefore(from.plusDays(1)))
            }
            .take(limit)
            .toList()
    }

    fun enrich(people: List<OnDutyPerson>, contacts: List<OnDutyPerson>): List<OnDutyPerson> {
        if (contacts.isEmpty()) return people
        return people.map { person ->
            val match = contacts.firstOrNull { other ->
                namesMatch(person.name, other.name) ||
                    (!person.uwcId.isNullOrBlank() && person.uwcId.equals(other.uwcId, ignoreCase = true))
            } ?: return@map person
            person.copy(
                uwcId = person.uwcId ?: match.uwcId,
                phone = person.phone ?: match.phone,
                email = person.email ?: match.email,
                location = person.location ?: match.location,
                photoUrl = person.photoUrl ?: match.photoUrl,
            )
        }
    }

    fun enrich(day: OnDutyDay, contacts: List<OnDutyPerson>): OnDutyDay {
        if (contacts.isEmpty()) return day
        return day.copy(
            groups = day.groups.map { group ->
                group.copy(people = enrich(group.people, contacts))
            },
        )
    }

    private fun parseRoleGroups(root: Element): List<OnDutyGroup> {
        val headings = root.select("h3")
        if (headings.isEmpty()) {
            val people = parsePeopleIn(root, role = "On duty")
            return if (people.isEmpty()) emptyList() else listOf(OnDutyGroup("On duty", people))
        }
        val groups = mutableListOf<OnDutyGroup>()
        for (heading in headings) {
            val role = heading.text().trim().ifBlank { "On duty" }
            val people = mutableListOf<OnDutyPerson>()
            var sibling = heading.nextElementSibling()
            while (sibling != null && !sibling.tagName().equals("h3", ignoreCase = true)) {
                people += parsePeopleIn(sibling, role)
                sibling = sibling.nextElementSibling()
            }
            if (people.isNotEmpty()) {
                groups += OnDutyGroup(role = role, people = people.distinctBy { it.id })
            }
        }
        return groups
    }

    private fun parsePeopleIn(root: Element, role: String): List<OnDutyPerson> {
        val tables = root.select("table")
        val innermost = tables.filter { table ->
            !hasNestedTable(table) && looksLikePersonCard(table)
        }
        val cards = innermost.ifEmpty { tables.filter(::looksLikePersonCard) }
        if (cards.isEmpty()) return emptyList()
        val seen = linkedSetOf<String>()
        val people = mutableListOf<OnDutyPerson>()
        for (card in cards) {
            val person = parsePersonCard(card, role) ?: continue
            if (!seen.add(person.id)) continue
            people += person
        }
        return people
    }

    private fun looksLikePersonCard(table: Element): Boolean =
        table.selectFirst("img[src*=user_photos], img[alt*=Photo of]") != null ||
            labelledValue(table, "phone", "e-mail", "email") != null

    private fun hasNestedTable(table: Element): Boolean =
        table.getElementsByTag("table").any { it !== table }

    private fun parsePersonCard(card: Element, role: String): OnDutyPerson? {
        val img = card.selectFirst("img[src*=user_photos], img[alt*=Photo of], img")
        val uwcId = uwcIdFrom(img) ?: W4Html.UWC_ID.find(card.html())?.groupValues?.get(1)?.lowercase()
        val name = displayName(card) ?: return null
        val phone = labelledValue(card, "phone")
        val email = labelledValue(card, "e-mail", "email")
        val location = labelledValue(card, "location")
        val photo = img?.let {
            W4PeopleParser.absPhotoUrl(it.absUrl("src").ifBlank { it.attr("src") }, uwcId ?: "")
        } ?: uwcId?.let { W4PeopleParser.guessPhotoUrl(it) }
        val id = uwcId ?: slug("$role-$name")
        return OnDutyPerson(
            id = id,
            name = name,
            role = role,
            uwcId = uwcId,
            phone = phone,
            email = email,
            location = location,
            photoUrl = photo,
        )
    }

    private fun parseCalendarDay(cell: Element, year: Int?, month: Int?): OnDutyDay? {
        val dayNumber = cell.selectFirst(".day-header")?.text()?.trim()?.toIntOrNull() ?: return null
        val date = if (year != null && month != null) {
            runCatching { LocalDate.of(year, month, dayNumber) }.getOrNull()
        } else {
            null
        }
        val groups = parseCalendarGroups(cell.selectFirst(".day-content") ?: cell, date, dayNumber)
        if (groups.isEmpty() && !cell.hasClass("today")) return null
        val label = date?.format(DISPLAY_DAY)
            ?: dayNumber.toString()
        return OnDutyDay(
            id = date?.toString() ?: "day-$dayNumber",
            date = date,
            dateLabel = label,
            isToday = cell.hasClass("today"),
            groups = groups,
        )
    }

    private fun parseCalendarGroups(content: Element, date: LocalDate?, dayNumber: Int): List<OnDutyGroup> {
        val groups = mutableListOf<OnDutyGroup>()
        var currentRole: String? = null
        val currentPeople = mutableListOf<OnDutyPerson>()

        fun flush() {
            val role = currentRole?.trim()?.ifBlank { null } ?: return
            if (currentPeople.isEmpty()) return
            groups += OnDutyGroup(role, currentPeople.toList())
            currentPeople.clear()
        }

        for (child in content.children()) {
            when {
                child.hasClass("onduty-group-name") -> {
                    flush()
                    currentRole = child.text().trim()
                }
                child.hasClass("onduty-group") -> {
                    val role = currentRole?.trim()?.ifBlank { null } ?: "On duty"
                    val names = splitNames(child)
                    val dayKey = date?.toString() ?: "day-$dayNumber"
                    currentPeople += names.map { name ->
                        OnDutyPerson(
                            id = slug("$dayKey-$role-$name"),
                            name = name,
                            role = role,
                        )
                    }
                }
            }
        }
        flush()
        return groups
    }

    private fun splitNames(element: Element): List<String> {
        val html = element.html()
        return html.split(Regex("""<br\s*/?>""", RegexOption.IGNORE_CASE))
            .map { Jsoup.parse(it).text().trim() }
            .filter { it.isNotEmpty() }
            .ifEmpty {
                element.text().split('\n').map { it.trim() }.filter { it.isNotEmpty() }
            }
    }

    private fun displayName(card: Element): String? {
        card.select("b").forEach { bold ->
            val text = bold.ownText().ifBlank { bold.text() }.trim().trimEnd(':')
            if (text.isNotEmpty() && text.lowercase() !in FIELD_LABELS) return text
        }
        return null
    }

    private fun labelledValue(root: Element, vararg labels: String): String? {
        val wanted = labels.map { it.lowercase().trimEnd(':') }.toSet()
        for (bold in root.select("b")) {
            val label = bold.text().trim().trimEnd(':').lowercase()
            if (label !in wanted) continue
            val bits = StringBuilder()
            var node = bold.nextSibling()
            while (node != null) {
                when (node) {
                    is Element -> {
                        if (node.tagName().equals("br", ignoreCase = true)) break
                        if (node.tagName().equals("b", ignoreCase = true)) break
                        bits.append(node.text())
                    }
                    is TextNode -> bits.append(node.text())
                    else -> bits.append(node.toString())
                }
                node = node.nextSibling()
            }
            val value = bits.toString()
                .replace("\u00a0", " ")
                .replace("&nbsp;", " ", ignoreCase = true)
                .trim()
            if (value.isNotEmpty()) return value
        }
        return null
    }

    private fun uwcIdFrom(img: Element?): String? {
        if (img == null) return null
        val haystack = listOf(img.attr("alt"), img.attr("src"), img.absUrl("src")).joinToString(" ")
        return W4Html.UWC_ID.find(haystack)?.groupValues?.get(1)?.lowercase()
    }

    private fun dateFromHeading(heading: String?): LocalDate? {
        if (heading.isNullOrBlank()) return null
        DATE_IN_TEXT.find(heading)?.value?.let { W4Dates.parse(it) }?.let { return it }
        return W4Dates.parse(heading)
    }

    private fun parseMonth(raw: String): Int? {
        val trimmed = raw.trim()
        Month.entries.firstOrNull {
            it.getDisplayName(TextStyle.FULL, Locale.UK).equals(trimmed, ignoreCase = true) ||
                it.getDisplayName(TextStyle.SHORT, Locale.UK).equals(trimmed, ignoreCase = true)
        }?.let { return it.value }
        return trimmed.toIntOrNull()?.takeIf { it in 1..12 }
    }

    private fun namesMatch(a: String, b: String): Boolean {
        val left = a.trim().lowercase()
        val right = b.trim().lowercase()
        if (left.isEmpty() || right.isEmpty()) return false
        return left == right
    }

    private fun slug(value: String): String =
        value.lowercase()
            .replace(Regex("""\s+"""), "-")
            .replace(Regex("""[^a-z0-9@._+-]+"""), "")
            .ifBlank { value }
}
