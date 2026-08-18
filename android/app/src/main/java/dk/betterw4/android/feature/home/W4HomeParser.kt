package dk.betterw4.android.feature.home

import dk.betterw4.android.core.w4.W4Hosts
import dk.betterw4.android.core.w4.W4Html
import dk.betterw4.android.core.w4.W4Urls
import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import org.jsoup.nodes.Element

data class HomeBirthday(
    val uwcId: String,
    val profileRoute: String? = null,
    val profileUrl: String? = null,
    val isStaff: Boolean = false,
    val photoUrl: String? = null,
)

data class HomeAnnouncement(
    val id: String,
    val title: String,
    val date: String? = null,
    val bodyHtml: String? = null,
)

data class HomeLink(
    val title: String,
    val url: String,
    val route: String? = null,
) {
    val isInternal: Boolean
        get() = route != null || W4Hosts.isW4Host(url.toHttpHost())
}

data class HomePage(
    val greetingText: String? = null,
    val greetingName: String? = null,
    val uwcId: String? = null,
    val publicProfileRoute: String? = null,
    val publicProfileUrl: String? = null,
    val birthdaysToday: List<HomeBirthday> = emptyList(),
    val birthdaysTomorrow: List<HomeBirthday> = emptyList(),
    val birthdaysCalendarUrl: String? = null,
    val announcements: List<HomeAnnouncement> = emptyList(),
    val announcementsEmptyText: String? = null,
    val announcementsRssUrl: String? = null,
    val links: List<HomeLink> = emptyList(),
    val serverVersion: String? = null,
    val releaseNotesUrl: String? = null,
) {
    val isEmpty: Boolean
        get() = greetingText == null &&
            birthdaysToday.isEmpty() &&
            birthdaysTomorrow.isEmpty() &&
            announcements.isEmpty() &&
            announcementsEmptyText == null &&
            links.isEmpty() &&
            serverVersion == null
}

/**
 * Home page parser matching iOS `W4HomeParser`.
 *
 * Deliberately does not parse `#timetable`, `#absences`, campus or the bell —
 * those have their own parsers and ride the same `site/index` response.
 */
object W4HomeParser {
    fun parse(html: String): HomePage {
        if (html.isBlank()) return HomePage()
        return parse(Jsoup.parse(html))
    }

    fun parse(document: Document): HomePage {
        val greeting = parseGreeting(document)
        val announcements = parseAnnouncements(document)
        val version = parseVersion(document)
        return HomePage(
            greetingText = greeting.text,
            greetingName = greeting.name,
            uwcId = greeting.uwcId,
            publicProfileRoute = greeting.profileRoute,
            publicProfileUrl = greeting.profileUrl,
            birthdaysToday = parseBirthdays(document, "#birthdays-today"),
            birthdaysTomorrow = parseBirthdays(document, "#birthdays-tomorrow"),
            birthdaysCalendarUrl = parseBirthdaysCalendarUrl(document),
            announcements = announcements.items,
            announcementsEmptyText = announcements.emptyText,
            announcementsRssUrl = announcements.rssUrl,
            links = parseLinks(document),
            serverVersion = version.version,
            releaseNotesUrl = version.releaseNotesUrl,
        )
    }

    private data class Greeting(
        val text: String?,
        val name: String?,
        val uwcId: String?,
        val profileRoute: String?,
        val profileUrl: String?,
    )

    private fun parseGreeting(root: Element): Greeting {
        val hello = root.selectFirst("#hello") ?: return Greeting(null, null, null, null, null)
        val paragraphs = hello.select("p").map { it.text().trim() }.filter { it.isNotEmpty() }
        val greetingLine = paragraphs.firstOrNull { it.startsWith("hello", ignoreCase = true) }
            ?: paragraphs.firstOrNull()
            ?: hello.text().trim()
        val greetingText = greetingLine.ifBlank { null }
        val name = Regex("""^[Hh]ello[,:]?\s+(.+)$""").find(greetingLine)?.groupValues?.get(1)?.trim()
        val anchor = hello.selectFirst("a[href*=uwc_id]") ?: hello.selectFirst("a[href]")
            ?: return Greeting(greetingText, name?.ifBlank { null }, null, null, null)
        val href = anchor.attr("href")
        val url = absoluteUrl(href)
        return Greeting(
            text = greetingText,
            name = name?.ifBlank { null },
            uwcId = uwcId(href, url),
            profileRoute = w4Route(url),
            profileUrl = url,
        )
    }

    private fun parseBirthdays(root: Element, containerSelector: String): List<HomeBirthday> {
        val container = root.selectFirst(containerSelector) ?: return emptyList()
        val result = mutableListOf<HomeBirthday>()
        val seen = mutableSetOf<String>()
        for (item in container.select("li")) {
            val anchor = item.selectFirst("a[href*=uwc_id]") ?: item.selectFirst("a[href]")
            val href = anchor?.attr("href").orEmpty()
            val url = absoluteUrl(href)
            val image = item.selectFirst("img.photo") ?: item.selectFirst("img")
            var id = uwcId(href, url)
            if (id == null && image != null) {
                id = W4Html.UWC_ID.find(image.attr("alt"))?.groupValues?.get(1)?.lowercase()
            }
            if (id == null || !seen.add(id)) continue
            val route = w4Route(url)
            val src = image?.attr("src").orEmpty()
            result += HomeBirthday(
                uwcId = id,
                profileRoute = route,
                profileUrl = url,
                isStaff = route?.startsWith("people/staff") == true,
                photoUrl = photoUrl(src),
            )
        }
        return result
    }

    private fun parseBirthdaysCalendarUrl(root: Element): String? {
        val anchor = root.selectFirst("#birthdays a[href*=people/birthdays]")
            ?: root.selectFirst("#birthdays .calendar a[href]")
        return anchor?.attr("href")?.let { absoluteUrl(it) }
    }

    private data class Announcements(
        val items: List<HomeAnnouncement>,
        val emptyText: String?,
        val rssUrl: String?,
    )

    private fun parseAnnouncements(root: Element): Announcements {
        val container = root.selectFirst("#announcements-content")
            ?: root.selectFirst("#announcements")
            ?: return Announcements(emptyList(), null, rssUrl(root))
        val rss = rssUrl(container) ?: rssUrl(root)
        var emptyText: String? = null
        for (p in container.select("p")) {
            val value = p.text().trim()
            if (value.startsWith("no announcements", ignoreCase = true)) {
                emptyText = value
                break
            }
        }
        val items = container.select("ul li").mapNotNull { parseAnnouncement(it) }
        return Announcements(items, emptyText, rss)
    }

    private fun parseAnnouncement(item: Element): HomeAnnouncement? {
        val dateEl = item.selectFirst("dl dt span") ?: item.selectFirst(".announcement-meta")
        val date = dateEl?.text()?.trim()?.ifBlank { null }
        var title = ""
        item.selectFirst("dl dt")?.let { term ->
            title = term.ownText().trim()
            if (title.isEmpty()) title = term.text().trim().removeSuffix(date.orEmpty()).trim()
        }
        if (title.isEmpty()) {
            title = item.selectFirst("h4, .announcement-title, a")?.text()?.trim().orEmpty()
        }
        val body = item.selectFirst("dl dd") ?: item.selectFirst(".announcement-content")
        val bodyHtml = body?.html()?.trim()?.ifBlank { null }
        if (title.isEmpty()) {
            title = item.text().trim()
            if (title.isEmpty()) return null
        }
        return HomeAnnouncement(
            id = "announcement-" + stableHash(title, date.orEmpty(), bodyHtml.orEmpty()),
            title = title,
            date = date,
            bodyHtml = bodyHtml,
        )
    }

    private fun rssUrl(root: Element): String? {
        val anchor = root.selectFirst(".rss a[href]")
            ?: root.selectFirst("a[href*=site/rss]")
            ?: root.selectFirst("a[type=application/rss+xml]")
            ?: root.selectFirst("link[type=application/rss+xml]")
        return anchor?.attr("href")?.let { absoluteUrl(it) }
            ?: anchor?.attr("href")?.let { absoluteUrl(it) }
    }

    private fun parseLinks(root: Element): List<HomeLink> {
        val block = root.selectFirst("#links") ?: root.selectFirst("#alerts #links") ?: return emptyList()
        var anchors = block.select("ul li a[href]")
        if (anchors.isEmpty()) anchors = block.select("a[href]")
        val result = mutableListOf<HomeLink>()
        val seen = mutableSetOf<String>()
        for (anchor in anchors) {
            val url = absoluteUrl(anchor.attr("href")) ?: continue
            if (!seen.add(url)) continue
            var title = anchor.text().trim()
            if (title.isEmpty()) title = anchor.attr("title").trim()
            if (title.isEmpty()) title = url.toHttpHost() ?: url
            result += HomeLink(title = title, url = url, route = w4Route(url))
        }
        return result
    }

    private data class Version(val version: String?, val releaseNotesUrl: String?)

    private fun parseVersion(root: Element): Version {
        val element = root.selectFirst("#version") ?: return Version(null, null)
        val anchor = element.selectFirst("a[href*=site/relnotes]") ?: element.selectFirst("a[href]")
        val url = anchor?.attr("href")?.let { absoluteUrl(it) }
        var version = anchor?.text()?.trim()?.takeIf { it.matches(Regex("""^[0-9]+(\.[0-9]+)*$""")) }
        if (version == null) {
            version = Regex("""v\.?\s*([0-9]+(?:\.[0-9]+)*)""", RegexOption.IGNORE_CASE)
                .find(element.text())
                ?.groupValues?.get(1)
        }
        return Version(version, url)
    }

    private fun absoluteUrl(raw: String): String? {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return null
        val lower = trimmed.lowercase()
        if (lower.startsWith("http://") || lower.startsWith("https://")) return trimmed
        if (trimmed.startsWith("/") || lower.startsWith("index.php") || trimmed.startsWith("?r=")) {
            return W4Urls.resolve(trimmed).toString()
        }
        if (":" in trimmed) return trimmed
        return null
    }

    private fun w4Route(url: String?): String? {
        if (url == null) return null
        val parsed = runCatching { java.net.URI(url) }.getOrNull() ?: return null
        if (!W4Hosts.isW4Host(parsed.host)) return null
        val base = W4Urls.routeOf(url) ?: return null
        val query = parsed.rawQuery ?: return base
        val extra = query.split('&')
            .mapNotNull { part ->
                val eq = part.indexOf('=')
                val name = if (eq < 0) part else part.substring(0, eq)
                if (name.equals("r", ignoreCase = true) || name.isBlank()) return@mapNotNull null
                val value = if (eq < 0) "" else part.substring(eq + 1)
                "$name=$value"
            }
        return if (extra.isEmpty()) base else base + "&" + extra.joinToString("&")
    }

    private fun uwcId(href: String, url: String?): String? {
        url?.let { W4Urls.resolve(it) }?.queryParameter("uwc_id")?.let { raw ->
            W4Html.UWC_ID.find(raw)?.groupValues?.get(1)?.lowercase()?.let { return it }
        }
        return W4Html.UWC_ID.find(href)?.groupValues?.get(1)?.lowercase()
    }

    private fun photoUrl(source: String): String? {
        val url = absoluteUrl(source) ?: return null
        if (url.substringAfterLast('/').equals("user.png", ignoreCase = true)) return null
        return url
    }

    private fun stableHash(vararg parts: String): String {
        var hash = 0xcbf29ce484222325UL
        for (part in parts) {
            for (byte in part.toByteArray()) {
                hash = hash xor (byte.toUByte().toULong())
                hash *= 0x100000001b3UL
            }
            hash = hash xor 0x1fUL
            hash *= 0x100000001b3UL
        }
        return hash.toString(16)
    }
}

private fun String.toHttpHost(): String? =
    runCatching { java.net.URI(this).host }.getOrNull()
