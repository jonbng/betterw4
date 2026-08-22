//
//  W4TeacherParser.swift
//  BetterW4
//
//  `people/students/staff` — My teachers and group leaders.
//
//  Live capture 21 Aug 2026. `#content_inner` holds a type filter and a
//  `ul.user-list` of `<li>`s: photo anchor, name anchor, then a role caption
//  (`Core meetings`, `Advisor group`, `English Language & Literature SL`).
//
//  Staff ids come from `uwc_id=` and are not always `nc…` (a live row is
//  `wk11lbon`). Trailing HL/SL is split off the caption into `ClassLevel`.
//
//  Purity: `nonisolated`, synchronous, `(String) -> Model`. No network.
//  PII: names and UWC ids are never logged.
//

import Foundation
import SwiftSoup

enum W4TeacherParser {

    /// Teachers on the page, in document order.
    nonisolated static func parse(_ html: String) -> [MyTeacher] {
        guard let document = try? SwiftSoup.parse(html, W4Routes.origin) else { return [] }
        let root = contentRoot(of: document)
        let list = firstElement(root, "ul.user-list") ?? root
        var order: [String] = []
        var byId: [String: MyTeacher] = [:]

        let items = elements(list, "> li")
        let rows = items.isEmpty ? elements(root, "ul.user-list > li") : items
        for item in rows {
            guard let teacher = parseRow(item) else { continue }
            if byId[teacher.id] == nil {
                byId[teacher.id] = teacher
                order.append(teacher.id)
            }
        }

        if order.isEmpty {
            for anchor in elements(root, "a[href*=uwc_id]") {
                guard let owner = container(of: anchor, upTo: root) else { continue }
                guard let teacher = parseRow(owner) else { continue }
                if byId[teacher.id] == nil {
                    byId[teacher.id] = teacher
                    order.append(teacher.id)
                }
            }
        }

        return order.compactMap { byId[$0] }
    }

    /// The `uwc_id` query value, lowercased. Unlike `W4PeopleParser.uwcId(fromHref:)`,
    /// this does not require the student-shaped `nc\d{2}[a-z]+` pattern.
    nonisolated static func staffId(fromHref href: String) -> String? {
        guard !href.isEmpty else { return nil }
        let decoded = href.removingPercentEncoding ?? href
        guard let raw = firstCapture(#"(?:^|[?&])uwc_id=([^&#]+)"#, in: decoded) else {
            return nil
        }
        let id = (raw.removingPercentEncoding ?? raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return id.isEmpty ? nil : id
    }

    /// Split a trailing IB level off a role caption (`… HL` / `… SL` / `… HL/SL`).
    nonisolated static func parseRole(_ raw: String?) -> (role: String?, level: ClassLevel) {
        let text = collapse((raw ?? "").replacingOccurrences(of: "\u{00a0}", with: " "))
        guard !text.isEmpty else { return (nil, .unknown) }
        let parts = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let last = parts.last else { return (text, .unknown) }
        let level = levelFromToken(last)
        if level == .unknown { return (text, .unknown) }
        let role = parts.dropLast().joined(separator: " ").nilIfEmpty
        return (role, level)
    }

    // MARK: - Row

    private nonisolated static func parseRow(_ item: Element) -> MyTeacher? {
        let links = elements(item, "a[href*=uwc_id]")
        guard !links.isEmpty else { return nil }
        let named = links.first { firstElement($0, "img") == nil } ?? links.first
        guard let named else { return nil }
        let href = absHref(named)
        guard let id = staffId(fromHref: href) else { return nil }

        var name = (ownText(of: named).nilIfEmpty ?? text(of: named))
            .replacingOccurrences(
                of: #"Photo of\s+"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name.caseInsensitiveCompare(id) == .orderedSame {
            name = id
        }

        let img = firstElement(item, "img.photo") ?? firstElement(item, "img")
        let photo = img.flatMap {
            W4PeopleParser.photoURL(fromSource: attribute($0, "src"), uwcId: id)
        }

        let caption = roleCaption(of: item, name: name, id: id)
        let parsed = parseRole(caption)
        return MyTeacher(
            id: id,
            name: name,
            role: parsed.role,
            level: parsed.level,
            photoURL: photo
        )
    }

    private nonisolated static func roleCaption(of item: Element, name: String, id: String) -> String? {
        var rest = text(of: item)
        for needle in [name, "Photo of \(id)", "Photo of \(id.uppercased())", id] {
            if let range = rest.range(of: needle, options: .caseInsensitive) {
                rest.removeSubrange(range)
            }
        }
        return collapse(rest).nilIfEmpty
    }

    private nonisolated static func levelFromToken(_ raw: String) -> ClassLevel {
        let compact = raw.lowercased().filter { $0.isLetter || $0 == "/" }
        if compact == "hl/sl" || compact == "hlsl" { return .combined }
        if compact == "hl" || compact.hasPrefix("higher") { return .higher }
        if compact == "sl" || compact.hasPrefix("standard") { return .standard }
        if compact.hasPrefix("combined") { return .combined }
        return .unknown
    }

    // MARK: - DOM

    private nonisolated static func contentRoot(of document: Document) -> Element {
        if let inner = firstElement(document, "#content_inner") { return inner }
        if let main = firstElement(document, "#content_main") { return main }
        if let body = document.body() { return body }
        return document
    }

    private nonisolated static func firstElement(_ root: Element, _ query: String) -> Element? {
        guard let found = try? root.select(query) else { return nil }
        return found.first()
    }

    private nonisolated static func elements(_ root: Element, _ query: String) -> [Element] {
        guard let found = try? root.select(query) else { return [] }
        return found.array()
    }

    private nonisolated static func container(of anchor: Element, upTo root: Element) -> Element? {
        var current: Element? = anchor.parent()
        while let element = current, element !== root {
            if element.tagName().lowercased() == "li" { return element }
            if element.tagName().lowercased() == "body" { return nil }
            current = element.parent()
        }
        return nil
    }

    private nonisolated static func text(of element: Element) -> String {
        collapse((try? element.text()) ?? "")
    }

    private nonisolated static func ownText(of element: Element) -> String {
        collapse((try? element.ownText()) ?? "")
    }

    private nonisolated static func attribute(_ element: Element, _ name: String) -> String {
        ((try? element.attr(name)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func absHref(_ element: Element) -> String {
        let abs = ((try? element.absUrl("href")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !abs.isEmpty { return abs }
        return attribute(element, "href")
    }

    private nonisolated static func collapse(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private nonisolated static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard !text.isEmpty,
              let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[captured]).nilIfEmpty
    }
}
