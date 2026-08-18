//
//  W4TripsParser.swift
//  BetterW4
//
//  W4's boarding-travel surfaces — the one family of pages Lectio had no
//  equivalent for, because UWC RCN is a boarding college:
//
//    * `academics/trips`               → `TripList`      (My trips)
//    * `academics/travel/travel.list`  → `TravelPage`    (My travel forms)
//    * the "Manage my travel contacts" page → `[TravelContact]`
//
//  Spec: docs/spec/parsers.md §14, docs/spec/features.md §1.9,
//  W4_PORT_PLAN.md Wave 4 item 4.10.
//
//  EVIDENCE — read this before changing a selector.
//
//  VERIFIED [V]: only the routes. `Fixtures/W4/academics-menu.html` (real
//  capture) renders a "Trips" group in the Academics side menu linking
//  `index.php?r=academics/trips` ("My trips") and
//  `index.php?r=academics/travel/travel.list` ("My travel forms"); the real
//  Home capture links `academics/trips` as "Trip Form". That is the entire
//  captured evidence base for this file.
//
//  UNKNOWN [U]: **the trip grid itself has never been captured.** Not one row,
//  not one header, not one column label. README §6 describes the columns
//  (Trip name | Outgoing date/time | Return date/time | Destination | Type |
//  Participants | Status), the "Plan new trip" button and the status ladder
//  (Planning → Pending confirmation → Approved | Cancelled) *in prose*, from a
//  live GET nobody saved. The travel-forms page and the travel-contacts page
//  have never been captured either.
//
//  Therefore everything below degrades: unparseable HTML, a missing grid, a
//  missing header, an unknown status and an empty-state row each produce an
//  empty (or partial) model plus a logged warning. Nothing throws, nothing
//  force-unwraps.
//
//  COLUMNS ARE HEADER-DRIVEN. `W4TripsParser.kt:17-31` reads `#content_inner
//  table` cells **positionally**, so one new W4 column silently shifts `status`
//  into `participants`. This parser matches on header *text* instead; the
//  documented [I] positional order is used only when a grid has no header row
//  at all, and never silently — the warning is the signal.
//
//  The raw string W4 printed is always kept next to the parsed value, so an
//  unrecognised status is still displayable (`statusLabel`).
//
//  Pure, `nonisolated`, synchronous: `(String) -> Model`. No network, no
//  storage, no clock, no singletons. Every date goes through `W4Dates`
//  (Europe/Oslo), never `TimeZone.current`.
//

import Foundation
import SwiftSoup

enum W4TripsParser {

    // MARK: - academics/trips  [U — never captured]

    /// Parses one page of `academics/trips`.
    ///
    /// Degrades to an empty `TripList` plus a warning for every failure mode.
    nonisolated static func parse(_ html: String) -> TripList {
        guard let document = try? SwiftSoup.parse(html) else {
            warn("trips: the HTML did not parse")
            return .empty
        }

        let scope = contentInner(of: document) ?? document
        let title = heading(in: scope)
        let action = planNewTrip(in: scope)

        guard let table = gridTable(in: scope) else {
            let note = pageNote(in: scope)
            let suffix = note == nil ? "" : " (the page says: " + (note ?? "") + ")"
            warn("trips: no grid table found" + suffix)
            return TripList(
                title: title,
                trips: [],
                hasMorePages: false,
                emptyMessage: note,
                canPlanNewTrip: action.canPlan,
                planNewTripHref: action.href,
                isHeaderDriven: false
            )
        }

        let header = headerRow(of: table)
        var columns = header.map { columnMap(fromHeader: cellElements(of: $0)) } ?? Columns()
        if columns.isEmpty {
            // Documented [I] fallback: Trip name | Outgoing | Return |
            // Destination | Type | Participants | Status (parsers.md §14).
            // Never silently — this log line is how we find out that the
            // capture we are waiting for does not look like this.
            warn("trips: no usable header row; falling back to the inferred column order")
            columns = .inferred
        }

        var trips: [Trip] = []
        var occurrences: [String: Int] = [:]
        var emptyMessage: String?

        for row in bodyRows(of: table, header: header) {
            let cells = cellElements(of: row)
            if let message = emptyRowMessage(row: row, cells: cells) {
                if emptyMessage == nil { emptyMessage = message }
                continue
            }
            guard let parsed = trip(
                row: row,
                cells: cells,
                columns: columns,
                occurrences: &occurrences
            ) else { continue }
            trips.append(parsed)
        }

        if trips.isEmpty && emptyMessage == nil {
            emptyMessage = pageNote(in: scope)
        }

        return TripList(
            title: title,
            trips: trips,
            hasMorePages: hasMorePages(in: scope),
            emptyMessage: emptyMessage,
            canPlanNewTrip: action.canPlan,
            planNewTripHref: action.href,
            isHeaderDriven: columns.isHeaderDriven
        )
    }

    /// Convenience for callers that only want the rows, matching the shape
    /// `parsers.md` §14 sketches (`parse(_:) -> [Trip]`).
    nonisolated static func parseTrips(_ html: String) -> [Trip] {
        parse(html).trips
    }

    // MARK: - Rows

    private static func trip(
        row: Element,
        cells: [Element],
        columns: Columns,
        occurrences: inout [String: Int]
    ) -> Trip? {
        let values = cells.map { text(of: $0) }

        func value(_ index: Int?) -> String? {
            guard let index, index >= 0, index < values.count else { return nil }
            return blankToNil(values[index])
        }

        let link = rowLink(in: row)
        let href = link.flatMap { blankToNil(attribute($0, "href")) }
        let route = href.flatMap { W4Routes.route(ofURLString: $0) }

        // The name column, then the row's own link text, then the first cell.
        let linkText = link.flatMap { blankToNil(text(of: $0)) }
        let name = value(columns.name) ?? linkText ?? values.first.flatMap(blankToNil) ?? ""

        let outgoingLabel = value(columns.outgoing)
        let returningLabel = value(columns.returning)
        let destination = value(columns.destination)
        let type = value(columns.type)
        let participantsLabel = value(columns.participants)
        let statusLabel = value(columns.status) ?? ""

        // A row carrying nothing we could show is grid furniture, not a trip.
        if name.isEmpty, outgoingLabel == nil, returningLabel == nil,
           destination == nil, participantsLabel == nil, statusLabel.isEmpty {
            return nil
        }

        // Bug B18: the id comes from the row link's `?id=`, never from `tr[id]`
        // (Yii does not emit one) and never from a hash of the name alone.
        let base: String
        if let numeric = href.flatMap({ firstGroup(in: $0, pattern: #"[?&]id=(\d+)"#) }) {
            base = "trip-\(numeric)"
        } else {
            base = Trip.identity(
                name: name,
                outgoingLabel: outgoingLabel,
                destination: destination
            )
        }
        let seen = occurrences[base] ?? 0
        occurrences[base] = seen + 1
        let id = seen == 0 ? base : "\(base)-\(seen)"

        return Trip(
            id: id,
            name: name,
            outgoing: parseDateTime(outgoingLabel),
            outgoingLabel: outgoingLabel,
            returning: parseDateTime(returningLabel),
            returningLabel: returningLabel,
            destination: destination,
            type: type,
            participants: participantCount(participantsLabel),
            participantsLabel: participantsLabel,
            status: TripStatus(label: statusLabel),
            statusLabel: statusLabel,
            href: href,
            route: route
        )
    }

    /// Column indexes, matched on header *text* so a new or re-ordered column
    /// can never shift a value into the wrong field.
    private struct Columns {
        var name: Int?
        var outgoing: Int?
        var returning: Int?
        var destination: Int?
        var type: Int?
        var participants: Int?
        var status: Int?
        var isHeaderDriven: Bool = true

        var isEmpty: Bool {
            name == nil && outgoing == nil && returning == nil && destination == nil
                && type == nil && participants == nil && status == nil
        }

        /// The **[I]** column order README §6 describes. Used only when the grid
        /// has no header row at all.
        static let inferred = Columns(
            name: 0,
            outgoing: 1,
            returning: 2,
            destination: 3,
            type: 4,
            participants: 5,
            status: 6,
            isHeaderDriven: false
        )
    }

    /// Matched most specific first. `name` is matched **last** and on the word
    /// "name" before the word "trip", so a "Trip type" column cannot swallow
    /// the name slot when the grid is re-ordered.
    private static func columnMap(fromHeader cells: [Element]) -> Columns {
        var columns = Columns()
        for (index, cell) in cells.enumerated() {
            let label = text(of: cell).lowercased()
            guard !label.isEmpty else { continue }

            if columns.status == nil, contains(label, ["status", "approval", "state"]) {
                columns.status = index
            } else if columns.participants == nil,
                      contains(label, ["participant", "attendee", "student", "people", "member"]) {
                columns.participants = index
            } else if columns.destination == nil,
                      contains(label, ["destination", "location", "place", "venue", "where"]) {
                columns.destination = index
            } else if columns.type == nil, contains(label, ["type", "category", "kind"]) {
                columns.type = index
            } else if columns.outgoing == nil,
                      contains(label, ["outgoing", "depart", "leav", "start"]) {
                columns.outgoing = index
            } else if columns.returning == nil,
                      contains(label, ["return", "back", "arriv", "coming"]) {
                columns.returning = index
            } else if columns.name == nil,
                      contains(label, ["name", "title", "description", "trip"]) {
                columns.name = index
            }
        }
        return columns
    }

    /// The link a row hangs its identity on: the first usable anchor, preferring
    /// one that carries a numeric `id=`.
    private static func rowLink(in row: Element) -> Element? {
        let links = select(row, "a[href]").filter { link in
            let href = attribute(link, "href").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !href.isEmpty, href != "#" else { return false }
            return !href.lowercased().hasPrefix("javascript:")
        }
        let withID = links.first { link in
            firstGroup(in: attribute(link, "href"), pattern: #"[?&]id=(\d+)"#) != nil
        }
        return withID ?? links.first
    }

    /// "Plan new trip" — an anchor on some Yii pages, an
    /// `<input type="button">` with an onclick on others. v1 is read-only: the
    /// UI hands `href` to the in-app `WKWebView` (D-24) and never POSTs.
    private static func planNewTrip(in scope: Element) -> (canPlan: Bool, href: String?) {
        for element in select(scope, "a[href], button, input") {
            if element.tagName().lowercased() == "input" {
                let type = attribute(element, "type").lowercased()
                guard type == "button" || type == "submit" || type.isEmpty else { continue }
            }
            let label = [
                text(of: element),
                attribute(element, "value"),
                attribute(element, "title")
            ].joined(separator: " ").lowercased()

            guard label.contains("new trip") || label.contains("plan a trip") else { continue }

            var href = blankToNil(attribute(element, "href"))
            if href == "#" || href?.lowercased().hasPrefix("javascript:") == true { href = nil }
            return (true, href)
        }
        return (false, nil)
    }

    // MARK: - academics/travel/travel.list  [U — never captured]

    /// Parses the travel-forms page: the four fixed journeys plus the
    /// "Manage my travel contacts" link.
    ///
    /// Two ladders, in order: a Yii grid if the page renders one, otherwise the
    /// anchors inside `#content_inner`. Both degrade to an empty page.
    nonisolated static func parseTravel(_ html: String) -> TravelPage {
        guard let document = try? SwiftSoup.parse(html) else {
            warn("travel: the HTML did not parse")
            return .empty
        }

        let scope = contentInner(of: document) ?? document
        let title = heading(in: scope)
        let contacts = manageContactsLink(in: scope)

        var forms = travelFormsFromGrid(in: scope, excluding: contacts?.href)
        if forms.isEmpty {
            forms = travelFormsFromLinks(in: scope, excluding: contacts?.href)
        }

        if forms.isEmpty {
            warn("travel: no travel forms found — neither a grid nor a usable link ladder")
        }

        return TravelPage(
            title: title,
            forms: forms,
            manageContactsHref: contacts?.href,
            manageContactsRoute: contacts?.route,
            manageContactsLabel: contacts?.label,
            emptyMessage: forms.isEmpty ? pageNote(in: scope) : nil
        )
    }

    private static func travelFormsFromGrid(
        in scope: Element,
        excluding contactsHref: String?
    ) -> [TravelForm] {
        guard let table = gridTable(in: scope) else { return [] }

        let header = headerRow(of: table)
        let columns = header.map { travelColumnMap(fromHeader: cellElements(of: $0)) }
            ?? TravelColumns()

        var forms: [TravelForm] = []
        var occurrences: [String: Int] = [:]

        for row in bodyRows(of: table, header: header) {
            let cells = cellElements(of: row)
            if emptyRowMessage(row: row, cells: cells) != nil { continue }

            let values = cells.map { text(of: $0) }
            func value(_ index: Int?) -> String? {
                guard let index, index >= 0, index < values.count else { return nil }
                return blankToNil(values[index])
            }

            let link = rowLink(in: row)
            let href = link.flatMap { blankToNil(attribute($0, "href")) }
            if let href, let contactsHref, href == contactsHref { continue }

            let linkText = link.flatMap { blankToNil(text(of: $0)) }
            let formTitle = value(columns.title) ?? linkText ?? values.first.flatMap(blankToNil) ?? ""
            guard !formTitle.isEmpty else { continue }

            forms.append(
                travelForm(
                    title: formTitle,
                    statusLabel: value(columns.status),
                    href: href,
                    occurrences: &occurrences
                )
            )
        }

        return forms
    }

    private static func travelFormsFromLinks(
        in scope: Element,
        excluding contactsHref: String?
    ) -> [TravelForm] {
        let anchors = usableAnchors(in: scope)

        // Prefer anchors that actually live under `academics/travel`; only if
        // there are none do we fall back to "anything that reads like one of
        // the four journeys", which keeps unrelated page links out.
        let onTravelRoute = anchors.filter { anchor in
            guard let route = W4Routes.route(ofURLString: attribute(anchor, "href")) else {
                return false
            }
            return route.lowercased().hasPrefix("academics/travel")
        }
        let candidates = onTravelRoute.isEmpty
            ? anchors.filter { TravelJourney.classify(text(of: $0)) != nil }
            : onTravelRoute

        var forms: [TravelForm] = []
        var occurrences: [String: Int] = [:]
        var seen = Set<String>()

        for anchor in candidates {
            let href = blankToNil(attribute(anchor, "href"))
            if let href, let contactsHref, href == contactsHref { continue }

            let formTitle = blankToNil(text(of: anchor)) ?? ""
            guard !formTitle.isEmpty else { continue }

            let journey = TravelJourney.classify(formTitle)
            // The page's own self-link ("My travel forms") is not a form.
            if journey == nil,
               let route = W4Routes.route(ofURLString: attribute(anchor, "href"))?.lowercased(),
               route == W4Routes.R.travel.lowercased() {
                continue
            }

            let key = "\(href ?? "")|\(formTitle.lowercased())"
            guard seen.insert(key).inserted else { continue }

            forms.append(
                travelForm(
                    title: formTitle,
                    statusLabel: nil,
                    href: href,
                    occurrences: &occurrences
                )
            )
        }

        return forms
    }

    private static func travelForm(
        title: String,
        statusLabel: String?,
        href: String?,
        occurrences: inout [String: Int]
    ) -> TravelForm {
        let journey = TravelJourney.classify(title)
        let base: String
        if let numeric = href.flatMap({ firstGroup(in: $0, pattern: #"[?&]id=(\d+)"#) }) {
            base = "travel-\(numeric)"
        } else if let journey {
            base = "travel-\(journey.rawValue)"
        } else {
            base = "travel-\(Trip.fnv1aHex(title.lowercased()))"
        }
        let seen = occurrences[base] ?? 0
        occurrences[base] = seen + 1
        let id = seen == 0 ? base : "\(base)-\(seen)"

        return TravelForm(
            id: id,
            journey: journey,
            title: title,
            statusLabel: statusLabel,
            href: href,
            route: href.flatMap { W4Routes.route(ofURLString: $0) }
        )
    }

    private struct TravelColumns {
        var title: Int?
        var status: Int?
    }

    private static func travelColumnMap(fromHeader cells: [Element]) -> TravelColumns {
        var columns = TravelColumns()
        for (index, cell) in cells.enumerated() {
            let label = text(of: cell).lowercased()
            guard !label.isEmpty else { continue }

            if columns.status == nil, contains(label, ["status", "state", "submitted"]) {
                columns.status = index
            } else if columns.title == nil,
                      contains(label, ["journey", "form", "travel", "name", "title", "description"]) {
                columns.title = index
            }
        }
        return columns
    }

    /// The "Manage my travel contacts" link. Matched on its own text, because
    /// its route has never been captured.
    private static func manageContactsLink(
        in scope: Element
    ) -> (href: String, route: String?, label: String)? {
        for anchor in usableAnchors(in: scope) {
            let label = text(of: anchor)
            let normalized = label.lowercased()
            guard normalized.contains("contact") else { continue }
            guard let href = blankToNil(attribute(anchor, "href")) else { continue }
            return (href, W4Routes.route(ofURLString: href), label)
        }
        return nil
    }

    // MARK: - Travel contacts  [U — never captured]

    /// Parses the "Manage my travel contacts" page.
    ///
    /// Header-driven like every other grid here; falls back to `mailto:` and
    /// `tel:` anchors inside the row for the phone and email columns.
    nonisolated static func parseTravelContacts(_ html: String) -> [TravelContact] {
        guard let document = try? SwiftSoup.parse(html) else {
            warn("travel contacts: the HTML did not parse")
            return []
        }

        let scope = contentInner(of: document) ?? document
        guard let table = gridTable(in: scope) else {
            warn("travel contacts: no grid table found")
            return []
        }

        let header = headerRow(of: table)
        let columns = header.map { contactColumnMap(fromHeader: cellElements(of: $0)) }
            ?? ContactColumns()

        var contacts: [TravelContact] = []
        var occurrences: [String: Int] = [:]

        for row in bodyRows(of: table, header: header) {
            let cells = cellElements(of: row)
            if emptyRowMessage(row: row, cells: cells) != nil { continue }

            let values = cells.map { text(of: $0) }
            func value(_ index: Int?) -> String? {
                guard let index, index >= 0, index < values.count else { return nil }
                return blankToNil(values[index])
            }

            let name = value(columns.name) ?? values.first.flatMap(blankToNil) ?? ""
            let email = value(columns.email) ?? schemeLink(in: row, scheme: "mailto:")
            let phone = value(columns.phone) ?? schemeLink(in: row, scheme: "tel:")
            let relation = value(columns.relation)

            guard !name.isEmpty || email != nil || phone != nil else { continue }

            let base = "contact-\(Trip.fnv1aHex([name, relation ?? "", phone ?? "", email ?? ""].joined(separator: "|")))"
            let seen = occurrences[base] ?? 0
            occurrences[base] = seen + 1

            contacts.append(
                TravelContact(
                    id: seen == 0 ? base : "\(base)-\(seen)",
                    name: name,
                    relation: relation,
                    phone: phone,
                    email: email
                )
            )
        }

        return contacts
    }

    private struct ContactColumns {
        var name: Int?
        var relation: Int?
        var phone: Int?
        var email: Int?
    }

    private static func contactColumnMap(fromHeader cells: [Element]) -> ContactColumns {
        var columns = ContactColumns()
        for (index, cell) in cells.enumerated() {
            let label = text(of: cell).lowercased()
            guard !label.isEmpty else { continue }

            if columns.email == nil, contains(label, ["email", "e-mail", "mail"]) {
                columns.email = index
            } else if columns.phone == nil,
                      contains(label, ["phone", "mobile", "tel", "number"]) {
                columns.phone = index
            } else if columns.relation == nil,
                      contains(label, ["relation", "role", "type", "kind"]) {
                columns.relation = index
            } else if columns.name == nil, contains(label, ["name", "contact"]) {
                columns.name = index
            }
        }
        return columns
    }

    /// The first `mailto:` / `tel:` target in a row, with the scheme stripped.
    private static func schemeLink(in row: Element, scheme: String) -> String? {
        for anchor in select(row, "a[href]") {
            let href = attribute(anchor, "href").trimmingCharacters(in: .whitespacesAndNewlines)
            guard href.lowercased().hasPrefix(scheme) else { continue }
            let value = String(href.dropFirst(scheme.count))
            return blankToNil(value.removingPercentEncoding ?? value)
        }
        return nil
    }

    // MARK: - Grid structure (parsers.md §0.4)

    /// Selector ladder for a Yii grid. The first table that has at least one
    /// data row wins; failing that, the first table that matched at all.
    private static let tableSelectors = [
        "div.grid-view table.items",
        "table.items",
        "table.grid-view",
        "table"
    ]

    private static func gridTable(in scope: Element) -> Element? {
        var firstMatch: Element?
        for selector in tableSelectors {
            let tables = select(scope, selector)
            if firstMatch == nil { firstMatch = tables.first }
            if let withRows = tables.first(where: { hasDataRows($0) }) { return withRows }
        }
        return firstMatch
    }

    private static func hasDataRows(_ table: Element) -> Bool {
        select(table, "tr").contains { !select($0, "td").isEmpty }
    }

    private static func headerRow(of table: Element) -> Element? {
        if let row = select(table, "thead tr").first, !cellElements(of: row).isEmpty {
            return row
        }
        // No <thead>: the first row made only of <th> cells is the header.
        for row in select(table, "tr") where !select(row, "th").isEmpty && select(row, "td").isEmpty {
            return row
        }
        return nil
    }

    private static func bodyRows(of table: Element, header: Element?) -> [Element] {
        var rows = select(table, "tbody > tr")
        if rows.isEmpty { rows = select(table, "tr") }
        return rows.filter { row in
            if let header, row === header { return false }
            return !select(row, "td").isEmpty
        }
    }

    private static func cellElements(of row: Element) -> [Element] {
        row.children().array().filter { element in
            let tag = element.tagName().lowercased()
            return tag == "td" || tag == "th"
        }
    }

    /// Bug B9: Yii 1 empty states are `td.empty`, `span.empty` **and** the bare
    /// sentence "No results found."; only checking `td.empty` misses two of them.
    private static func emptyRowMessage(row: Element, cells: [Element]) -> String? {
        if let marker = select(row, "td.empty, span.empty").first {
            let message = text(of: marker)
            return message.isEmpty ? "No results found." : message
        }
        guard cells.count <= 2 else { return nil }
        let joined = cells.map { text(of: $0) }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = joined.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        guard normalized.hasPrefix("no "), normalized.hasSuffix("found") else { return nil }
        return joined
    }

    /// The non-grid empty state: `#content_inner > div.note` ("No users found"
    /// is the **[V]** example, from `Current applicants at UWCRCN.html`).
    private static func pageNote(in scope: Element) -> String? {
        let direct = scope.children().array().first { element in
            element.tagName().lowercased() == "div" && element.hasClass("note")
        }
        if let direct { return blankToNil(text(of: direct)) }
        guard let anywhere = select(scope, "div.note").first else { return nil }
        return blankToNil(text(of: anywhere))
    }

    /// Bug B10: nobody paginates. Detect the pager (or a summary that says there
    /// is more) so the UI can say "more on W4" instead of silently truncating.
    private static func hasMorePages(in scope: Element) -> Bool {
        let links = select(scope, "div.pager a[href], ul.yiiPager a[href]").filter { link in
            let href = attribute(link, "href").trimmingCharacters(in: .whitespacesAndNewlines)
            return !href.isEmpty && href != "#"
        }
        if !links.isEmpty { return true }

        if let summary = select(scope, "div.summary").first,
           let groups = matchGroups(#"(\d+)\s*-\s*(\d+)\s+of\s+(\d+)"#, in: text(of: summary)),
           groups.count >= 3,
           let shownEnd = Int(groups[1]),
           let total = Int(groups[2]) {
            return shownEnd < total
        }
        return false
    }

    // MARK: - Dates and counts

    /// Every date is Oslo wall clock (D-11 / parsers.md §0.1). `W4Dates` is the
    /// single shared parser — this file must never build a `DateFormatter`.
    private static func parseDateTime(_ raw: String?) -> Date? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        if let date = W4Dates.parseDateTime(trimmed) { return date }
        // A cell may carry more than the timestamp ("Sun 20-Sep-2026 08:00").
        // Regex over extracted text, never over markup.
        if let token = firstGroup(
            in: trimmed,
            pattern: #"(\d{1,2}-[A-Za-z]{3,9}-\d{2,4}(?:\s+\d{1,2}:\d{2})?)"#
        ), let date = W4Dates.parseDateTime(token) {
            return date
        }
        return W4Dates.firstDate(in: trimmed)
    }

    /// `parsers.md` §14: the participants cell may be a **name list** rather
    /// than a count, so a number is only reported when the cell is nothing but
    /// digits. The raw string is kept either way.
    private static func participantCount(_ raw: String?) -> Int? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed.allSatisfy({ $0.isNumber }) else { return nil }
        return Int(trimmed)
    }

    // MARK: - Small helpers

    private static func contentInner(of document: Document) -> Element? {
        select(document, "#content_inner").first
    }

    private static func heading(in scope: Element) -> String? {
        for selector in ["h2", "h1", "h3"] {
            if let element = select(scope, selector).first, let value = blankToNil(text(of: element)) {
                return value
            }
        }
        return nil
    }

    private static func usableAnchors(in scope: Element) -> [Element] {
        select(scope, "a[href]").filter { anchor in
            let href = attribute(anchor, "href").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !href.isEmpty, href != "#" else { return false }
            return !href.lowercased().hasPrefix("javascript:")
        }
    }

    private static func select(_ element: Element, _ query: String) -> [Element] {
        ((try? element.select(query)) ?? Elements()).array()
    }

    private static func text(of element: Element) -> String {
        ((try? element.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func attribute(_ element: Element, _ name: String) -> String {
        (try? element.attr(name)) ?? ""
    }

    private static func blankToNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func contains(_ haystack: String, _ needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }

    private static func matchGroups(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1 else { return nil }
        var groups: [String] = []
        for index in 1..<match.numberOfRanges {
            guard let groupRange = Range(match.range(at: index), in: text) else { return nil }
            groups.append(String(text[groupRange]))
        }
        return groups
    }

    private static func firstGroup(in text: String, pattern: String) -> String? {
        matchGroups(pattern, in: text)?.first
    }

    private static func warn(_ message: String) {
        print("⚠️ [W4TripsParser] \(message)")
    }
}
