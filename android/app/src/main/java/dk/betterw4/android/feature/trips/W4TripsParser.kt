package dk.betterw4.android.feature.trips

import dk.betterw4.android.core.w4.W4Dates
import dk.betterw4.android.core.w4.W4Urls
import org.jsoup.Jsoup
import org.jsoup.nodes.Element

data class W4Trip(
    val id: String,
    val name: String,
    val outgoing: String,
    val returning: String,
    val destination: String,
    val type: String,
    val participants: String,
    val status: String,
    val href: String? = null,
)

data class W4TripList(
    val title: String? = null,
    val trips: List<W4Trip> = emptyList(),
    val hasMorePages: Boolean = false,
    val emptyMessage: String? = null,
    val canPlanNewTrip: Boolean = false,
    val planNewTripHref: String? = null,
)

enum class TravelJourney {
    TO_SCHOOL_AUTUMN,
    HOME_WINTER,
    BACK_AFTER_WINTER,
    HOME_SUMMER,
    ;

    val displayName: String
        get() = when (this) {
            TO_SCHOOL_AUTUMN -> "To school in autumn"
            HOME_WINTER -> "Home for winter"
            BACK_AFTER_WINTER -> "Back after winter"
            HOME_SUMMER -> "Home for summer"
        }

    companion object {
        fun classify(text: String): TravelJourney? {
            val t = text.lowercase()
            return when {
                t.contains("autumn") || (t.contains("fall") && t.contains("school")) -> TO_SCHOOL_AUTUMN
                t.contains("winter") && (t.contains("home") || t.contains("leave")) -> HOME_WINTER
                t.contains("winter") && (t.contains("back") || t.contains("return") || t.contains("after")) ->
                    BACK_AFTER_WINTER
                t.contains("summer") -> HOME_SUMMER
                else -> null
            }
        }
    }
}

data class TravelForm(
    val id: String,
    val title: String,
    val status: String? = null,
    val href: String? = null,
    val journey: TravelJourney? = null,
)

data class TravelContact(
    val id: String,
    val name: String,
    val relation: String? = null,
    val phone: String? = null,
    val email: String? = null,
)

data class TravelPage(
    val title: String? = null,
    val forms: List<TravelForm> = emptyList(),
    val manageContactsHref: String? = null,
    val manageContactsLabel: String? = null,
    val emptyMessage: String? = null,
)

/**
 * Header-driven trips + travel parser matching iOS `W4TripsParser`.
 * Positional columns are used only when the grid has no header (never silently).
 */
object W4TripsParser {
    fun parse(html: String): List<W4Trip> = parseList(html).trips

    fun parseList(html: String): W4TripList {
        val doc = Jsoup.parse(html)
        val scope = doc.getElementById("content_inner") ?: doc.body()
        val title = heading(scope)
        val action = planNewTrip(scope)
        val table = gridTable(scope)
            ?: return W4TripList(
                title = title,
                emptyMessage = pageNote(scope),
                canPlanNewTrip = action.first,
                planNewTripHref = action.second,
            )
        val header = headerRow(table)
        var columns = header?.let { columnMap(cellElements(it)) } ?: Columns()
        val headerDriven = !columns.isEmpty
        if (columns.isEmpty) columns = Columns.inferred
        val trips = mutableListOf<W4Trip>()
        var emptyMessage: String? = null
        val seen = mutableMapOf<String, Int>()
        for (row in bodyRows(table, header)) {
            val cells = cellElements(row)
            val empty = emptyRowMessage(row, cells)
            if (empty != null) {
                if (emptyMessage == null) emptyMessage = empty
                continue
            }
            trip(row, cells, columns, seen)?.let { trips += it }
        }
        return W4TripList(
            title = title,
            trips = trips,
            hasMorePages = hasMorePages(scope),
            emptyMessage = emptyMessage ?: if (trips.isEmpty()) pageNote(scope) else null,
            canPlanNewTrip = action.first,
            planNewTripHref = action.second,
        ).also { @Suppress("UNUSED_VARIABLE") val driven = headerDriven }
    }

    fun parseTravel(html: String): TravelPage {
        val doc = Jsoup.parse(html)
        val scope = doc.getElementById("content_inner") ?: doc.body()
        val title = heading(scope)
        val contacts = manageContactsLink(scope)
        var forms = travelFormsFromGrid(scope, contacts?.first)
        if (forms.isEmpty()) forms = travelFormsFromLinks(scope, contacts?.first)
        return TravelPage(
            title = title,
            forms = forms,
            manageContactsHref = contacts?.first,
            manageContactsLabel = contacts?.second,
            emptyMessage = if (forms.isEmpty()) pageNote(scope) else null,
        )
    }

    fun parseTravelContacts(html: String): List<TravelContact> {
        val doc = Jsoup.parse(html)
        val scope = doc.getElementById("content_inner") ?: doc.body()
        val table = gridTable(scope) ?: return emptyList()
        val header = headerRow(table)
        val columns = header?.let { contactColumnMap(cellElements(it)) } ?: ContactColumns()
        val contacts = mutableListOf<TravelContact>()
        var n = 0
        for (row in bodyRows(table, header)) {
            val cells = cellElements(row)
            if (emptyRowMessage(row, cells) != null) continue
            val values = cells.map { it.text().trim() }
            fun value(index: Int?): String? =
                index?.takeIf { it in values.indices }?.let { values[it].ifBlank { null } }
            val name = value(columns.name) ?: values.firstOrNull()?.ifBlank { null } ?: ""
            val email = value(columns.email) ?: schemeLink(row, "mailto:")
            val phone = value(columns.phone) ?: schemeLink(row, "tel:")
            val relation = value(columns.relation)
            if (name.isEmpty() && email == null && phone == null) continue
            n++
            contacts += TravelContact(
                id = "contact-$n",
                name = name,
                relation = relation,
                phone = phone,
                email = email,
            )
        }
        return contacts
    }

    private data class Columns(
        val name: Int? = null,
        val outgoing: Int? = null,
        val returning: Int? = null,
        val destination: Int? = null,
        val type: Int? = null,
        val participants: Int? = null,
        val status: Int? = null,
    ) {
        val isEmpty: Boolean
            get() = name == null && outgoing == null && returning == null &&
                destination == null && type == null && participants == null && status == null

        companion object {
            val inferred = Columns(0, 1, 2, 3, 4, 5, 6)
        }
    }

    private fun columnMap(cells: List<Element>): Columns {
        var name: Int? = null
        var outgoing: Int? = null
        var returning: Int? = null
        var destination: Int? = null
        var type: Int? = null
        var participants: Int? = null
        var status: Int? = null
        cells.forEachIndexed { index, cell ->
            val label = cell.text().trim().lowercase()
            if (label.isEmpty()) return@forEachIndexed
            when {
                status == null && contains(label, listOf("status", "approval", "state")) -> status = index
                participants == null && contains(label, listOf("participant", "attendee", "student", "people", "member")) ->
                    participants = index
                destination == null && contains(label, listOf("destination", "location", "place", "venue", "where")) ->
                    destination = index
                type == null && contains(label, listOf("type", "category", "kind")) -> type = index
                outgoing == null && contains(label, listOf("outgoing", "depart", "leav", "start")) -> outgoing = index
                returning == null && contains(label, listOf("return", "back", "arriv", "coming")) -> returning = index
                name == null && contains(label, listOf("name", "title", "description", "trip")) -> name = index
            }
        }
        return Columns(name, outgoing, returning, destination, type, participants, status)
    }

    private fun trip(
        row: Element,
        cells: List<Element>,
        columns: Columns,
        occurrences: MutableMap<String, Int>,
    ): W4Trip? {
        val values = cells.map { it.text().trim() }
        fun value(index: Int?): String? =
            index?.takeIf { it in values.indices }?.let { values[it].ifBlank { null } }
        val link = rowLink(row)
        val href = link?.attr("href")?.trim()?.ifBlank { null }
        val name = value(columns.name) ?: link?.text()?.trim()?.ifBlank { null } ?: values.firstOrNull() ?: ""
        val outgoing = value(columns.outgoing).orEmpty()
        val returning = value(columns.returning).orEmpty()
        val destination = value(columns.destination).orEmpty()
        val type = value(columns.type).orEmpty()
        val participants = value(columns.participants).orEmpty()
        val status = value(columns.status).orEmpty()
        if (name.isEmpty() && outgoing.isEmpty() && destination.isEmpty() && status.isEmpty()) return null
        val base = href?.let { ID_QUERY.find(it)?.groupValues?.get(1) }?.let { "trip-$it" }
            ?: "trip-${name.lowercase()}-$outgoing-$destination"
        val seen = occurrences[base] ?: 0
        occurrences[base] = seen + 1
        val id = if (seen == 0) base else "$base-$seen"
        return W4Trip(
            id = id,
            name = name,
            outgoing = outgoing,
            returning = returning,
            destination = destination,
            type = type,
            participants = participants,
            status = status,
            href = href,
        )
    }

    private data class TravelColumns(val title: Int? = null, val status: Int? = null)
    private data class ContactColumns(
        val name: Int? = null,
        val relation: Int? = null,
        val phone: Int? = null,
        val email: Int? = null,
    )

    private fun travelFormsFromGrid(scope: Element, excluding: String?): List<TravelForm> {
        val table = gridTable(scope) ?: return emptyList()
        val header = headerRow(table)
        val columns = header?.let { travelColumnMap(cellElements(it)) } ?: TravelColumns()
        val forms = mutableListOf<TravelForm>()
        val seen = mutableMapOf<String, Int>()
        for (row in bodyRows(table, header)) {
            val cells = cellElements(row)
            if (emptyRowMessage(row, cells) != null) continue
            val values = cells.map { it.text().trim() }
            fun value(index: Int?): String? =
                index?.takeIf { it in values.indices }?.let { values[it].ifBlank { null } }
            val link = rowLink(row)
            val href = link?.attr("href")?.trim()?.ifBlank { null }
            if (href != null && href == excluding) continue
            val title = value(columns.title) ?: link?.text()?.trim()?.ifBlank { null }
                ?: values.firstOrNull()?.ifBlank { null } ?: continue
            forms += travelForm(title, value(columns.status), href, seen)
        }
        return forms
    }

    private fun travelFormsFromLinks(scope: Element, excluding: String?): List<TravelForm> {
        val anchors = usableAnchors(scope)
        val onTravel = anchors.filter { a ->
            W4Urls.routeOf(a.attr("href"))?.lowercase()?.startsWith("academics/travel") == true
        }
        val candidates = if (onTravel.isEmpty()) {
            anchors.filter { TravelJourney.classify(it.text()) != null }
        } else {
            onTravel
        }
        val forms = mutableListOf<TravelForm>()
        val seen = mutableMapOf<String, Int>()
        val unique = mutableSetOf<String>()
        for (anchor in candidates) {
            val href = anchor.attr("href").trim().ifBlank { null }
            if (href != null && href == excluding) continue
            val title = anchor.text().trim()
            if (title.isEmpty()) continue
            val key = "${href.orEmpty()}|${title.lowercase()}"
            if (!unique.add(key)) continue
            forms += travelForm(title, null, href, seen)
        }
        return forms
    }

    private fun travelForm(
        title: String,
        status: String?,
        href: String?,
        occurrences: MutableMap<String, Int>,
    ): TravelForm {
        val journey = TravelJourney.classify(title)
        val base = href?.let { ID_QUERY.find(it)?.groupValues?.get(1) }?.let { "travel-$it" }
            ?: journey?.let { "travel-${it.name.lowercase()}" }
            ?: "travel-${title.lowercase().hashCode()}"
        val seen = occurrences[base] ?: 0
        occurrences[base] = seen + 1
        return TravelForm(
            id = if (seen == 0) base else "$base-$seen",
            title = title,
            status = status,
            href = href,
            journey = journey,
        )
    }

    private fun travelColumnMap(cells: List<Element>): TravelColumns {
        var title: Int? = null
        var status: Int? = null
        cells.forEachIndexed { index, cell ->
            val label = cell.text().trim().lowercase()
            if (label.isEmpty()) return@forEachIndexed
            when {
                status == null && contains(label, listOf("status", "state", "submitted")) -> status = index
                title == null && contains(label, listOf("journey", "form", "travel", "name", "title")) ->
                    title = index
            }
        }
        return TravelColumns(title, status)
    }

    private fun contactColumnMap(cells: List<Element>): ContactColumns {
        var name: Int? = null
        var relation: Int? = null
        var phone: Int? = null
        var email: Int? = null
        cells.forEachIndexed { index, cell ->
            val label = cell.text().trim().lowercase()
            if (label.isEmpty()) return@forEachIndexed
            when {
                email == null && contains(label, listOf("email", "e-mail", "mail")) -> email = index
                phone == null && contains(label, listOf("phone", "mobile", "tel", "number")) -> phone = index
                relation == null && contains(label, listOf("relation", "role", "type", "kind")) -> relation = index
                name == null && contains(label, listOf("name", "contact")) -> name = index
            }
        }
        return ContactColumns(name, relation, phone, email)
    }

    private fun manageContactsLink(scope: Element): Pair<String, String>? {
        for (anchor in usableAnchors(scope)) {
            val label = anchor.text().trim()
            if (!label.contains("contact", ignoreCase = true)) continue
            val href = anchor.attr("href").trim().ifBlank { continue }
            return href to label
        }
        return null
    }

    private fun planNewTrip(scope: Element): Pair<Boolean, String?> {
        for (el in scope.select("a[href], button, input")) {
            if (el.tagName() == "input") {
                val type = el.attr("type").lowercase()
                if (type !in setOf("button", "submit", "")) continue
            }
            val label = listOf(el.text(), el.attr("value"), el.attr("title")).joinToString(" ").lowercase()
            if ("new trip" !in label && "plan a trip" !in label) continue
            var href = el.attr("href").trim().ifBlank { null }
            if (href == "#" || href?.startsWith("javascript:", ignoreCase = true) == true) href = null
            return true to href
        }
        return false to null
    }

    private val TABLE_SELECTORS = listOf("div.grid-view table.items", "table.items", "table.grid-view", "table")

    private fun gridTable(scope: Element): Element? {
        var first: Element? = null
        for (selector in TABLE_SELECTORS) {
            val tables = scope.select(selector)
            if (first == null) first = tables.firstOrNull()
            tables.firstOrNull { it.select("td").isNotEmpty() }?.let { return it }
        }
        return first
    }

    private fun headerRow(table: Element): Element? {
        table.selectFirst("thead tr")?.takeIf { cellElements(it).isNotEmpty() }?.let { return it }
        return table.select("tr").firstOrNull { it.select("th").isNotEmpty() && it.select("td").isEmpty() }
    }

    private fun bodyRows(table: Element, header: Element?): List<Element> {
        var rows = table.select("tbody > tr")
        if (rows.isEmpty()) rows = table.select("tr")
        return rows.filter { row ->
            if (header != null && row === header) return@filter false
            row.select("td").isNotEmpty()
        }
    }

    private fun cellElements(row: Element): List<Element> =
        row.children().filter { it.tagName() == "td" || it.tagName() == "th" }

    /** B9: Yii empty states are td.empty, span.empty, and "No results found." */
    private fun emptyRowMessage(row: Element, cells: List<Element>): String? {
        val marker = row.selectFirst("td.empty, span.empty")
        if (marker != null) {
            val message = marker.text().trim()
            return message.ifEmpty { "No results found." }
        }
        if (cells.size > 2) return null
        val joined = cells.joinToString(" ") { it.text().trim() }.trim()
        val normalized = joined.lowercase().trim('.', ' ')
        if (normalized.startsWith("no ") && normalized.endsWith("found")) return joined
        return null
    }

    private fun pageNote(scope: Element): String? {
        val direct = scope.children().firstOrNull { it.tagName() == "div" && it.hasClass("note") }
        if (direct != null) return direct.text().trim().ifBlank { null }
        return scope.selectFirst("div.note")?.text()?.trim()?.ifBlank { null }
    }

    private fun hasMorePages(scope: Element): Boolean {
        val links = scope.select("div.pager a[href], ul.yiiPager a[href]").filter {
            val href = it.attr("href").trim()
            href.isNotEmpty() && href != "#"
        }
        if (links.isNotEmpty()) return true
        val summary = scope.selectFirst("div.summary")?.text().orEmpty()
        val match = Regex("""(\d+)\s*-\s*(\d+)\s+of\s+(\d+)""", RegexOption.IGNORE_CASE).find(summary)
        if (match != null) {
            val shownEnd = match.groupValues[2].toIntOrNull() ?: return false
            val total = match.groupValues[3].toIntOrNull() ?: return false
            return shownEnd < total
        }
        return false
    }

    private fun heading(scope: Element): String? {
        for (sel in listOf("h2", "h1", "h3")) {
            scope.selectFirst(sel)?.text()?.trim()?.ifBlank { null }?.let { return it }
        }
        return null
    }

    private fun rowLink(row: Element): Element? {
        val links = usableAnchors(row)
        return links.firstOrNull { ID_QUERY.containsMatchIn(it.attr("href")) } ?: links.firstOrNull()
    }

    private fun usableAnchors(scope: Element): List<Element> =
        scope.select("a[href]").filter { a ->
            val href = a.attr("href").trim()
            href.isNotEmpty() && href != "#" && !href.startsWith("javascript:", ignoreCase = true)
        }

    private fun schemeLink(row: Element, scheme: String): String? {
        for (anchor in row.select("a[href]")) {
            val href = anchor.attr("href").trim()
            if (!href.startsWith(scheme, ignoreCase = true)) continue
            return href.removePrefix(scheme).ifBlank { null }
        }
        return null
    }

    private fun contains(haystack: String, needles: List<String>): Boolean =
        needles.any { haystack.contains(it) }

    private val ID_QUERY = Regex("""[?&]id=(\d+)""")

    @Suppress("unused")
    private fun parseStamp(raw: String?): java.time.LocalDateTime? =
        raw?.let { W4Dates.parseDateTime(it) }
}
