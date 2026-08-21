package dk.betterw4.android.feature.birthdays

import dk.betterw4.android.core.w4.W4Hosts
import dk.betterw4.android.core.w4.W4Html
import dk.betterw4.android.core.w4.W4Urls
import dk.betterw4.android.feature.directory.W4PeopleParser
import org.jsoup.Jsoup
import org.jsoup.nodes.Element
import java.time.LocalDate
import java.time.Month
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.util.Locale

/**
 * `people/birthdays` and `people/birthdays/index&month=&year=`.
 *
 * Live capture 21 Aug 2026: `.calendar-div .nav` ("August 2026") plus
 * `table.calendar td.day`. Each person is `a[title][href*=uwc_id] > img.photo`.
 * Staff and students share the grid; kind is decided per href.
 */
object W4BirthdayParser {

    private val MONTH_YEAR = Regex("""([A-Za-z]+)\s+(\d{4})""")
    private val MONTH_QUERY = Regex("""[?&]month=(\d{1,2})""", RegexOption.IGNORE_CASE)
    private val YEAR_QUERY = Regex("""[?&]year=(\d{4})""", RegexOption.IGNORE_CASE)
    private val PHOTO_OF = Regex("""^photo of\s+""", RegexOption.IGNORE_CASE)
    private val DISPLAY_DAY = DateTimeFormatter.ofPattern("EEE d MMM", Locale.UK)

    fun parse(html: String): BirthdayMonth {
        val doc = Jsoup.parse(html, W4Hosts.ORIGIN)
        val root = doc.getElementById("content_inner") ?: doc.body() ?: return BirthdayMonth()
        val nav = root.selectFirst(".calendar-div .nav") ?: root.selectFirst(".nav")
        val navText = nav?.text().orEmpty()
        val monthYear = MONTH_YEAR.find(navText)
        val monthName = monthYear?.groupValues?.getOrNull(1)
        val year = monthYear?.groupValues?.getOrNull(2)?.toIntOrNull()
        val month = monthName?.let { parseMonth(it) }
        val (previousLink, nextLink) = adjacentRefs(nav, year, month)
        val previous = previousLink ?: fallbackAdjacent(year, month, -1)
        val next = nextLink ?: fallbackAdjacent(year, month, 1)
        val days = root.select("table.calendar td.day").mapNotNull { parseDay(it, year, month) }
        val label = listOfNotNull(monthName, year?.toString()).joinToString(" ").ifBlank { null }
        return BirthdayMonth(
            monthLabel = label,
            year = year,
            month = month,
            previous = previous,
            next = next,
            days = days,
        )
    }

    private fun parseDay(cell: Element, year: Int?, month: Int?): BirthdayDay? {
        val dayNumber = cell.selectFirst(".day-header")?.text()?.trim()?.toIntOrNull()
            ?: cell.ownText().trim().toIntOrNull()
            ?: return null
        if (dayNumber <= 0) return null
        val date = if (year != null && month != null) {
            runCatching { LocalDate.of(year, month, dayNumber) }.getOrNull()
        } else {
            null
        }
        val content = cell.selectFirst(".day-content") ?: cell
        val people = uniqued(content.select("a[href*=uwc_id]").mapNotNull { parsePerson(it) })
        val label = date?.format(DISPLAY_DAY) ?: dayNumber.toString()
        return BirthdayDay(
            date = date,
            dayNumber = dayNumber,
            dateLabel = label,
            people = people,
        )
    }

    private fun parsePerson(anchor: Element): BirthdayPerson? {
        val href = anchor.attr("abs:href").ifBlank { anchor.attr("href") }
        val uwcId = W4Html.UWC_ID.find(href)?.groupValues?.get(1)?.lowercase() ?: return null
        val isStaff = href.contains("people/staff", ignoreCase = true)
        val img = anchor.selectFirst("img.photo, img")
        val photo = img?.let {
            W4PeopleParser.absPhotoUrl(it.absUrl("src").ifBlank { it.attr("src") }, uwcId)
        }
        val name = displayName(anchor.attr("title"), uwcId)
            ?: displayName(anchor.ownText().ifBlank { null }, uwcId)
            ?: displayName(img?.attr("alt"), uwcId)
        val route = if (isStaff) {
            "${W4Urls.Routes.STAFF_PROFILE}&uwc_id=$uwcId"
        } else {
            "${W4Urls.Routes.STUDENT_PROFILE}&uwc_id=$uwcId"
        }
        return BirthdayPerson(
            uwcId = uwcId,
            name = name,
            isStaff = isStaff,
            profileRoute = route,
            photoUrl = photo,
        )
    }

    private fun displayName(raw: String?, uwcId: String): String? {
        var value = raw?.replace('\u00a0', ' ')?.trim().orEmpty()
        if (value.isEmpty()) return null
        value = value.replace(PHOTO_OF, "").trim()
        if (value.isEmpty()) return null
        if (value.equals(uwcId, ignoreCase = true)) return null
        return value
    }

    private fun adjacentRefs(
        nav: Element?,
        year: Int?,
        month: Int?,
    ): Pair<BirthdayMonthRef?, BirthdayMonthRef?> {
        var previous: BirthdayMonthRef? = null
        var next: BirthdayMonthRef? = null
        for (link in nav?.select("a[href*=month]").orEmpty()) {
            val ref = monthRef(link.attr("href")) ?: continue
            if (year != null && month != null) {
                if (ref.year < year || (ref.year == year && ref.month < month)) {
                    previous = ref
                } else {
                    next = ref
                }
            } else if (previous == null) {
                previous = ref
            } else {
                next = ref
            }
        }
        return previous to next
    }

    private fun monthRef(href: String?): BirthdayMonthRef? {
        val decoded = href?.trim().orEmpty()
        if (decoded.isEmpty()) return null
        val month = MONTH_QUERY.find(decoded)?.groupValues?.getOrNull(1)?.toIntOrNull()
        val year = YEAR_QUERY.find(decoded)?.groupValues?.getOrNull(1)?.toIntOrNull()
        if (month == null || year == null || month !in 1..12) return null
        return BirthdayMonthRef(year, month)
    }

    private fun fallbackAdjacent(year: Int?, month: Int?, offset: Int): BirthdayMonthRef? {
        if (year == null || month == null) return null
        return BirthdayMonthRef(year, month).offset(offset)
    }

    private fun parseMonth(raw: String): Int? {
        val trimmed = raw.trim()
        Month.entries.firstOrNull {
            it.getDisplayName(TextStyle.FULL, Locale.UK).equals(trimmed, ignoreCase = true) ||
                it.getDisplayName(TextStyle.SHORT, Locale.UK).equals(trimmed, ignoreCase = true)
        }?.let { return it.value }
        return trimmed.toIntOrNull()?.takeIf { it in 1..12 }
    }

    private fun uniqued(people: List<BirthdayPerson>): List<BirthdayPerson> {
        val seen = linkedSetOf<String>()
        return people.filter { seen.add(it.uwcId.lowercase()) }
    }
}
