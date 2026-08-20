package dk.betterw4.android.feature.classes

import dk.betterw4.android.core.w4.W4Hosts
import dk.betterw4.android.core.w4.W4Html
import dk.betterw4.android.feature.directory.DirectoryEntityKind
import dk.betterw4.android.feature.directory.W4PeopleParser
import dk.betterw4.android.feature.schedule.W4ClassId
import org.jsoup.Jsoup
import org.jsoup.nodes.Element
import java.net.URLDecoder
import java.nio.charset.StandardCharsets

/**
 * `academics/classes/myclasses` and `academics/classes/class&class_id=`.
 *
 * Live capture 19 Aug 2026. The list is a `dl.class-list` of subject `<dt>`s
 * and one `<a class_id>` per class. The class page is `dl.class-details`
 * (subject / year / block / level / room) plus `ul.student-list` under
 * Teacher and Students headings.
 */
object W4ClassParser {

    private val CLASS_ID = Regex("""(?:\?|&)class_id=([^&#]+)""", RegexOption.IGNORE_CASE)
    private val ROOM_ID = Regex("""(?:\?|&)room_id=([^&#]+)""", RegexOption.IGNORE_CASE)
    private val CAPTION = Regex(
        """(?i)^([A-Za-z0-9]+):\s*(.+?)\s+(\d+)\s*(?:st|nd|rd|th)?\s*Year\s+([A-Z])\s+level(?:\s+with\s+(.+?))?(?:\s+in room\s+(.+))?$""",
    )

    data class ClassCaption(
        val code: String,
        val subject: String,
        val year: String?,
        val level: ClassLevel,
        val room: String?,
    )

    fun parseCaption(caption: String): ClassCaption? {
        val clean = caption.replace('\u00a0', ' ').replace(Regex("""\s+"""), " ").trim()
        val match = CAPTION.matchEntire(clean) ?: return null
        val code = match.groupValues[1].trim()
        val subject = match.groupValues[2].trim()
        val year = match.groupValues[3].trim().ifBlank { null }
        val level = ClassLevel.parse(match.groupValues[4])
        val room = match.groupValues.getOrNull(6)?.trim()?.ifBlank { null }
        if (code.isEmpty() || subject.isEmpty()) return null
        return ClassCaption(
            code = code,
            subject = subject,
            year = year,
            level = level,
            room = room,
        )
    }
    private val YEAR_NUMBER = Regex("""\d+""")
    private val LEADING_CODE = Regex("""^([A-Z]{3,5})\s+(.+)$""")

    fun parseIndex(html: String): List<MyClass> {
        val doc = Jsoup.parse(html, W4Hosts.ORIGIN)
        val root = doc.getElementById("content_inner") ?: doc.body() ?: return emptyList()
        val list = root.selectFirst("dl.class-list") ?: root
        val out = linkedMapOf<String, MyClass>()
        var subjectHeading: String? = null
        for (child in list.children()) {
            when (child.tagName().lowercase()) {
                "dt" -> subjectHeading = child.text().trim().ifBlank { null }
                "dd" -> {
                    for (anchor in child.select("a[href*=class_id]")) {
                        parseListLink(anchor, subjectHeading)?.let { parsed ->
                            out.putIfAbsent(parsed.id, parsed)
                        }
                    }
                }
            }
        }
        if (out.isEmpty()) {
            for (anchor in root.select("a[href*=class_id]")) {
                parseListLink(anchor, subjectHeading = null)?.let { parsed ->
                    out.putIfAbsent(parsed.id, parsed)
                }
            }
        }
        return out.values.toList()
    }

    fun parseClass(html: String, classId: String? = null): MyClass {
        val doc = Jsoup.parse(html, W4Hosts.ORIGIN)
        val root = doc.getElementById("content_inner") ?: doc.body() ?: doc
        val headingId = root.selectFirst("h2")?.text()
            ?.removePrefix("Class")
            ?.trim()
            ?.ifBlank { null }
        val id = classId?.trim()?.ifBlank { null }
            ?: headingId
            ?: classIdFromHref(html)
            ?: "unknown"

        val fields = parseDetails(root.selectFirst("dl.class-details"))
        val parsedId = W4ClassId.parse(id)
        val subjectRaw = fields["subject"]
        val subjectCode = parsedId?.subjectCode
            ?: subjectRaw?.let { LEADING_CODE.matchEntire(it.trim())?.groupValues?.get(1) }
        val subject = stripSubjectCode(subjectRaw, subjectCode)
            ?.ifBlank { null }
            ?: subjectCode
            ?: id

        val year = yearNumber(fields["year"]) ?: parsedId?.year?.toString()
        val block = fields["block"]?.trim()?.ifBlank { null } ?: parsedId?.block
        val levelRaw = fields["level"]
        val level = ClassLevel.parse(levelRaw)
            .takeIf { it != ClassLevel.UNKNOWN }
            ?: parsedId?.level?.toString()?.let { ClassLevel.parse(it) }
            ?: ClassLevel.UNKNOWN
        val levelLabel = levelLabelFrom(levelRaw, level)
        val room = parseRoom(root.selectFirst("dl.class-details"))

        val teachers = mutableListOf<ClassMember>()
        val students = mutableListOf<ClassMember>()
        var section: MemberSection = MemberSection.None
        for (child in root.children()) {
            when (child.tagName().lowercase()) {
                "h3" -> section = classifySection(child.text())
                "ul" -> {
                    if (!child.classNames().any { it.equals("student-list", ignoreCase = true) }) {
                        continue
                    }
                    when (section) {
                        MemberSection.Teachers -> teachers += parseMembers(child, DirectoryEntityKind.TEACHER)
                        MemberSection.Students -> students += parseMembers(child, DirectoryEntityKind.STUDENT)
                        MemberSection.None -> Unit
                    }
                }
            }
        }

        return MyClass(
            id = id,
            subject = subject,
            subjectCode = subjectCode,
            year = year,
            block = block,
            level = level,
            levelLabel = levelLabel,
            room = room,
            teachers = teachers.distinctBy { it.id },
            students = students.distinctBy { it.id },
            loaded = true,
        )
    }

    fun merge(base: MyClass, detail: MyClass): MyClass {
        val subject = preferSubjectName(base.subject, detail.subject)
        return base.copy(
            subject = subject,
            subjectCode = detail.subjectCode ?: base.subjectCode,
            year = detail.year ?: base.year,
            block = detail.block ?: base.block,
            level = if (detail.level != ClassLevel.UNKNOWN) detail.level else base.level,
            levelLabel = detail.levelLabel ?: base.levelLabel,
            room = detail.room ?: base.room,
            teachers = detail.teachers.ifEmpty { base.teachers },
            students = detail.students.ifEmpty { base.students },
            loaded = detail.loaded || base.loaded,
        )
    }

    fun classIdFromHref(href: String): String? {
        val decoded = runCatching {
            URLDecoder.decode(href, StandardCharsets.UTF_8.name())
        }.getOrDefault(href)
        return CLASS_ID.find(decoded)?.groupValues?.get(1)?.trim()?.ifBlank { null }
    }

    fun roomIdFromHref(href: String): String? {
        val decoded = runCatching {
            URLDecoder.decode(href, StandardCharsets.UTF_8.name())
        }.getOrDefault(href)
        return ROOM_ID.find(decoded)?.groupValues?.get(1)?.trim()?.ifBlank { null }
    }

    private fun parseListLink(anchor: Element, subjectHeading: String?): MyClass? {
        val href = anchor.attr("abs:href").ifBlank { anchor.attr("href") }
        val id = classIdFromHref(href) ?: return null
        val caption = anchor.text().replace('\u00a0', ' ').trim()
        val parsedId = W4ClassId.parse(id)
        val match = CAPTION.matchEntire(caption)
        val restSubject = match?.groupValues?.getOrNull(2)?.trim()
        val year = match?.groupValues?.getOrNull(3)?.trim()?.ifBlank { null }
            ?: parsedId?.year?.toString()
        val levelChar = match?.groupValues?.getOrNull(4)
        val level = ClassLevel.parse(levelChar)
            .takeIf { it != ClassLevel.UNKNOWN }
            ?: parsedId?.level?.toString()?.let { ClassLevel.parse(it) }
            ?: ClassLevel.UNKNOWN
        val teacherName = match?.groupValues?.getOrNull(5)?.trim()?.ifBlank { null }
        val roomName = match?.groupValues?.getOrNull(6)?.trim()?.ifBlank { null }
        val subject = subjectHeading?.takeIf { it.isNotBlank() }
            ?: restSubject
            ?: parsedId?.subjectCode
            ?: id
        val teachers = teacherName?.let {
            listOf(
                ClassMember(
                    id = slug("teacher-$it"),
                    name = it,
                    kind = DirectoryEntityKind.TEACHER,
                ),
            )
        }.orEmpty()
        return MyClass(
            id = id,
            subject = subject,
            subjectCode = parsedId?.subjectCode,
            year = year,
            block = parsedId?.block,
            level = level,
            levelLabel = level.badge.takeIf { it.isNotEmpty() },
            room = roomName?.let { ClassRoom(name = it) },
            teachers = teachers,
            loaded = false,
        )
    }

    private fun parseDetails(dl: Element?): Map<String, String> {
        if (dl == null) return emptyMap()
        val fields = linkedMapOf<String, String>()
        var pending: String? = null
        for (child in dl.children()) {
            when (child.tagName().lowercase()) {
                "dt" -> pending = child.text().trim().trimEnd(':').lowercase()
                "dd" -> {
                    val key = pending ?: continue
                    val value = child.text().replace('\u00a0', ' ').trim()
                    if (value.isNotEmpty()) fields[key] = value
                    pending = null
                }
            }
        }
        return fields
    }

    private fun parseRoom(dl: Element?): ClassRoom? {
        if (dl == null) return null
        var pending: String? = null
        for (child in dl.children()) {
            when (child.tagName().lowercase()) {
                "dt" -> pending = child.text().trim().trimEnd(':').lowercase()
                "dd" -> {
                    if (pending != "room") {
                        pending = null
                        continue
                    }
                    val link = child.selectFirst("a[href*=room_id]")
                    val name = (link?.text() ?: child.text()).replace('\u00a0', ' ').trim()
                    if (name.isEmpty()) return null
                    val href = link?.attr("abs:href").orEmpty().ifBlank { link?.attr("href").orEmpty() }
                    return ClassRoom(id = roomIdFromHref(href), name = name)
                }
            }
        }
        return null
    }

    private fun parseMembers(list: Element, defaultKind: DirectoryEntityKind): List<ClassMember> {
        val out = linkedMapOf<String, ClassMember>()
        for (item in list.select("> li")) {
            parseMember(item, defaultKind)?.let { out.putIfAbsent(it.id, it) }
        }
        return out.values.toList()
    }

    private fun parseMember(item: Element, defaultKind: DirectoryEntityKind): ClassMember? {
        val links = item.select("a[href*=uwc_id]")
        if (links.isEmpty()) return null
        val named: Element = links.firstOrNull { it.selectFirst("img") == null }
            ?: links.firstOrNull()
            ?: return null
        val href = named.attr("abs:href").ifBlank { named.attr("href") }
        val id = W4Html.UWC_ID.find(href)?.groupValues?.get(1)?.lowercase() ?: return null
        val kind = if (href.contains("people/staff", ignoreCase = true)) {
            DirectoryEntityKind.TEACHER
        } else {
            defaultKind
        }
        val name = named.ownText().ifBlank { named.text() }.trim()
            .replace(Regex("""Photo of\s+""", RegexOption.IGNORE_CASE), "")
            .ifBlank { id }
            .takeIf { !it.equals(id, ignoreCase = true) }
            ?: id
        val img = item.selectFirst("img.photo, img")
        val photo = img?.let {
            W4PeopleParser.absPhotoUrl(it.absUrl("src").ifBlank { it.attr("src") }, id)
        }
        val overlay = item.selectFirst(".level-overlay")?.text()?.trim()?.ifBlank { null }
        val level = ClassLevel.parse(overlay)
        return ClassMember(
            id = id,
            name = name,
            kind = kind,
            photoUrl = photo,
            level = level,
        )
    }

    private fun classifySection(title: String): MemberSection {
        val compact = title.lowercase().replace(Regex("""[^a-z]"""), "")
        return when {
            compact.startsWith("teacher") -> MemberSection.Teachers
            compact.startsWith("student") -> MemberSection.Students
            else -> MemberSection.None
        }
    }

    private fun yearNumber(raw: String?): String? =
        raw?.let { YEAR_NUMBER.find(it)?.value }

    private fun stripSubjectCode(raw: String?, code: String?): String? {
        val text = raw?.trim().orEmpty()
        if (text.isEmpty()) return null
        if (!code.isNullOrBlank() && text.startsWith(code, ignoreCase = true)) {
            return text.removePrefix(text.take(code.length)).trim().ifBlank { text }
        }
        return LEADING_CODE.matchEntire(text)?.groupValues?.get(2) ?: text
    }

    private fun preferSubjectName(left: String, right: String): String {
        val leftCode = LEADING_CODE.matchEntire(left.trim())
        val rightCode = LEADING_CODE.matchEntire(right.trim())
        return when {
            leftCode != null && rightCode == null -> right
            rightCode != null && leftCode == null -> left
            right.length > left.length -> right
            else -> left
        }.ifBlank { left.ifBlank { right } }
    }

    private fun levelLabelFrom(raw: String?, level: ClassLevel): String? {
        val text = raw?.trim().orEmpty()
        if (text.isEmpty()) return level.badge.takeIf { it.isNotEmpty() }
        val words = text.split(Regex("""\s+""")).filter { it.isNotBlank() }
        val long = words.drop(1).joinToString(" ").ifBlank { words.lastOrNull().orEmpty() }
        return when (level) {
            ClassLevel.HIGHER -> "HL"
            ClassLevel.STANDARD -> "SL"
            ClassLevel.COMBINED -> long.ifBlank { "Combined" }
            ClassLevel.NONE -> null
            ClassLevel.UNKNOWN -> long.ifBlank { text }
        }
    }

    private fun slug(value: String): String =
        value.lowercase()
            .replace(Regex("""\s+"""), "-")
            .replace(Regex("""[^a-z0-9@._+-]+"""), "")
            .ifBlank { value }

    private enum class MemberSection { None, Teachers, Students }
}
