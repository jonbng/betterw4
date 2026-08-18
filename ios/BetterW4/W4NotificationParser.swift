//
//  W4NotificationParser.swift
//  BetterW4
//
//  Parses `#header div.notifications` — from the chrome of any authenticated
//  page, and from the `notifications/refresh` AJAX fragment.
//
//  READ THIS BEFORE TRUSTING ANY ASSERTION IN THE TESTS.
//
//  The container is [V] and, in **both** real captures (`UWCRCN W4.html:37-38`
//  and the HAR `?r=documents` body), it is *empty*:
//
//  ```html
//  <div class="notifications">
//  </div>
//  ```
//
//  Zero notifications is the normal state at this school. Bug **B8**: the Kotlin
//  port only survives that page by luck (it falls through to `doc.body()` and
//  counts zero anchors). Here it is an explicit, tested branch that returns
//  ``W4NotificationSnapshot/empty``.
//
//  The populated markup has never been captured. It is reconstructed from the
//  real assets W4 serves — `notifications.js` and `notifications.css` — so the
//  class names are [V] but the shape they hang on is [I]:
//
//  ```html
//  <div class="notifications"><div class="btn-group">
//    <img class="notification-icon">
//    <div class="alert new">3</div>
//    <div class="dropdown-menu">
//      <h3 class="tasks">Tasks <a class="read">…</a></h3>
//      <dl>
//        <dt class="overdue">Assessments<a class="read" data-notification-type="…">read</a></dt>
//        <dd><ul><li class="overdue">
//          <a href="/index.php?r=…">Title <span class="deadline">…</span></a>
//          <a class="read" data-notification-id="12">read</a>
//        </li></ul></dd>
//      </dl>
//      <h3 class="emails">Emails</h3>
//      <dl class="email-list">…</dl>
//    </div>
//  </div></div>
//  ```
//
//  Refresh contract [V], `notifications.js:65`:
//  `$('#header div.notifications').html($(data).children())` — the payload is a
//  *wrapper whose children* are the new content, so this parser accepts a full
//  `div.notifications`, a bare `.btn-group`, or an anonymous wrapper.
//
//  Every node is optional. A shape we have not seen degrades to an empty
//  snapshot plus a logged warning; nothing here throws or force-unwraps.
//  Pure, synchronous and `nonisolated` (plan D-30).
//
//  Session death (403 + `Login Required`, or a 200 of login HTML) is the
//  transport layer's job, not this parser's — see reviewer-notes.md §3.
//

import Foundation
import SwiftSoup

enum W4NotificationParser {

    /// Poll this every 60 s while the sheet is closed (`notifications.js:51-57`).
    static let refreshRoute = W4Routes.R.notificationsRefresh

    // MARK: - Entry point

    /// Parses a full page or a `notifications/refresh` fragment.
    ///
    /// Always returns a snapshot: an empty bell and an unparseable bell both come
    /// back as ``W4NotificationSnapshot/empty``, the second with a logged warning.
    nonisolated static func parse(_ html: String) -> W4NotificationSnapshot {
        guard !html.isEmpty else { return .empty }
        do {
            return try parse(document: try SwiftSoup.parse(html))
        } catch {
            warn("could not parse the notification chrome: \(error)")
            return .empty
        }
    }

    private nonisolated static func parse(document: Document) throws -> W4NotificationSnapshot {
        guard let root = try resolveRoot(in: document) else { return .empty }

        // B8: an empty `div.notifications` is the normal state, not a failure.
        if try isEmptyContainer(root) { return .empty }

        let taskGroups = try parseTaskGroups(in: root)
        let emailGroups = try parseEmailGroups(in: root, excluding: taskGroups.consumed)

        let alert = try resolveBadge(in: root)
        let count = try resolveCount(in: root, badge: alert)
        let severity = resolveSeverity(
            badge: alert,
            groups: taskGroups.groups + emailGroups
        )

        return W4NotificationSnapshot(
            count: count,
            severity: severity,
            taskGroups: taskGroups.groups,
            emailGroups: emailGroups
        )
    }

    // MARK: - Root

    /// A full page gives `div.notifications`; the refresh payload may be a bare
    /// `.btn-group` inside an anonymous wrapper (`notifications.js:65`).
    private nonisolated static func resolveRoot(in document: Document) throws -> Element? {
        if let container = try document.select("div.notifications").first() {
            return container
        }
        if let group = try document.select(".btn-group").first(),
           let parent = group.parent() as? Element {
            return parent
        }
        return document.body()
    }

    private nonisolated static func isEmptyContainer(_ root: Element) throws -> Bool {
        let markers = try root.select(".btn-group, div.alert, .dropdown-menu, dl, [data-notification-id]")
        return markers.isEmpty()
    }

    // MARK: - Badge

    private nonisolated static func resolveBadge(in root: Element) throws -> Element? {
        if let scoped = try root.select(".btn-group div.alert").first() { return scoped }
        if let loose = try root.select("div.alert").first() { return loose }
        return try root.select(".alert").first()
    }

    private nonisolated static func resolveCount(in root: Element, badge: Element?) throws -> Int {
        if let badge {
            let text = trim(try badge.text())
            if let value = Int(text) { return value }
            if !text.isEmpty {
                // `9+` and similar are [U]; fall back to the honest parsed count.
                warn("badge text \"\(text)\" is not an integer; counting parsed items instead")
            }
        }

        var seen = Set<String>()
        for element in try root.select("[data-notification-id]").array() {
            let value = trim(try element.attr("data-notification-id"))
            if !value.isEmpty { seen.insert(value) }
        }
        return seen.count
    }

    private nonisolated static func resolveSeverity(
        badge: Element?,
        groups: [W4NotificationGroup]
    ) -> W4NotificationSeverity {
        if let fromBadge = severityClass(of: badge) { return fromBadge }
        var severities: [W4NotificationSeverity] = []
        for group in groups {
            severities.append(group.severity)
            severities.append(contentsOf: group.items.map(\.severity))
        }
        return mostSevere(severities) ?? .normal
    }

    // MARK: - Sections

    private nonisolated static func parseTaskGroups(
        in root: Element
    ) throws -> (groups: [W4NotificationGroup], consumed: [Element]) {
        if let list = try definitionList(after: "h3.tasks", in: root) {
            let groups = try parseGroups(in: list, section: .task)
            if !groups.isEmpty { return (groups, [list]) }
            return ([], [list])
        }

        // No `h3.tasks` heading: take the first definition list that is not the
        // email list, so an unheaded fragment still yields its rows.
        for list in try root.select("dl").array() where !list.hasClass("email-list") {
            let groups = try parseGroups(in: list, section: .task)
            if !groups.isEmpty { return (groups, [list]) }
        }
        return ([], [])
    }

    private nonisolated static func parseEmailGroups(
        in root: Element,
        excluding consumed: [Element]
    ) throws -> [W4NotificationGroup] {
        if let list = try definitionList(after: "h3.emails", in: root),
           !consumed.contains(where: { $0 === list }) {
            let groups = try parseGroups(in: list, section: .email)
            if !groups.isEmpty { return groups }
        }
        if let list = try root.select("dl.email-list").first(),
           !consumed.contains(where: { $0 === list }) {
            return try parseGroups(in: list, section: .email)
        }
        return []
    }

    /// The first `<dl>` after a heading, stopping at the next `<h3>` so the Tasks
    /// heading can never swallow the Emails list.
    private nonisolated static func definitionList(
        after headingSelector: String,
        in root: Element
    ) throws -> Element? {
        guard let heading = try root.select(headingSelector).first() else { return nil }
        var sibling = try heading.nextElementSibling()
        while let current = sibling {
            let tag = current.tagNameNormal()
            if tag == "dl" { return current }
            if tag == "h3" { return nil }
            sibling = try current.nextElementSibling()
        }
        return nil
    }

    // MARK: - Definition lists

    private nonisolated static func parseGroups(
        in list: Element,
        section: W4NotificationSection
    ) throws -> [W4NotificationGroup] {
        // Pair each <dt> with the <dd> rows that follow it.
        var blocks: [(heading: Element?, rows: [Element])] = []
        for child in list.children().array() {
            switch child.tagNameNormal() {
            case "dt":
                blocks.append((heading: child, rows: []))
            case "dd":
                let items = try child.select("li").array()
                let rows = items.isEmpty ? [child] : items
                if blocks.isEmpty {
                    blocks.append((heading: nil, rows: rows))
                } else {
                    blocks[blocks.count - 1].rows.append(contentsOf: rows)
                }
            default:
                continue
            }
        }

        var groups: [W4NotificationGroup] = []
        for block in blocks {
            let type = attribute(
                "data-notification-type",
                inFirstOf: [
                    "a.read[data-notification-type]",
                    "a.clear[data-notification-type]",
                    "[data-notification-type]"
                ],
                within: block.heading
            )

            var items: [W4Notification] = []
            for row in block.rows {
                if let item = try parseItem(row, section: section, groupType: type) {
                    items.append(item)
                }
            }

            guard !items.isEmpty else {
                if block.heading != nil {
                    warn("a \(section.rawValue) group carried no rows with a data-notification-id")
                }
                continue
            }

            let title = block.heading.map { headingText(of: $0) }.flatMap { $0.isEmpty ? nil : $0 }
                ?? defaultTitle(for: section)

            groups.append(
                W4NotificationGroup(
                    type: type,
                    title: title,
                    severity: severityClass(of: block.heading) ?? .normal,
                    items: items
                )
            )
        }
        return groups
    }

    // MARK: - Items

    private nonisolated static func parseItem(
        _ row: Element,
        section: W4NotificationSection,
        groupType: String?
    ) throws -> W4Notification? {
        let id = attribute(
            "data-notification-id",
            inFirstOf: [
                "a.read[data-notification-id]",
                "a.clear[data-notification-id]",
                "[data-notification-id]"
            ],
            within: row
        )
        guard let id else {
            // Without the server's id the row cannot be marked read or cleared,
            // and inventing one would post garbage back. Drop it, loudly.
            warn("dropped a \(section.rawValue) row with no data-notification-id")
            return nil
        }

        let anchors = try row.select("a[href]").array()
        let titleAnchor = anchors.first { !$0.hasClass("read") && !$0.hasClass("clear") }
            ?? anchors.first

        var title = ""
        if let titleAnchor {
            // `ownText()` keeps the row title and leaves `span.deadline` /
            // `span.duration` for the subtitle.
            title = collapseWhitespace(titleAnchor.ownText())
            if title.isEmpty { title = collapseWhitespace(try titleAnchor.text()) }
        }
        if title.isEmpty { title = headingText(of: row) }
        if title.isEmpty { title = id }

        let href = attribute("href", of: titleAnchor)
        let subtitleText = try firstText(
            in: row,
            selectors: ["span.deadline", "span.duration", ".deadline", ".duration"]
        )
        let subtitle = subtitleText.flatMap { $0 == title ? nil : $0 }

        let type = attribute(
            "data-notification-type",
            inFirstOf: [
                "a.read[data-notification-type]",
                "a.clear[data-notification-type]",
                "[data-notification-type]"
            ],
            within: row
        ) ?? groupType

        return W4Notification(
            id: id,
            title: title,
            subtitle: subtitle,
            route: href.flatMap { W4Routes.route(ofURLString: $0) },
            href: href,
            type: type,
            section: section,
            severity: severityClass(of: row) ?? .normal
        )
    }

    // MARK: - Text

    /// An element's own text plus the text of its children, minus the `read` /
    /// `clear` action anchors.
    ///
    /// parsers.md §3 warns against the Kotlin approach of regex-stripping the
    /// literal words `read` and `clear` out of the finished string — that eats
    /// any group genuinely called "Reading" or "Clearance".
    private nonisolated static func headingText(of element: Element) -> String {
        var parts: [String] = []
        for node in element.getChildNodes() {
            if let text = node as? TextNode {
                parts.append(text.getWholeText())
            } else if let child = node as? Element {
                if child.tagNameNormal() == "a",
                   child.hasClass("read") || child.hasClass("clear") {
                    continue
                }
                parts.append((try? child.text()) ?? "")
            }
        }
        return collapseWhitespace(parts.joined(separator: " "))
    }

    private nonisolated static func firstText(
        in element: Element,
        selectors: [String]
    ) throws -> String? {
        for selector in selectors {
            guard let found = try element.select(selector).first() else { continue }
            let text = collapseWhitespace(try found.text())
            if !text.isEmpty { return text }
        }
        return nil
    }

    private nonisolated static func defaultTitle(for section: W4NotificationSection) -> String {
        switch section {
        case .task: return "Tasks"
        case .email: return "Emails"
        }
    }

    // MARK: - Attributes

    private nonisolated static func attribute(_ name: String, of element: Element?) -> String? {
        guard let element, element.hasAttr(name) else { return nil }
        let value = trim((try? element.attr(name)) ?? "")
        return value.isEmpty ? nil : value
    }

    /// The attribute from the first matching descendant, falling back to the
    /// element itself.
    private nonisolated static func attribute(
        _ name: String,
        inFirstOf selectors: [String],
        within element: Element?
    ) -> String? {
        guard let element else { return nil }
        for selector in selectors {
            if let found = try? element.select(selector).first(),
               let value = attribute(name, of: found) {
                return value
            }
        }
        return attribute(name, of: element)
    }

    // MARK: - Severity

    private nonisolated static func severityClass(of element: Element?) -> W4NotificationSeverity? {
        guard let element else { return nil }
        if element.hasClass("overdue") { return .overdue }
        if element.hasClass("new") { return .new }
        if element.hasClass("normal") { return .normal }
        return nil
    }

    private nonisolated static func mostSevere(
        _ severities: [W4NotificationSeverity]
    ) -> W4NotificationSeverity? {
        if severities.contains(.overdue) { return .overdue }
        if severities.contains(.new) { return .new }
        return severities.isEmpty ? nil : .normal
    }

    // MARK: - Helpers

    private nonisolated static func trim(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func collapseWhitespace(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private nonisolated static func warn(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("⚠️ W4NotificationParser: \(message())")
        #endif
    }
}
