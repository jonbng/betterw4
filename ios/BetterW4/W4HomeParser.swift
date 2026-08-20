//
//  W4HomeParser.swift
//  BetterW4
//
//  Parser for the W4 Home page, `index.php?r=site/index`.
//
//  Spec: docs/spec/parsers.md §13 · docs/spec/features.md §1.16 ·
//  plan Wave 4 item 4.6.
//
//  Home is the richest capture we have (`references/pages/UWCRCN W4.html`,
//  sanitized to `BetterW4Tests/Fixtures/W4/home.html`), so nearly everything
//  below is verified markup rather than inference. The two exceptions are
//  called out inline: populated announcement *items* (the capture shows only
//  the empty state) and the shape of anything W4 might add later.
//
//  Rules this file obeys:
//    * pure and synchronous — `(String) -> HomePage`, no I/O, no actor hops,
//      no singletons, safe to call from any isolation domain;
//    * never throws, never force-unwraps, never assumes a node exists — a page
//      that changed shape degrades to `HomePage.empty` (or to a partially
//      filled page) plus a logged warning;
//    * HTML is read with SwiftSoup only; regex is used exclusively on text that
//      SwiftSoup already extracted, never over markup;
//    * `#links` is parsed dynamically. It is configuration, not code
//      (README §6) — nothing about the ten captured entries is hardcoded.
//
//  Deliberately **not** parsed here (other Wave 4 items own them):
//  `#timetable` (4.1), `#absences` (4.4), `.status-dropdown` and
//  `div.notifications` (4.5).
//

import Foundation
import OSLog
import SwiftSoup

enum W4HomeParser {

    // MARK: - Entry point

    /// Parses `r=site/index`. Never throws: an unparseable or unrecognised
    /// page yields `HomePage.empty` and a warning.
    nonisolated static func parse(_ html: String) -> HomePage {
        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            warn("empty document")
            return .empty
        }
        guard let document = try? SwiftSoup.parse(html) else {
            warn("SwiftSoup could not parse the document")
            return .empty
        }
        return parse(document: document)
    }

    /// Same as `parse(_:)` for callers that already hold a parsed document
    /// (the Home response feeds several parsers; parsing it once is cheaper).
    nonisolated static func parse(document: Document) -> HomePage {
        var page = HomePage()

        let greeting = parseGreeting(document)
        page.greetingText = greeting.text
        page.greetingName = greeting.name
        page.uwcId = greeting.uwcId
        page.publicProfileRoute = greeting.profileRoute
        page.publicProfileURL = greeting.profileURL

        page.birthdaysToday = parseBirthdays(document, containerSelector: "#birthdays-today")
        page.birthdaysTomorrow = parseBirthdays(document, containerSelector: "#birthdays-tomorrow")
        page.birthdaysCalendarURL = parseBirthdaysCalendarURL(document)

        let announcements = parseAnnouncements(document)
        page.announcements = announcements.items
        page.announcementsEmptyText = announcements.emptyText
        page.announcementsRSSURL = announcements.rssURL

        page.links = parseLinks(document)

        let version = parseVersion(document)
        page.serverVersion = version.version
        page.releaseNotesURL = version.releaseNotesURL

        if page.isEmpty {
            warn("no recognisable Home blocks found (#hello, #birthdays, #announcements, #links, #version)")
        }
        return page
    }

    // MARK: - #hello — greeting and the signed-in student's own identity

    /// `#hello` **[V]**:
    ///
    /// ```html
    /// <div id="hello">
    ///   <p>Hello Alex Andersen</p>
    ///   <p>Go to your <a href="…?r=people/students/student&uwc_id=nc26abcd">W4 public profile</a></p>
    /// </div>
    /// ```
    ///
    /// This is the authoritative source of the signed-in student's UWC id: a
    /// document-wide `nc\d{2}[a-z]+` sweep on Home matches a birthday
    /// classmate first (bug B17).
    nonisolated static func parseGreeting(
        _ root: Element
    ) -> (text: String?, name: String?, uwcId: String?, profileRoute: String?, profileURL: URL?) {
        guard let hello = firstElement(root, "#hello") else {
            warn("#hello is missing — cannot read the greeting or the signed-in uwc id")
            return (nil, nil, nil, nil, nil)
        }

        let paragraphs = elements(hello, "p")
        let greetingLine = paragraphs
            .map { text(of: $0) }
            .first { $0.range(of: "^hello\\b", options: [.regularExpression, .caseInsensitive]) != nil }
            ?? paragraphs.map { text(of: $0) }.first { !$0.isEmpty }
            ?? text(of: hello)

        let greetingText = greetingLine.isEmpty ? nil : greetingLine
        let name = firstCapture("^[Hh]ello[,:]?\\s+(.+)$", in: greetingLine)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // The profile anchor: scoped to #hello so it can only ever be this
        // student's own link.
        let anchor = firstElement(hello, "a[href*=uwc_id]") ?? firstElement(hello, "a[href]")
        guard let anchor else {
            warn("#hello carries no profile link — uwc id unavailable")
            return (greetingText, emptyToNil(name), nil, nil, nil)
        }

        let href = attribute(of: anchor, "href")
        let url = absoluteURL(fromHref: href)
        let route = w4Route(from: url)
        let uwcId = self.uwcId(fromHref: href, url: url)
        if uwcId == nil {
            warn("#hello profile link has no recognisable uwc id")
        }
        return (greetingText, emptyToNil(name), uwcId, route, url)
    }

    // MARK: - #birthdays

    /// `#birthdays-today` / `#birthdays-tomorrow` **[V]**:
    /// `li > a[href*=uwc_id] > img.photo[alt="Photo of nc16efgh"]`.
    ///
    /// The capture contains photos and UWC ids and **no names at all**, which
    /// is why `HomeBirthday` has no name field. Both `people/students/student`
    /// and `people/staff/staff` links appear.
    ///
    /// An empty block (`<div>` with no `<ul>`) is normal and yields `[]`
    /// without a warning.
    nonisolated static func parseBirthdays(_ root: Element, containerSelector: String) -> [HomeBirthday] {
        guard let container = firstElement(root, containerSelector) else {
            // Not a failure on non-Home pages, which have no birthdays block.
            return []
        }

        var result: [HomeBirthday] = []
        var seen = Set<String>()
        for item in elements(container, "li") {
            let anchor = firstElement(item, "a[href*=uwc_id]") ?? firstElement(item, "a[href]")
            let href = anchor.map { attribute(of: $0, "href") } ?? ""
            let url = absoluteURL(fromHref: href)
            let image = firstElement(item, "img.photo") ?? firstElement(item, "img")

            var candidate = uwcId(fromHref: href, url: url)
            if candidate == nil, let image {
                // `alt="Photo of nc16efgh"` is the last honest fallback.
                candidate = firstUWCId(in: attribute(of: image, "alt"))
            }
            guard let resolvedId = candidate else {
                warn("birthday entry in \(containerSelector) carries no uwc id; skipped")
                continue
            }
            guard seen.insert(resolvedId).inserted else { continue }

            let route = w4Route(from: url)
            let source = image.map { attribute(of: $0, "src") } ?? ""
            result.append(
                HomeBirthday(
                    uwcId: resolvedId,
                    profileRoute: route,
                    profileURL: url,
                    isStaff: route?.hasPrefix("people/staff") == true,
                    photoSource: emptyToNil(source),
                    photoURL: photoURL(fromSource: source)
                )
            )
        }
        return result
    }

    /// `#birthdays div.calendar > a` → `r=people/birthdays` **[V]**.
    nonisolated static func parseBirthdaysCalendarURL(_ root: Element) -> URL? {
        let anchor = firstElement(root, "#birthdays a[href*=people/birthdays]")
            ?? firstElement(root, "#birthdays .calendar a[href]")
        guard let anchor else { return nil }
        return absoluteURL(fromHref: attribute(of: anchor, "href"))
    }

    // MARK: - #announcements

    /// `#announcements > #announcements-content` **[V]**.
    ///
    /// The captured state is empty — `<p>No announcements...</p>` — and that is
    /// reported honestly through `emptyText` rather than as a parse failure.
    /// The *item* selectors below are inferred from the rules `homepage.css`
    /// ships (`#announcements-content ul li dl dt`, `… dl dd`,
    /// `… dl dt span`, `.announcement-content`, `.announcement-meta`); no
    /// populated announcement has ever been captured.
    nonisolated static func parseAnnouncements(
        _ root: Element
    ) -> (items: [HomeAnnouncement], emptyText: String?, rssURL: URL?) {
        guard let container = firstElement(root, "#announcements-content")
            ?? firstElement(root, "#announcements") else {
            return ([], nil, rssURL(in: root))
        }

        let rss = rssURL(in: container) ?? rssURL(in: root)

        var emptyText: String?
        for paragraph in elements(container, "p") {
            let value = text(of: paragraph)
            if value.range(of: "^no announcements", options: [.regularExpression, .caseInsensitive]) != nil {
                emptyText = value
                break
            }
        }

        var items: [HomeAnnouncement] = []
        for item in elements(container, "ul li") {
            guard let announcement = parseAnnouncement(item) else { continue }
            items.append(announcement)
        }

        if items.isEmpty && emptyText == nil {
            warn("#announcements held neither items nor the captured empty state")
        }
        return (items, emptyText, rss)
    }

    private nonisolated static func parseAnnouncement(_ item: Element) -> HomeAnnouncement? {
        let dateElement = firstElement(item, "dl dt span")
            ?? firstElement(item, ".announcement-meta")
        let date = dateElement.map { text(of: $0) }

        var title = ""
        if let term = firstElement(item, "dl dt") {
            // `<dt>Title <span>date</span></dt>` — ownText() drops the span.
            title = term.ownText().trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty {
                title = stripping(date, from: text(of: term))
            }
        }
        if title.isEmpty, let heading = firstElement(item, "h4, .announcement-title, a") {
            title = text(of: heading)
        }

        let body = firstElement(item, "dl dd") ?? firstElement(item, ".announcement-content")
        let bodyHTML = body.flatMap { try? $0.html() }?.trimmingCharacters(in: .whitespacesAndNewlines)

        if title.isEmpty {
            let fallback = text(of: item)
            guard !fallback.isEmpty else { return nil }
            title = fallback
        }

        return HomeAnnouncement(
            id: "announcement-" + stableHash(title, date ?? "", bodyHTML ?? ""),
            title: title,
            date: emptyToNil(date),
            bodyHTML: emptyToNil(bodyHTML)
        )
    }

    private nonisolated static func rssURL(in root: Element) -> URL? {
        let anchor = firstElement(root, ".rss a[href]")
            ?? firstElement(root, "a[href*=site/rss]")
            ?? firstElement(root, "a[type=application/rss+xml]")
            ?? firstElement(root, "link[type=application/rss+xml]")
        guard let anchor else { return nil }
        return absoluteURL(fromHref: attribute(of: anchor, "href"))
    }

    // MARK: - #links

    /// `#links > h3 "Links" + ul > li > a` **[V]**.
    ///
    /// Parsed dynamically, in document order. The captured block holds ten
    /// entries mixing W4 routes with Google Sites / Drive / Forms and
    /// ManageBac; none of that is hardcoded, and ManageBac stays a plain link
    /// (README §7 — never scraped).
    nonisolated static func parseLinks(_ root: Element) -> [HomeLink] {
        guard let block = firstElement(root, "#links") ?? firstElement(root, "#alerts #links") else {
            // Non-Home pages have no links block; that is not an error.
            return []
        }

        var anchors = elements(block, "ul li a[href]")
        if anchors.isEmpty {
            anchors = elements(block, "a[href]")
        }

        var result: [HomeLink] = []
        var seen = Set<String>()
        for anchor in anchors {
            let href = attribute(of: anchor, "href")
            guard let url = absoluteURL(fromHref: href) else {
                warn("#links entry has an unusable href; skipped")
                continue
            }
            guard seen.insert(url.absoluteString).inserted else { continue }

            var title = text(of: anchor)
            if title.isEmpty {
                title = attribute(of: anchor, "title")
            }
            if title.isEmpty {
                // Derived, not invented: better than an unlabelled row.
                title = url.host ?? url.absoluteString
            }
            result.append(HomeLink(title: title, url: url, route: w4Route(from: url)))
        }

        if result.isEmpty {
            warn("#links exists but yielded no usable entries")
        }
        return result
    }

    // MARK: - #version

    /// `<div id="version">W4 v. <a href="…?r=site/relnotes">25.9.1</a></div>` **[V]**.
    /// Present on every authenticated page, not just Home.
    nonisolated static func parseVersion(_ root: Element) -> (version: String?, releaseNotesURL: URL?) {
        guard let element = firstElement(root, "#version") else { return (nil, nil) }

        let anchor = firstElement(element, "a[href*=site/relnotes]") ?? firstElement(element, "a[href]")
        let url = anchor.flatMap { absoluteURL(fromHref: attribute(of: $0, "href")) }

        var version: String?
        if let anchor {
            let label = text(of: anchor)
            if label.range(of: "^[0-9]+(\\.[0-9]+)*$", options: .regularExpression) != nil {
                version = label
            }
        }
        if version == nil {
            version = firstCapture("v\\.?\\s*([0-9]+(?:\\.[0-9]+)*)", in: text(of: element))
        }
        return (emptyToNil(version), url)
    }

    // MARK: - URLs and routes

    /// Resolves an `href`/`src` into an absolute URL, or `nil` when it is not
    /// something we can honestly resolve (a saved-page relative path such as
    /// `./UWCRCN W4_files/x.jpg`, or an empty attribute).
    nonisolated static func absoluteURL(fromHref raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        if trimmed.hasPrefix("/") || lower.hasPrefix("index.php") || trimmed.hasPrefix("?r=") {
            return W4Routes.resolve(trimmed)
        }
        // mailto:, tel:, and anything else that at least declares a scheme.
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        return nil
    }

    /// The W4 route of a URL in the project's route-with-siblings spelling —
    /// `documents/index&page_id=870`, which `W4Routes.url(_:)` accepts back
    /// verbatim. `nil` for anything that is not on the W4 host.
    nonisolated static func w4Route(from url: URL?) -> String? {
        guard let url, W4Routes.isW4Host(url.host) else { return nil }
        guard let base = W4Routes.route(of: url) else { return nil }

        var route = base
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        for item in items where item.name.lowercased() != "r" {
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            route += "&\(name)=\(item.value ?? "")"
        }
        return route
    }

    /// W4's own default avatar means "no photo", the same rule the people
    /// parser and the image loader use. A live `{uwc_id}_thumb.jpg` src is
    /// upgraded to the matching full portrait.
    private nonisolated static func photoURL(fromSource source: String) -> URL? {
        guard let url = absoluteURL(fromHref: source) else { return nil }
        if url.lastPathComponent.lowercased() == "user.png" { return nil }
        return W4PeopleParser.fullSizePhotoURL(from: url)
    }

    // MARK: - UWC ids

    /// `?uwc_id=nc26abcd` first, then any `nc\d{2}[a-z]+` inside the href.
    private nonisolated static func uwcId(fromHref href: String, url: URL?) -> String? {
        if let url,
           let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let value = items.first(where: { $0.name.lowercased() == "uwc_id" })?.value,
           let id = firstUWCId(in: value) {
            return id
        }
        return firstUWCId(in: href)
    }

    private nonisolated static func firstUWCId(in text: String) -> String? {
        // One definition of the id shape lives in `W4Html`; do not fork it.
        firstCapture(W4Html.uwcIdPattern, in: text, caseInsensitive: true)?.lowercased()
    }

    // MARK: - SwiftSoup helpers

    private nonisolated static func firstElement(_ root: Element, _ query: String) -> Element? {
        guard let found = try? root.select(query) else { return nil }
        return found.first()
    }

    private nonisolated static func elements(_ root: Element, _ query: String) -> [Element] {
        guard let found = try? root.select(query) else { return [] }
        return found.array()
    }

    private nonisolated static func text(of element: Element) -> String {
        ((try? element.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func attribute(of element: Element, _ name: String) -> String {
        ((try? element.attr(name)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Text helpers (regex only ever runs on extracted text, never markup)

    private nonisolated static func firstCapture(
        _ pattern: String,
        in text: String,
        caseInsensitive: Bool = false
    ) -> String? {
        let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
        guard !text.isEmpty,
              let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: text) else { return nil }
        let value = String(text[captured]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private nonisolated static func stripping(_ suffix: String?, from text: String) -> String {
        guard let suffix, !suffix.isEmpty, let range = text.range(of: suffix) else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var copy = text
        copy.removeSubrange(range)
        return copy.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func emptyToNil(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// FNV-1a over the content. Deterministic across launches, unlike
    /// `Hasher`, which is seeded per process and would change every id.
    private nonisolated static func stableHash(_ parts: String...) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for part in parts {
            for byte in part.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x0000_0100_0000_01b3
            }
            hash ^= 0x1f
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    // MARK: - Logging

    /// Degrading is normal; crashing is not. Every fallback says so out loud.
    /// Static parser text only — no page content, no identifiers.
    private nonisolated static func warn(_ message: String) {
        Logger(subsystem: "dk.jonathanb.w4", category: "W4HomeParser")
            .warning("\(message, privacy: .public)")
    }
}
