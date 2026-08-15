package dk.betterlectio.android.core.lectio.scrape

import org.jsoup.Jsoup

data class StudentIdentity(
    val studentId: String?,
    val teacherId: String?,
    val name: String?,
    val pictureId: String?,
) {
    val isTeacher: Boolean get() = !teacherId.isNullOrBlank()
    val personId: String? get() = studentId ?: teacherId
}

data class StudentIdentityDebugSignals(
    val hasMetaStartUrl: Boolean,
    val elevidLinkCount: Int,
    val laereridLinkCount: Int,
    val elevidRegexCount: Int,
    val laereridRegexCount: Int,
    val studentContextCardCount: Int,
    val teacherContextCardCount: Int,
    val firstStudentContextCard: String?,
    val firstTeacherContextCard: String?,
    val title: String?,
    val header: String?,
    val pictureId: String?,
)

/**
 * Parse student id / name / picture from Lectio page chrome.
 *
 * Sources (in priority order), matching both Flutter and iOS:
 * 1. Flutter / lectio_wrapper: `meta[name=msapplication-starturl]` → `elevid` / `laererid`
 * 2. iOS `StudentParser.parseStudentInfo`: first `a[href*=elevid]` / `a[href*=laererid]`
 * 3. Regex fallback on raw HTML for `elevid=` / `laererid=` (covers minified / odd markup)
 * 4. `data-lectiocontextcard` self-links like `S123…` / `T123…`
 */
object StudentIdentityParser {

    private const val META_START_URL = "msapplication-starturl"
    private const val ELEV_ID_KEY = "elevid"
    private const val LAERER_ID_KEY = "laererid"

    private val elevIdInUrl = Regex("""elevid=(\d+)""", RegexOption.IGNORE_CASE)
    private val laererIdInUrl = Regex("""laererid=(\d+)""", RegexOption.IGNORE_CASE)
    private val contextCard = Regex("""data-lectiocontextcard=["']([ST])(\d+)["']""", RegexOption.IGNORE_CASE)

    fun parse(html: String): StudentIdentity {
        val doc = Jsoup.parse(html)

        var studentId: String? = null
        var teacherId: String? = null

        // 1) Flutter: msapplication-starturl meta
        val meta = doc.selectFirst("meta[name=$META_START_URL]")
            ?.attr("content")
        val metaQueries = AspNetForm.queriesFromUrl(meta)
        studentId = metaQueries[ELEV_ID_KEY]?.takeIf { it.isNotBlank() }
        teacherId = metaQueries[LAERER_ID_KEY]?.takeIf { it.isNotBlank() }

        // 2) iOS: first link containing elevid / laererid
        if (studentId.isNullOrBlank()) {
            studentId = firstIdFromLinks(doc, elevIdInUrl, "a[href*=elevid]")
        }
        if (teacherId.isNullOrBlank() && studentId.isNullOrBlank()) {
            teacherId = firstIdFromLinks(doc, laererIdInUrl, "a[href*=laererid]")
        }

        // 3) Regex over full HTML (handles non-anchor URLs, script vars, etc.)
        if (studentId.isNullOrBlank()) {
            studentId = elevIdInUrl.find(html)?.groupValues?.getOrNull(1)
        }
        if (teacherId.isNullOrBlank() && studentId.isNullOrBlank()) {
            teacherId = laererIdInUrl.find(html)?.groupValues?.getOrNull(1)
        }

        // 4) Context card. The authenticated Skema page can contain several context cards
        // for classes/teachers, but Supabase/iOS resolve the logged-in student from the
        // first S-card when query links are absent.
        if (studentId.isNullOrBlank() && teacherId.isNullOrBlank()) {
            val cards = contextCard.findAll(html)
                .map { it.groupValues[1].uppercase() to it.groupValues[2] }
                .distinct()
                .toList()
            val studentCard = cards.firstOrNull { it.first == "S" }
            val teacherCard = cards.firstOrNull { it.first == "T" }
            studentId = studentCard?.second
            if (studentId.isNullOrBlank()) {
                teacherId = teacherCard?.second
            }
        }

        var pictureId: String? = null
        val img = doc.getElementById("s_m_HeaderContent_picctrlthumbimage")
            ?: doc.selectFirst("img#s_m_HeaderContent_picctrlthumbimage")
        val src = img?.attr("src")
        if (!src.isNullOrBlank() && src.contains("pictureid", ignoreCase = true)) {
            pictureId = AspNetForm.queriesFromUrl(src)["pictureid"]
                ?: Regex("""pictureid=(\d+)""", RegexOption.IGNORE_CASE)
                    .find(src)?.groupValues?.getOrNull(1)
        }

        var name: String? = null
        val title = doc.getElementById("s_m_HeaderContent_MainTitle")?.text()
        if (!title.isNullOrBlank()) {
            name = parseNameFromTitle(title)
        }
        if (name.isNullOrBlank()) {
            // iOS: subHeaderDiv "Elev: Name …"
            val header = doc.selectFirst("div[id*=subHeaderDiv]")?.text().orEmpty()
            val elevMatch = Regex("""Elev:\s*(.+?)(?:\s*\(|$)""", RegexOption.IGNORE_CASE)
                .find(header)
            name = elevMatch?.groupValues?.getOrNull(1)?.trim()?.takeIf { it.isNotEmpty() }
        }

        return StudentIdentity(
            studentId = studentId,
            teacherId = teacherId,
            name = name,
            pictureId = pictureId,
        )
    }

    fun debugSignals(html: String): StudentIdentityDebugSignals {
        val doc = Jsoup.parse(html)
        val cards = contextCard.findAll(html)
            .map { it.groupValues[1].uppercase() to it.groupValues[2] }
            .distinct()
            .toList()
        val studentCards = cards.filter { it.first == "S" }
        val teacherCards = cards.filter { it.first == "T" }
        val pictureSrc = doc.getElementById("s_m_HeaderContent_picctrlthumbimage")
            ?.attr("src")
            .orEmpty()
        val pictureId = AspNetForm.queriesFromUrl(pictureSrc)["pictureid"]
            ?: Regex("""pictureid=(\d+)""", RegexOption.IGNORE_CASE)
                .find(pictureSrc)?.groupValues?.getOrNull(1)

        return StudentIdentityDebugSignals(
            hasMetaStartUrl = doc.selectFirst("meta[name=$META_START_URL]") != null,
            elevidLinkCount = doc.select("a[href*=elevid]").size,
            laereridLinkCount = doc.select("a[href*=laererid]").size,
            elevidRegexCount = elevIdInUrl.findAll(html).count(),
            laereridRegexCount = laererIdInUrl.findAll(html).count(),
            studentContextCardCount = studentCards.size,
            teacherContextCardCount = teacherCards.size,
            firstStudentContextCard = studentCards.firstOrNull()?.second,
            firstTeacherContextCard = teacherCards.firstOrNull()?.second,
            title = doc.getElementById("s_m_HeaderContent_MainTitle")
                ?.text()
                ?.take(120),
            header = doc.selectFirst("div[id*=subHeaderDiv]")
                ?.text()
                ?.take(160),
            pictureId = pictureId,
        )
    }

    private fun firstIdFromLinks(
        doc: org.jsoup.nodes.Document,
        pattern: Regex,
        css: String,
    ): String? {
        for (link in doc.select(css)) {
            val href = link.attr("href")
            val id = pattern.find(href)?.groupValues?.getOrNull(1)
            if (!id.isNullOrBlank()) return id
        }
        return null
    }

    internal fun parseNameFromTitle(title: String): String? {
        val trimmed = title.trim()
        // "Eleven NAME, class" / "Eleven NAME - class" / "Lærer NAME"
        val afterPrefix = when {
            trimmed.contains("Eleven ", ignoreCase = true) ->
                trimmed.substringAfter("Eleven ", missingDelimiterValue = trimmed)
            trimmed.contains("Lærer ", ignoreCase = true) ->
                trimmed.substringAfter("Lærer ", missingDelimiterValue = trimmed)
            else -> trimmed
        }
        // Strip optional (k) kostelev marker before comma/dash split
        val withoutKost = afterPrefix.replace(Regex("""\(k\)""", RegexOption.IGNORE_CASE), "")
        val namePart = withoutKost.split(',', '–', '-').firstOrNull()?.trim()
        return namePart?.takeIf { it.isNotEmpty() }
    }
}
