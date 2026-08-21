//
//  W4PeopleParser.swift
//  BetterW4
//
//  Parses the W4 people directory into `PeopleModels.swift`:
//
//    * list pages — `people/students/all|firstyear|secondyear|byname|bypreferred|
//      bycountry|byhouse`, `people/students/staff&type=teachers|leaders`,
//      `people/staff/current|onleave` → `DirectoryPeoplePage`;
//    * public profiles — `people/students/student&uwc_id=`,
//      `people/staff/staff&uwc_id=`, and the signed-in student's own
//      `site/profile` → `DirectoryPersonProfile`.
//
//  Plan: `docs/W4_PORT_PLAN.md` Wave 4 item 4.7 (D-5 naming, D-30 pure parsers).
//  Spec: `docs/spec/parsers.md` §11 · `docs/spec/features.md` §1.12 ·
//  `docs/spec/reviewer-notes.md` §7.
//
//  EVIDENCE STATUS — read this before trusting any selector below.
//
//  **No people list page has ever been captured.** What is verified:
//
//    * the identity + photo shape, from the Home birthdays block
//      (`references/pages/UWCRCN W4.html:201-214`, mirrored in
//      `Fixtures/W4/home.html`): `a[href*=uwc_id] > img.photo` with
//      `alt="Photo of {uwc_id}"` and a `{uwc_id}_thumb.jpg` source, and the fact
//      that staff links read `people/staff/staff` while student links read
//      `people/students/student` **on the same page** — which is precisely why
//      the kind is decided per anchor and never by sniffing the document;
//    * the empty state, `<div class="note">No users found</div>`
//      (`references/pages/Current applicants at UWCRCN.html:81`);
//    * the grid cell classes `td.student-name`, `td.entry-name`, `tr.online
//      td.status` and `tr.offline td.status`, which exist in W4's own
//      `css/main.css` — so at least one people list *is* a Yii `CGridView`. The
//      rows themselves have never been seen.
//
//  Everything else — `ul.user-list`, the Yii pager, `table.detail-view` on a
//  profile — is inferred from the Android port and from Yii 1 conventions.
//  Consequently this file never throws, never force-unwraps, never subscripts
//  blindly, and degrades to an empty page (or a partially filled one) plus a
//  logged warning.
//
//  Purity: `nonisolated`, synchronous, `(String) -> Model`. No network, no
//  storage, no singletons, no clock reads.
//
//  PII: names and UWC ids are never logged. Every warning below is a static
//  string.
//

import Foundation
import OSLog
import SwiftSoup

enum W4PeopleParser {

    private static let log = Logger(
        subsystem: "dk.jonathanb.w4",
        category: "W4PeopleParser"
    )

    // MARK: - List pages

    /// Parses one people list page. Never throws: unparseable HTML, an
    /// unrecognised shape and W4's own "No users found" state all yield a
    /// `DirectoryPeoplePage` whose `people` is empty.
    nonisolated static func parseList(_ html: String) -> DirectoryPeoplePage {
        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            log.warning("People list body is empty; returning an empty page.")
            return DirectoryPeoplePage()
        }
        guard let document = try? SwiftSoup.parse(html) else {
            log.warning("People list is not parseable HTML; returning an empty page.")
            return DirectoryPeoplePage()
        }
        return parseList(document: document)
    }

    /// Same as `parseList(_:)` for callers that already hold a parsed document.
    nonisolated static func parseList(document: Document) -> DirectoryPeoplePage {
        let root = contentRoot(of: document)
        let people = parsePeople(in: root)
        let notice = parseNotice(in: root)

        if people.isEmpty && notice == nil {
            log.warning("People list held neither a person row nor an empty-state note.")
        }

        return DirectoryPeoplePage(
            heading: parseHeading(in: root),
            people: people,
            notice: notice,
            hasMorePages: parseHasMorePages(in: root)
        )
    }

    /// Convenience for callers that only want the rows.
    nonisolated static func parsePeople(_ html: String) -> [DirectoryPerson] {
        parseList(html).people
    }

    // MARK: - Profiles

    /// Parses a public profile (`people/students/student&uwc_id=`,
    /// `people/staff/staff&uwc_id=`) or the signed-in student's `site/profile`.
    ///
    /// - Parameter kind: pass it when the caller knows which route it fetched.
    ///   That is always better evidence than anything on the page, so it wins.
    /// - Returns: `nil` when the page carries no recognisable UWC id, which is
    ///   the only thing that makes a profile addressable at all.
    nonisolated static func parseProfile(
        _ html: String,
        kind explicitKind: DirectoryPersonKind? = nil
    ) -> DirectoryPersonProfile? {
        guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            log.warning("Profile body is empty; nothing to parse.")
            return nil
        }
        guard let document = try? SwiftSoup.parse(html) else {
            log.warning("Profile is not parseable HTML; nothing to parse.")
            return nil
        }
        return parseProfile(document: document, kind: explicitKind)
    }

    /// Same as `parseProfile(_:kind:)` for an already-parsed document.
    nonisolated static func parseProfile(
        document: Document,
        kind explicitKind: DirectoryPersonKind? = nil
    ) -> DirectoryPersonProfile? {
        let root = contentRoot(of: document)
        // Students: Yii `table.detail-view` (`site/profile`, inferred).
        // Staff: live `people/staff/staff` pages use `dl/dt/dd` plus class/EA lists.
        let view = firstElement(root, "table.detail-view") ?? root
        var fields = parseFields(in: view)
        fields.append(contentsOf: parseDefinitionList(in: root))

        guard let uwcId = profileUWCId(in: root, fields: fields) else {
            log.warning("Profile page carries no recognisable uwc id; returning nil.")
            return nil
        }

        let preferredName = value(fields, "preferred name", "preferred")
        let year = exactValue(fields, "study year", "year", "ib year").flatMap { normalizedYear($0) }
        let house = value(fields, "house")
        let houseId = profileHouseId(in: root)
        let room = exactValue(fields, "room")
        let country = value(fields, "country", "nationality") ?? sidebarCountry(in: root)
        let pronouns = value(fields, "pronouns", "pronoun")
        let positions = StaffRoles.parse(value(fields, "position", "positions", "role", "roles"))
        let taughtClasses = parseTaughtClasses(in: root)
        let activities = parseStaffActivities(in: root)
        let advisor = parseAdvisor(in: root)
        let graduationYear = exactValue(fields, "graduation year")

        let resolvedKind = explicitKind
            ?? profileKind(in: document, uwcId: uwcId)
            ?? inferredKind(positions: positions, activities: activities, fields: fields)
        if resolvedKind == nil {
            log.warning("Profile page states no kind for its own uwc id; assuming student.")
        }

        let kind = resolvedKind ?? .student
        let subtitle = kind == .staff
            ? staffSubtitle(positions: positions, country: country)
            : profileSubtitle(year: year, house: house, country: country)

        let person = DirectoryPerson(
            uwcId: uwcId,
            name: profileName(fields: fields, uwcId: uwcId),
            kind: kind,
            preferredName: preferredName,
            year: year,
            house: house,
            country: country,
            pronouns: pronouns,
            subtitle: subtitle,
            status: nil,
            isOnline: nil,
            photoURL: profilePhotoURL(in: root, uwcId: uwcId)
        )

        return DirectoryPersonProfile(
            person: person,
            birthday: value(fields, "birthday", "date of birth", "birth date", "dob"),
            lastLogin: value(fields, "last login", "last logged in", "last seen"),
            scrapedEmail: value(fields, "email", "e-mail", "e mail"),
            officeTel: value(fields, "office tel", "office telephone", "office phone"),
            mobile: value(fields, "mobile", "mobile phone", "cell"),
            houseId: houseId,
            room: room,
            graduationYear: graduationYear,
            advisor: advisor,
            positions: positions,
            taughtClasses: taughtClasses,
            activities: activities,
            fields: fields
        )
    }

    // MARK: - Identity from an href

    /// The UWC id an anchor points at: the `uwc_id` sibling parameter first,
    /// then any `nc\d{2}[a-z]+` inside the href.
    nonisolated static func uwcId(fromHref href: String) -> String? {
        let decoded = href.removingPercentEncoding ?? href
        if let raw = firstCapture("[?&]uwc_id=([^&#]+)", in: decoded),
           let id = firstUWCId(in: raw) {
            return id
        }
        return firstUWCId(in: decoded)
    }

    /// Student or staff, **decided from this one href** (parsers.md §11, "Kind
    /// detection").
    ///
    /// The Kotlin port sniffs the whole document for the substring
    /// `people/staff` (`W4PeopleParser.kt:67-73`); on any page that lists both —
    /// Home's birthdays, a mixed directory — that mislabels everybody. The route's
    /// last segment is the entity: `people/staff/staff` and
    /// `people/students/staff` are staff, `people/students/student` is a student.
    ///
    /// Returns `nil` when the href names no people route; callers decide what to
    /// do with that rather than getting a silent guess.
    nonisolated static func kind(fromHref href: String) -> DirectoryPersonKind? {
        let decoded = href.removingPercentEncoding ?? href
        guard let route = W4Routes.route(ofURLString: decoded)?.lowercased() else {
            // Not a Yii `r=` URL at all (a rewritten path, say) — read the path.
            let lower = decoded.lowercased()
            if lower.contains("people/staff") { return .staff }
            if lower.contains("people/students/student") { return .student }
            return nil
        }
        guard route.hasPrefix("people/") else { return nil }
        if let last = route.split(separator: "/").last.map(String.init) {
            if last.hasPrefix("staff") { return .staff }
            if last.hasPrefix("student") { return .student }
        }
        if route.hasPrefix("people/staff") { return .staff }
        if route.hasPrefix("people/students") { return .student }
        return nil
    }

    // MARK: - Photos

    /// The canonical full-size portrait for a UWC id:
    /// `https://w4.uwcrcn.no/files/user_photos/{uwc_id}_photo.jpg`.
    ///
    /// List pages and the Home birthdays block print `{uwc_id}_thumb.jpg`
    /// (**[V]** for the file-name shape, **[I]** for the directory, which every
    /// capture rewrote to a local `…_files/` path). We always request the
    /// matching `{uwc_id}_photo.jpg` file — `{uwc_id}.jpg` 404s on live W4.
    nonisolated static func photoURL(forUWCId uwcId: String) -> URL? {
        let id = uwcId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !id.isEmpty else { return nil }
        return URL(string: "\(W4Routes.origin)/files/user_photos/\(id)_photo.jpg")
    }

    /// List pages print `{uwc_id}_thumb.jpg`; the matching full portrait is
    /// `{uwc_id}_photo.jpg`. A guessed `{uwc_id}.jpg` 404s and is upgraded too.
    /// Already-full URLs are returned unchanged.
    nonisolated static func fullSizePhotoURL(from url: URL) -> URL {
        let stripped = url.absoluteString.replacingOccurrences(
            of: "_thumb.",
            with: ".",
            options: .caseInsensitive
        )
        let upgraded = stripped.replacingOccurrences(
            of: #"(/files/user_photos/)([A-Za-z0-9]+)(\.[A-Za-z0-9]+)"#,
            with: "$1$2_photo$3",
            options: [.regularExpression, .caseInsensitive]
        )
        return URL(string: upgraded) ?? url
    }

    /// Resolves an `img src` into a portrait URL, or `nil` for "no photo".
    ///
    /// `/images/user.png` is W4's missing-photo placeholder: rendering it as if
    /// it were a portrait is a bug, so it maps to `nil`. A "Save page as" local
    /// path (`./UWCRCN W4_files/nc00aaa_thumb.jpg`) is restored to the live
    /// full-size convention rather than dropped. A live `_thumb.jpg` src is
    /// upgraded to `{uwc_id}_photo.jpg`.
    nonisolated static func photoURL(fromSource raw: String, uwcId: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()
        guard !lower.hasPrefix("data:") else { return nil }
        guard fileName(of: trimmed).lowercased() != "user.png" else { return nil }

        if lower.contains("_files/") && !lower.contains("/files/user_photos/") {
            return photoURL(forUWCId: uwcId)
        }

        guard let url = absoluteURL(fromHref: trimmed) else { return nil }
        guard url.lastPathComponent.lowercased() != "user.png" else { return nil }
        return fullSizePhotoURL(from: url)
    }

    // MARK: - Rows

    /// Every person on the page, in document order, each appearing exactly once.
    ///
    /// One sweep over `a[href*=uwc_id]` handles both list shapes: the anchor's
    /// nearest `li` / `tr` ancestor decides how it is enriched, so a
    /// `ul.user-list` page, a `CGridView` page and a page carrying both parse the
    /// same way. A `<li>` normally holds **two** anchors for the same person
    /// (photo + name); they merge on the UWC id.
    private nonisolated static func parsePeople(in root: Element) -> [DirectoryPerson] {
        var order: [String] = []
        var drafts: [String: Draft] = [:]
        var sawUnknownKind = false

        for anchor in elements(root, "a[href*=uwc_id]") {
            guard !isChrome(anchor, upTo: root) else { continue }
            guard var draft = Self.draft(fromAnchor: anchor) else { continue }

            if draft.kind == nil { sawUnknownKind = true }

            if let owner = container(of: anchor, upTo: root) {
                if owner.tagName().lowercased() == "tr" {
                    enrich(&draft, fromRow: owner)
                } else {
                    enrich(&draft, fromListItem: owner)
                }
            }

            if let existing = drafts[draft.uwcId] {
                drafts[draft.uwcId] = merge(existing, draft)
            } else {
                drafts[draft.uwcId] = draft
                order.append(draft.uwcId)
            }
        }

        if sawUnknownKind {
            log.warning("A directory row names no people route; those rows default to student.")
        }
        return order.compactMap { drafts[$0]?.person() }
    }

    /// One anchor — the only place a person's id, kind and photo may come from.
    private nonisolated static func draft(fromAnchor anchor: Element) -> Draft? {
        let href = attribute(anchor, "href")
        guard let id = uwcId(fromHref: href) else { return nil }

        var draft = Draft(uwcId: id)
        draft.kind = kind(fromHref: href)

        let own = anchor.ownText()
        draft.name = displayName(own.isEmpty ? text(of: anchor) : own, uwcId: id)

        if let image = firstElement(anchor, "img.photo") ?? firstElement(anchor, "img") {
            let url = photoURL(fromSource: attribute(image, "src"), uwcId: id)
            draft.photoURL = url
            draft.photoIsCanonical = url.map { isCanonicalThumb($0) } ?? false
        }
        return draft
    }

    /// `ul.user-list > li` **[I]** — the Android fixture's shape:
    ///
    /// ```html
    /// <li><a …><img class="photo" src="…_thumb.jpg" alt="Photo of nc00aaa"></a>
    ///     <a …>Alex Andersen</a><br>Denmark<br>1<sup>st</sup> year<br></li>
    /// ```
    ///
    /// Everything below the name is free text split on `<br>`, joined with `·`
    /// and rendered verbatim — W4 never labels it, so nothing here is promoted
    /// into `country` or `house` on a guess.
    private nonisolated static func enrich(_ draft: inout Draft, fromListItem item: Element) {
        var lines = textLines(of: item, skippingTag: "a")

        // Last resort: a row whose anchors carry no text at all. Only then is the
        // first free-text line a name rather than a subtitle — and the check is
        // made against the whole `<li>`, so it cannot depend on which of the two
        // anchors we happen to be looking at.
        if draft.name == nil, !lines.isEmpty, !listItemCarriesAnchorName(item) {
            draft.name = displayName(lines.removeFirst(), uwcId: draft.uwcId)
        }

        if draft.subtitle == nil {
            draft.subtitle = emptyToNil(lines.joined(separator: " · "))
        }
        if draft.year == nil {
            draft.year = statedYear(inAnyOf: lines)
        }
    }

    /// The Yii `CGridView` variant. `td.student-name` / `td.entry-name` /
    /// `td.status` and `tr.online` / `tr.offline` are the classes W4's own
    /// `css/main.css` styles (**[V]** that they exist, **[I]** how a row uses
    /// them). Any other column is read through its `th` header — never by
    /// position — and otherwise falls through to the subtitle verbatim.
    private nonisolated static func enrich(_ draft: inout Draft, fromRow row: Element) {
        let cells = elements(row, "td")
        guard !cells.isEmpty else { return }

        let rowClasses = classNames(of: row)
        if rowClasses.contains("online") {
            draft.isOnline = true
        } else if rowClasses.contains("offline") {
            draft.isOnline = false
        }

        let values = cells.map { text(of: $0) }
        let headers = headerLabels(for: row)
        // Cells the UI renders on their own. Everything else still feeds the
        // subtitle, even when a header let us type it as well: promoting a column
        // to `country` must not make it vanish from the row's summary line.
        var rendered = Set<Int>()

        for (index, cell) in cells.enumerated() {
            let classes = classNames(of: cell)
            if classes.contains("student-name") || classes.contains("entry-name") {
                if draft.name == nil {
                    draft.name = displayName(values[index], uwcId: draft.uwcId)
                }
                rendered.insert(index)
            } else if classes.contains("status") {
                if draft.status == nil {
                    draft.status = emptyToNil(values[index])
                }
                rendered.insert(index)
            }
        }

        for (index, cellText) in values.enumerated() {
            guard index < headers.count else { break }
            let label = PersonProfileField.normalizedLabel(headers[index])
            guard !label.isEmpty, let clean = emptyToNil(cellText) else { continue }

            if label.contains("preferred") {
                if draft.preferredName == nil { draft.preferredName = clean }
            } else if label.contains("country") || label.contains("nationality") {
                if draft.country == nil { draft.country = clean }
            } else if label.contains("house") {
                if draft.house == nil { draft.house = clean }
            } else if label.contains("pronoun") {
                if draft.pronouns == nil { draft.pronouns = clean }
            } else if label.contains("year") {
                if draft.year == nil { draft.year = normalizedYear(clean) }
            } else if label.contains("status") {
                if draft.status == nil { draft.status = clean }
                rendered.insert(index)
            } else if label.contains("name") {
                if draft.name == nil { draft.name = displayName(clean, uwcId: draft.uwcId) }
                rendered.insert(index)
            }
        }

        var extras: [String] = []
        for (index, cellText) in values.enumerated() {
            guard !rendered.contains(index) else { continue }
            guard let clean = emptyToNil(cellText) else { continue }
            if let name = draft.name, clean.caseInsensitiveCompare(name) == .orderedSame { continue }
            if clean.caseInsensitiveCompare(draft.uwcId) == .orderedSame { continue }
            if firstUWCId(in: clean) != nil { continue }
            extras.append(clean)
        }

        if draft.subtitle == nil {
            draft.subtitle = emptyToNil(extras.prefix(3).joined(separator: " · "))
        }
        if draft.year == nil {
            draft.year = statedYear(inAnyOf: extras)
        }
    }

    /// True when some anchor in this `<li>` already carries a usable name.
    private nonisolated static func listItemCarriesAnchorName(_ item: Element) -> Bool {
        for anchor in elements(item, "a[href*=uwc_id]") {
            guard let id = uwcId(fromHref: attribute(anchor, "href")) else { continue }
            let own = anchor.ownText()
            if displayName(own.isEmpty ? text(of: anchor) : own, uwcId: id) != nil { return true }
        }
        return false
    }

    /// `thead th` (or the first row that has `th` cells) of the row's own table.
    private nonisolated static func headerLabels(for row: Element) -> [String] {
        guard let table = enclosingTable(of: row) else { return [] }
        var cells = elements(table, "thead tr th")
        if cells.isEmpty {
            if let headerRow = elements(table, "tr").first(where: { !elements($0, "th").isEmpty }) {
                cells = elements(headerRow, "th")
            }
        }
        return cells.map { text(of: $0) }
    }

    // MARK: - Page furniture

    /// `#content_inner` is the page body on every captured W4 page
    /// (parsers.md §0.3). Falling back to `<body>` keeps AJAX fragments and
    /// hand-written fixtures working.
    private nonisolated static func contentRoot(of document: Document) -> Element {
        if let inner = firstElement(document, "#content_inner") { return inner }
        if let main = firstElement(document, "#content_main") { return main }
        if let body = document.body() { return body }
        return document
    }

    private nonisolated static func parseHeading(in root: Element) -> String? {
        for selector in ["h2", "h1", "h3"] {
            if let element = firstElement(root, selector), let heading = emptyToNil(text(of: element)) {
                return heading
            }
        }
        return nil
    }

    /// `<div class="note">No users found</div>` — **[V]**, the real empty-state
    /// body of `references/pages/Current applicants at UWCRCN.html`. The
    /// `CGridView` `empty` cell is the **[I]** fallback.
    private nonisolated static func parseNotice(in root: Element) -> String? {
        if let note = firstElement(root, "div.note"), let message = emptyToNil(text(of: note)) {
            return message
        }
        if let empty = firstElement(root, ".grid-view .empty") ?? firstElement(root, ".empty"),
           let message = emptyToNil(text(of: empty)) {
            return message
        }
        return nil
    }

    /// **[I]** — no paged people list has ever been captured. This is the stock
    /// Yii 1 `CLinkPager` / `CGridView` summary shape. Reporting it lets the UI
    /// say "more on w4.uwcrcn.no" instead of silently truncating a 200-student
    /// directory (parsers.md §0.4).
    private nonisolated static func parseHasMorePages(in root: Element) -> Bool {
        for item in elements(root, ".pager li, ul.yiiPager li") {
            let classes = classNames(of: item)
            guard classes.contains("next") || classes.contains("last") else { continue }
            guard !classes.contains("hidden") else { continue }
            if firstElement(item, "a[href]") != nil { return true }
        }
        if let summary = firstElement(root, ".summary"),
           let numbers = captures("([0-9]+)\\s*-\\s*([0-9]+)\\s+of\\s+([0-9]+)", in: text(of: summary), count: 3),
           let shown = Int(numbers[1]), let total = Int(numbers[2]) {
            return shown < total
        }
        return false
    }

    // MARK: - Profile details

    /// Every `th` / `td` pair, in document order, kept verbatim so the UI can
    /// render fields this parser has never heard of.
    private nonisolated static func parseFields(in view: Element) -> [PersonProfileField] {
        var fields: [PersonProfileField] = []
        for row in elements(view, "tr") {
            let cells = elements(row, "td")
            let label: String
            let fieldValue: String

            if let header = firstElement(row, "th") {
                label = text(of: header)
                guard let first = cells.first else { continue }
                fieldValue = text(of: first)
            } else if let labelCell = firstElement(row, "td.label"), cells.count > 1 {
                label = text(of: labelCell)
                // `td.label` may not be the first cell; take the one after it.
                let index = (cells.firstIndex { $0 === labelCell }).map { $0 + 1 } ?? 1
                guard index < cells.count else { continue }
                fieldValue = text(of: cells[index])
            } else {
                continue
            }

            guard !label.isEmpty, !fieldValue.isEmpty else { continue }
            fields.append(PersonProfileField(label: label, value: fieldValue))
        }
        return fields
    }

    /// Ladder, strictest first. Deliberately **not** in the ladder:
    /// `W4Html.uwcId(_:)`, which reads the signed-in student's id out of the page
    /// chrome — on a classmate's profile that is the wrong person (the same
    /// mistake as bug B17 on Home).
    private nonisolated static func profileUWCId(
        in root: Element,
        fields: [PersonProfileField]
    ) -> String? {
        if let stated = value(fields, "uwc id", "username", "id") {
            if let id = firstUWCId(in: stated) ?? firstPersonId(in: stated) { return id }
        }
        if let image = firstElement(root, "img.user-photo") ?? firstElement(root, "img.photo") {
            if let id = firstUWCId(in: attribute(image, "alt")) ?? firstPersonId(in: attribute(image, "alt")) {
                return id
            }
            if let id = firstUWCId(in: attribute(image, "src")) ?? firstPersonId(in: attribute(image, "src")) {
                return id
            }
        }
        for anchor in elements(root, "a[href*=uwc_id]") where !isChrome(anchor, upTo: root) {
            if let id = uwcId(fromHref: attribute(anchor, "href")) { return id }
        }
        return nil
    }

    /// The kind of *this* profile, from an anchor that points at *this* id.
    ///
    /// Matching the anchor's `uwc_id` against the resolved id is what keeps this
    /// honest: a student's profile that links to their advisor still parses as a
    /// student, because the staff link carries a different id.
    private nonisolated static func profileKind(
        in document: Document,
        uwcId id: String
    ) -> DirectoryPersonKind? {
        for anchor in elements(document, "a[href*=uwc_id]") {
            let href = attribute(anchor, "href")
            guard uwcId(fromHref: href) == id else { continue }
            if let resolved = kind(fromHref: href) { return resolved }
        }
        return nil
    }

    private nonisolated static func profileName(
        fields: [PersonProfileField],
        uwcId: String
    ) -> String {
        let first = value(fields, "first name", "firstname", "given name")
        let last = value(fields, "last name", "lastname", "family name", "surname")
        let assembled = [first, last].compactMap { $0 }.joined(separator: " ")
        if let name = emptyToNil(assembled) { return name }
        if let name = value(fields, "full name", "name") { return name }
        if let preferred = value(fields, "preferred name", "preferred") { return preferred }
        // `DirectoryPerson.hasResolvedName` reports this honestly to the UI.
        return uwcId
    }

    private nonisolated static func profileSubtitle(
        year: String?,
        house: String?,
        country: String?
    ) -> String? {
        let parts = [year.map { "Year \($0)" }, house, country].compactMap { $0 }
        return emptyToNil(parts.joined(separator: " · "))
    }

    private nonisolated static func profilePhotoURL(in root: Element, uwcId: String) -> URL? {
        let image = firstElement(root, "img.user-photo")
            ?? firstElement(root, "img.photo")
            ?? elements(root, "img[src]").first {
                let src = attribute($0, "src").lowercased()
                return src.contains(uwcId.lowercased()) && !classNames(of: $0).contains("flag")
            }
        if let image, let url = photoURL(fromSource: attribute(image, "src"), uwcId: uwcId) {
            return url
        }
        if let pretty = firstElement(root, "a.pretty"),
           let url = photoURL(fromSource: attribute(pretty, "href"), uwcId: uwcId) {
            return url
        }
        return nil
    }

    private nonisolated static func parseDefinitionList(in root: Element) -> [PersonProfileField] {
        var fields: [PersonProfileField] = []
        for dt in elements(root, "dt") {
            let label = text(of: dt)
            guard !label.isEmpty else { continue }
            guard let dd = try? dt.nextElementSibling(), dd.tagName().lowercased() == "dd" else { continue }
            let fieldValue = text(of: dd)
            guard !fieldValue.isEmpty else { continue }
            fields.append(PersonProfileField(label: label, value: fieldValue))
        }
        return fields
    }

    private nonisolated static func parseTaughtClasses(in root: Element) -> [PersonClass] {
        guard let heading = elements(root, "h3").first(where: {
            text(of: $0).localizedCaseInsensitiveContains("class")
        }) else { return [] }
        guard let list = nextElement(heading, tag: "ul") else { return [] }
        var seen = Set<String>()
        var result: [PersonClass] = []
        for anchor in elements(list, "a[href*=class_id]") {
            let href = attribute(anchor, "href")
            guard let classId = ClassRoster.classId(from: href) else { continue }
            let key = classId.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            let caption = text(of: anchor)
            let parsed = W4ClassParser.parseCaption(caption)
            let fallbackName: String = {
                guard let rest = caption.split(separator: ":", maxSplits: 1).dropFirst().first else {
                    return caption
                }
                let trimmed = rest.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? caption : trimmed
            }()
            result.append(
                PersonClass(
                    classId: classId,
                    name: parsed?.subject ?? fallbackName,
                    year: parsed?.year,
                    levelLabel: emptyToNil(parsed?.level.badge),
                    teacher: parsed?.teacher,
                    room: parsed?.room
                )
            )
        }
        return result
    }

    private nonisolated static func parseStaffActivities(in root: Element) -> [StaffActivity] {
        guard let heading = elements(root, "h3").first(where: {
            let title = text(of: $0)
            return title.localizedCaseInsensitiveContains("EA activit")
                || title.localizedCaseInsensitiveContains("extra academic")
        }) else { return [] }
        guard let list = nextElement(heading, tag: "ul") else { return [] }
        return elements(list, "li").compactMap { item in
            let html = (try? item.html()) ?? ""
            let parts = html
                .replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
                .components(separatedBy: "\n")
                .map { stripTags($0) }
                .filter { !$0.isEmpty }
            let name: String
            if let anchor = firstElement(item, "a") {
                name = text(of: anchor)
            } else {
                name = parts.first ?? text(of: item)
            }
            guard !name.isEmpty else { return nil }
            let rest = parts.filter { $0.caseInsensitiveCompare(name) != .orderedSame }
            let dates = rest.first { $0.localizedCaseInsensitiveContains(" to ") }
            let category = rest.first { $0 != dates }
            return StaffActivity(name: name, dates: dates, category: category)
        }
    }

    private nonisolated static func sidebarCountry(in root: Element) -> String? {
        guard let sidebar = firstElement(root, ".image-sidebar") else { return nil }
        return elements(sidebar, "div")
            .map { text(of: $0) }
            .first { $0.count >= 3 && $0.count <= 40 && !$0.localizedCaseInsensitiveContains("flag") }
    }

    private nonisolated static func staffSubtitle(positions: [String], country: String?) -> String? {
        let roles = positions.prefix(3).joined(separator: " · ")
        let parts = [emptyToNil(roles), country].compactMap { $0 }
        return emptyToNil(parts.joined(separator: " · "))
    }

    private nonisolated static func nextElement(_ element: Element, tag: String) -> Element? {
        var current = try? element.nextElementSibling()
        while let node = current {
            if node.tagName().lowercased() == tag { return node }
            current = try? node.nextElementSibling()
        }
        return nil
    }

    private nonisolated static func firstPersonId(in source: String) -> String? {
        firstCapture(#"\b([A-Za-z]{2}\d{2}[A-Za-z]+)\b"#, in: source)?.lowercased()
    }

    private nonisolated static func stripTags(_ html: String) -> String {
        let withoutTags = html.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: "",
            options: .regularExpression
        )
        return collapse((withoutTags as NSString).replacingOccurrences(of: "&nbsp;", with: " "))
    }

    /// A class list is not evidence of staff — student profiles list classes too.
    /// Position / EA activities are staff-only; study year / graduation year are
    /// student-only.
    private nonisolated static func inferredKind(
        positions: [String],
        activities: [StaffActivity],
        fields: [PersonProfileField]
    ) -> DirectoryPersonKind? {
        if !positions.isEmpty || !activities.isEmpty { return .staff }
        if exactValue(fields, "study year", "graduation year") != nil { return .student }
        return nil
    }

    private nonisolated static func parseAdvisor(in root: Element) -> ProfileAdvisor? {
        for dt in elements(root, "dt") {
            let label = PersonProfileField.normalizedLabel(text(of: dt))
            guard label == "advisor" else { continue }
            guard let dd = try? dt.nextElementSibling(), dd.tagName().lowercased() == "dd" else {
                continue
            }
            guard let anchor = firstElement(dd, "a[href*=uwc_id]") else { continue }
            guard let id = uwcId(fromHref: attribute(anchor, "href")) else { continue }
            let name = text(of: anchor)
            guard !name.isEmpty else { continue }
            return ProfileAdvisor(uwcId: id, name: name)
        }
        return nil
    }

    private nonisolated static func profileHouseId(in root: Element) -> String? {
        for dt in elements(root, "dt") {
            let label = PersonProfileField.normalizedLabel(text(of: dt))
            guard label == "house" else { continue }
            guard let dd = try? dt.nextElementSibling(), dd.tagName().lowercased() == "dd" else {
                continue
            }
            guard let anchor = firstElement(dd, "a[href*=house_id]") else { continue }
            return W4HouseParser.houseId(fromHref: attribute(anchor, "href"))
        }
        return nil
    }

    /// Case- and punctuation-insensitive lookup over the verbatim field list:
    /// exact normalized match first, then a contains match, in the order the
    /// candidates are given.
    private nonisolated static func value(
        _ fields: [PersonProfileField],
        _ labels: String...
    ) -> String? {
        for label in labels {
            let wanted = PersonProfileField.normalizedLabel(label)
            guard !wanted.isEmpty else { continue }
            if let match = fields.first(where: { PersonProfileField.normalizedLabel($0.label) == wanted }) {
                return emptyToNil(match.value)
            }
        }
        for label in labels {
            let wanted = PersonProfileField.normalizedLabel(label)
            guard !wanted.isEmpty else { continue }
            if let match = fields.first(where: { PersonProfileField.normalizedLabel($0.label).contains(wanted) }) {
                return emptyToNil(match.value)
            }
        }
        return nil
    }

    private nonisolated static func exactValue(
        _ fields: [PersonProfileField],
        _ labels: String...
    ) -> String? {
        for label in labels {
            let wanted = PersonProfileField.normalizedLabel(label)
            guard !wanted.isEmpty else { continue }
            if let match = fields.first(where: { PersonProfileField.normalizedLabel($0.label) == wanted }) {
                return emptyToNil(match.value)
            }
        }
        return nil
    }

    // MARK: - Draft

    /// A person being assembled from however many anchors and cells mention
    /// them. Every field is optional until the row is finished, so a second
    /// anchor can only ever fill gaps — never overwrite what the first one knew.
    private struct Draft {
        var uwcId: String
        var name: String?
        var kind: DirectoryPersonKind?
        var preferredName: String?
        var year: String?
        var house: String?
        var country: String?
        var pronouns: String?
        var subtitle: String?
        var status: String?
        var isOnline: Bool?
        var photoURL: URL?
        var photoIsCanonical: Bool = false

        func person() -> DirectoryPerson {
            DirectoryPerson(
                uwcId: uwcId,
                name: name ?? uwcId,
                kind: kind ?? .student,
                preferredName: preferredName,
                year: year,
                house: house,
                country: country,
                pronouns: pronouns,
                subtitle: subtitle,
                status: status,
                isOnline: isOnline,
                photoURL: photoURL
            )
        }
    }

    private nonisolated static func merge(_ existing: Draft, _ incoming: Draft) -> Draft {
        var result = existing
        result.name = existing.name ?? incoming.name
        result.kind = existing.kind ?? incoming.kind
        result.preferredName = existing.preferredName ?? incoming.preferredName
        result.year = existing.year ?? incoming.year
        result.house = existing.house ?? incoming.house
        result.country = existing.country ?? incoming.country
        result.pronouns = existing.pronouns ?? incoming.pronouns
        result.subtitle = existing.subtitle ?? incoming.subtitle
        result.status = existing.status ?? incoming.status
        result.isOnline = existing.isOnline ?? incoming.isOnline

        let photo = pickPhoto(existing, incoming)
        result.photoURL = photo.url
        result.photoIsCanonical = photo.isCanonical
        return result
    }

    /// A real `/files/user_photos/…` portrait beats anything else; a name-only
    /// anchor must never clobber the photo anchor's portrait.
    private nonisolated static func pickPhoto(
        _ existing: Draft,
        _ incoming: Draft
    ) -> (url: URL?, isCanonical: Bool) {
        guard let incomingURL = incoming.photoURL else {
            return (existing.photoURL, existing.photoIsCanonical)
        }
        guard let existingURL = existing.photoURL else {
            return (incomingURL, incoming.photoIsCanonical)
        }
        if existing.photoIsCanonical { return (existingURL, true) }
        if incoming.photoIsCanonical { return (incomingURL, true) }
        return (existingURL, false)
    }

    private nonisolated static func isCanonicalThumb(_ url: URL) -> Bool {
        url.path.lowercased().contains("/files/user_photos/")
    }

    // MARK: - Names, years, ids

    /// A usable display name, or `nil` when the text is really an identifier.
    ///
    /// `alt="Photo of nc00aaa"` is **[V]** on Home and is an id with a prefix,
    /// not a name — strip the prefix and then refuse the bare id.
    private nonisolated static func displayName(_ raw: String, uwcId: String) -> String? {
        var value = collapse(raw)
        if let range = value.range(of: "^photo of\\s*", options: [.regularExpression, .caseInsensitive]) {
            value.removeSubrange(range)
            value = collapse(value)
        }
        guard !value.isEmpty else { return nil }
        guard value.caseInsensitiveCompare(uwcId) != .orderedSame else { return nil }
        guard value.caseInsensitiveCompare("id") != .orderedSame else { return nil }
        // A bare UWC id in the name column is an id column, not a name.
        if firstUWCId(in: value) == value.lowercased() { return nil }
        return value
    }

    /// `"1st year"` / `"Year 2"` → `"1"` / `"2"`. Free text only states a year
    /// when it says so; anything vaguer stays out of the model.
    private nonisolated static func statedYear(inAnyOf lines: [String]) -> String? {
        for line in lines {
            if let digit = firstCapture("\\b([12])\\s*(?:st|nd|rd|th)\\s*year\\b", in: line) { return digit }
            if let digit = firstCapture("\\byears?\\s*([12])\\b", in: line) { return digit }
        }
        return nil
    }

    /// A value that came from a column or field **labelled** "year": normalized
    /// to `"1"` / `"2"` when it can be, otherwise kept verbatim rather than lost.
    private nonisolated static func normalizedYear(_ raw: String) -> String? {
        let trimmed = collapse(raw)
        guard !trimmed.isEmpty else { return nil }
        if trimmed == "1" || trimmed == "2" { return trimmed }
        if trimmed.range(of: #"\bfirst\s+year\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return "1"
        }
        if trimmed.range(of: #"\bsecond\s+year\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return "2"
        }
        if let digit = firstCapture("\\b([12])\\s*(?:st|nd|rd|th)?\\s*year\\b", in: trimmed) { return digit }
        if let digit = firstCapture("\\byears?\\s*([12])\\b", in: trimmed) { return digit }
        if let digit = firstCapture("\\bib\\s*([12])\\b", in: trimmed) { return digit }
        return trimmed
    }

    private nonisolated static func firstUWCId(in source: String) -> String? {
        // One definition of the id shape lives in `W4Html`; do not fork it.
        firstCapture(W4Html.uwcIdPattern, in: source)?.lowercased()
    }

    // MARK: - DOM walking

    /// The nearest `li` / `tr` ancestor inside `root`, which is the row this
    /// anchor belongs to.
    private nonisolated static func container(of anchor: Element, upTo root: Element) -> Element? {
        var current: Element? = anchor.parent()
        while let element = current, element !== root {
            let tag = element.tagName().lowercased()
            if tag == "tr" || tag == "li" { return element }
            if tag == "body" || tag == "html" { return nil }
            current = element.parent()
        }
        return nil
    }

    /// Page chrome is not a directory. Home's `#birthdays` and `#hello` blocks
    /// live *inside* `#content_inner` (**[V]**, `Fixtures/W4/home.html:83,193,235`)
    /// and both carry `uwc_id` links, so a people list parser that swept them up
    /// would report four classmates as a directory page.
    private nonisolated static func isChrome(_ element: Element, upTo root: Element) -> Bool {
        var current: Element? = element
        while let node = current, node !== root {
            let id = attribute(node, "id").lowercased()
            if !id.isEmpty && chromeIDs.contains(id) { return true }
            if !classNames(of: node).isDisjoint(with: chromeClasses) { return true }
            let tag = node.tagName().lowercased()
            if tag == "body" || tag == "html" { return false }
            current = node.parent()
        }
        return false
    }

    private static let chromeIDs: Set<String> = [
        "hello", "hello-absences", "user-panel", "header", "footer", "breadcrumb",
        "birthdays", "birthdays-today", "birthdays-tomorrow", "birthdays-announcements",
        "announcements", "announcements-content", "links", "alerts", "version"
    ]

    private static let chromeClasses: Set<String> = [
        "sdmenu", "notifications", "status-dropdown", "help-icon"
    ]

    private nonisolated static func enclosingTable(of element: Element) -> Element? {
        var current: Element? = element.parent()
        while let node = current {
            let tag = node.tagName().lowercased()
            if tag == "table" { return node }
            if tag == "body" || tag == "html" { return nil }
            current = node.parent()
        }
        return nil
    }

    /// Free text inside `element`, split into lines on `<br>` and block
    /// boundaries, with every `skipped` element (the anchors) left out.
    ///
    /// `1<sup>st</sup> year` has to come back as `1st year`, so text is
    /// concatenated as written and only then collapsed — joining node texts with
    /// spaces would produce `1 st year`.
    private nonisolated static func textLines(
        of container: Element,
        skippingTag skipped: String
    ) -> [String] {
        var lines: [String] = []
        var current = ""

        func flush() {
            let line = Self.collapse(current)
            if !line.isEmpty { lines.append(line) }
            current = ""
        }

        func walk(_ node: Node) {
            if let textNode = node as? TextNode {
                current += textNode.getWholeText()
                return
            }
            guard let element = node as? Element else { return }
            let tag = element.tagName().lowercased()
            if tag == skipped { return }
            if tag == "br" {
                flush()
                return
            }
            if Self.blockTags.contains(tag) {
                flush()
                for child in element.getChildNodes() { walk(child) }
                flush()
                return
            }
            for child in element.getChildNodes() { walk(child) }
        }

        for child in container.getChildNodes() { walk(child) }
        flush()
        return lines
    }

    private static let blockTags: Set<String> = [
        "div", "p", "ul", "ol", "li", "table", "thead", "tbody", "tr", "td", "th",
        "h1", "h2", "h3", "h4", "h5", "h6", "section", "article", "dl", "dt", "dd"
    ]

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
        collapse((try? element.text()) ?? "")
    }

    private nonisolated static func attribute(_ element: Element, _ name: String) -> String {
        ((try? element.attr(name)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func classNames(of element: Element) -> Set<String> {
        let raw = ((try? element.attr("class")) ?? "").lowercased()
        return Set(raw.split(whereSeparator: { $0.isWhitespace }).map(String.init))
    }

    // MARK: - Text helpers (regex only ever runs on extracted text, never markup)

    private nonisolated static func collapse(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private nonisolated static func emptyToNil(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private nonisolated static func fileName(of path: String) -> String {
        let withoutQuery = path.split(separator: "?").first.map(String.init) ?? path
        return withoutQuery.split(separator: "/").last.map(String.init) ?? withoutQuery
    }

    /// Resolves an `href` / `src` into an absolute URL, or `nil` when it is not
    /// something we can honestly resolve.
    private nonisolated static func absoluteURL(fromHref raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        if trimmed.hasPrefix("/") || lower.hasPrefix("index.php") || trimmed.hasPrefix("?r=") {
            return W4Routes.resolve(trimmed)
        }
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        var relative = trimmed
        while relative.hasPrefix("./") { relative.removeFirst(2) }
        guard !relative.isEmpty,
              let encoded = relative.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "\(W4Routes.origin)/\(encoded)")
    }

    private nonisolated static func captures(
        _ pattern: String,
        in text: String,
        count: Int
    ) -> [String]? {
        guard !text.isEmpty, count > 0,
              let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > count else { return nil }

        var result: [String] = []
        for index in 1...count {
            guard let captured = Range(match.range(at: index), in: text) else { return nil }
            result.append(String(text[captured]))
        }
        return result
    }

    private nonisolated static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let value = captures(pattern, in: text, count: 1)?.first else { return nil }
        return emptyToNil(value)
    }
}
