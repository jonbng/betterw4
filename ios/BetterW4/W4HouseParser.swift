//
//  W4HouseParser.swift
//  BetterW4
//
//  Parses `people/students/byhouse` and `people/students/byhouse/index&house_id=`.
//
//  Captured 19 Aug 2026. A house page is a `ul.menu-list` of house links, then
//  `h3` House leader / `Room NNN` / `Students with no room`, each followed by a
//  `ul.user-list` of photo + name + country + year + campus-status.
//
//  Purity: `nonisolated`, synchronous, `(String) -> Model`. No network.
//  PII: names and UWC ids are never logged.
//

import Foundation
import OSLog
import SwiftSoup

enum W4HouseParser {

    private static let log = Logger(
        subsystem: "dk.jonathanb.w4",
        category: "W4HouseParser"
    )

    // MARK: - Index

    /// House links from the by-house landing page (or the menu on a house page).
    nonisolated static func parseIndex(_ html: String) -> [House] {
        guard let document = try? SwiftSoup.parse(html) else { return [] }
        return parseIndex(document: document)
    }

    nonisolated static func parseIndex(document: Document) -> [House] {
        let root = contentRoot(of: document)
        var order: [String] = []
        var byId: [String: House] = [:]

        for anchor in elements(root, "a[href*=house_id]") {
            let href = attribute(anchor, "href")
            guard let id = houseId(fromHref: href) else { continue }
            let name = emptyToNil(text(of: anchor)) ?? displayName(forId: id)
            if byId[id] == nil {
                byId[id] = House(id: id, name: name)
                order.append(id)
            }
        }

        for item in elements(root, "ul.menu-list li") {
            if firstElement(item, "a[href*=house_id]") != nil { continue }
            guard let current = firstElement(item, "span.current"),
                  let name = emptyToNil(text(of: current)) else { continue }
            let id = slug(fromName: name)
            if byId[id] == nil {
                byId[id] = House(id: id, name: name)
                order.append(id)
            }
        }

        return order.compactMap { byId[$0] }
    }

    // MARK: - House page

    /// One house: leader, rooms, and anyone listed without a room.
    nonisolated static func parseHouse(_ html: String, houseId explicitId: String? = nil) -> House {
        guard let document = try? SwiftSoup.parse(html) else {
            log.warning("House page is not parseable HTML; returning an empty house.")
            let id = explicitId ?? "unknown"
            return House(id: id, name: displayName(forId: id), loaded: true)
        }
        return parseHouse(document: document, houseId: explicitId)
    }

    nonisolated static func parseHouse(document: Document, houseId explicitId: String? = nil) -> House {
        let root = contentRoot(of: document)
        let listed = parseIndex(document: document)
        let currentName = firstElement(root, "ul.menu-list span.current").map { text(of: $0) }
        let id = explicitId
            ?? listed.first(where: { $0.name.caseInsensitiveCompare(currentName ?? "") == .orderedSame })?.id
            ?? currentName.map(slug(fromName:))
            ?? "unknown"
        let name = emptyToNil(currentName)
            ?? listed.first(where: { $0.id == id })?.name
            ?? displayName(forId: id)

        var leaders: [HouseResident] = []
        var rooms: [HouseRoom] = []
        var unassigned: [HouseResident] = []
        var section: Section = .none

        for child in root.children() {
            switch child.tagName().lowercased() {
            case "h3":
                let title = text(of: child)
                guard !title.isEmpty, !isStatusHeading(title) else { continue }
                section = classify(title)
            case "ul":
                guard classNames(of: child).contains("user-list") else { continue }
                let residents = parseResidents(in: child)
                switch section {
                case .leader:
                    leaders.append(contentsOf: residents)
                case .room(let title):
                    rooms.append(
                        HouseRoom(
                            id: "\(id)-\(slug(fromName: title))",
                            name: title,
                            residents: residents
                        )
                    )
                case .unassigned:
                    unassigned.append(contentsOf: residents)
                case .none:
                    if !residents.isEmpty { unassigned.append(contentsOf: residents) }
                }
            default:
                continue
            }
        }

        return House(
            id: id,
            name: name,
            leaders: leaders.map { $0.withHouse(name) },
            rooms: rooms.map { room in
                HouseRoom(
                    id: room.id,
                    name: room.name,
                    residents: room.residents.map { $0.withHouse(name) }
                )
            },
            unassigned: unassigned.map { $0.withHouse(name) },
            loaded: true
        )
    }

    // MARK: - Slugs

    nonisolated static func houseId(fromHref href: String) -> String? {
        let decoded = href.removingPercentEncoding ?? href
        return firstCapture("[?&]house_id=([^&#]+)", in: decoded)?.lowercased()
    }

    nonisolated static func slug(fromName name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.caseInsensitiveCompare("graduated") == .orderedSame { return "grad" }
        let lowered = trimmed.lowercased()
        let kept = lowered.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        let slug = String(String.UnicodeScalarView(kept))
        return slug.isEmpty ? "unknown" : slug
    }

    nonisolated static func displayName(forId id: String) -> String {
        switch id.lowercased() {
        case "grad": return "Graduated"
        default:
            guard let first = id.first else { return id }
            return first.uppercased() + id.dropFirst()
        }
    }

    // MARK: - Residents

    private nonisolated static func parseResidents(in list: Element) -> [HouseResident] {
        var order: [String] = []
        var byId: [String: HouseResident] = [:]
        for item in list.children() where item.tagName().lowercased() == "li" {
            guard let resident = parseResident(item) else { continue }
            if byId[resident.id] == nil {
                byId[resident.id] = resident
                order.append(resident.id)
            }
        }
        return order.compactMap { byId[$0] }
    }

    private nonisolated static func parseResident(_ item: Element) -> HouseResident? {
        let anchors = elements(item, "a[href*=uwc_id]")
        guard let first = anchors.first else { return nil }
        let href = attribute(first, "href")
        guard let id = W4PeopleParser.uwcId(fromHref: href) else { return nil }
        let kind = W4PeopleParser.kind(fromHref: href) ?? .student

        var name: String?
        for anchor in anchors {
            let own = anchor.ownText()
            let text = own.isEmpty ? ((try? anchor.text()) ?? "") : own
            let cleaned = displayName(text, uwcId: id)
            if let cleaned { name = cleaned; break }
        }

        var photoURL: URL?
        if let image = firstElement(item, "img.photo") ?? firstElement(item, "img") {
            photoURL = W4PeopleParser.photoURL(fromSource: attribute(image, "src"), uwcId: id)
        }

        let status = firstElement(item, "h3").flatMap { emptyToNil(text(of: $0)) }
        let lines = textLines(of: item).filter { line in
            if let name, line.caseInsensitiveCompare(name) == .orderedSame { return false }
            if line.caseInsensitiveCompare(id) == .orderedSame { return false }
            if let status, line.caseInsensitiveCompare(status) == .orderedSame { return false }
            return true
        }
        let year = statedYear(inAnyOf: lines)
        let country = lines.first { statedYear(in: $0) == nil }

        let subtitleParts = [country, year.map(yearLabel)].compactMap { $0 }
        let person = DirectoryPerson(
            uwcId: id,
            name: name ?? id,
            kind: kind,
            year: year,
            house: nil,
            country: country,
            subtitle: emptyToNil(subtitleParts.joined(separator: " · ")),
            status: status,
            photoURL: photoURL
        )
        return HouseResident(person: person, country: country, year: year, status: status)
    }

    // MARK: - Headings

    private enum Section {
        case none
        case leader
        case room(String)
        case unassigned
    }

    private nonisolated static func classify(_ title: String) -> Section {
        let lower = title.lowercased()
        if lower.contains("house leader") || lower.contains("houseparent") { return .leader }
        if lower.contains("no room") || lower.contains("unassigned") { return .unassigned }
        if title.range(of: "^room\\b", options: [.regularExpression, .caseInsensitive]) != nil {
            return .room(title)
        }
        return .unassigned
    }

    private nonisolated static func isStatusHeading(_ title: String) -> Bool {
        title.range(
            of: "^(on campus|off campus|on a walk|at raudbua|in flekke|in dale|other)\\b",
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    // MARK: - DOM

    private nonisolated static func contentRoot(of document: Document) -> Element {
        if let inner = firstElement(document, "#content_inner") { return inner }
        if let main = firstElement(document, "#content_main") { return main }
        if let body = document.body() { return body }
        return document
    }

    private nonisolated static func textLines(of item: Element) -> [String] {
        // SwiftSoup spells this `copy(with:)` and returns `Any`; `clone()` is jsoup's name for
        // it and does not exist here. The failed call was error-typed, which is what produced the
        // four "cannot infer contextual base" errors further down this function rather than one
        // honest error on this line.
        guard let clone = item.copy() as? Element else { return [] }
        _ = try? clone.select("a").remove()
        _ = try? clone.select("h3").remove()
        _ = try? clone.select("img").remove()
        let html = (try? clone.html()) ?? ""
        return html
            .replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#039;", with: "'")
            .split(whereSeparator: \.isNewline)
            .map { collapse(String($0)) }
            .filter { !$0.isEmpty }
    }

    private nonisolated static func displayName(_ raw: String, uwcId: String) -> String? {
        var value = collapse(raw)
        if let range = value.range(of: "^photo of\\s*", options: [.regularExpression, .caseInsensitive]) {
            value.removeSubrange(range)
            value = collapse(value)
        }
        guard !value.isEmpty else { return nil }
        guard value.caseInsensitiveCompare(uwcId) != .orderedSame else { return nil }
        return value
    }

    private nonisolated static func statedYear(inAnyOf lines: [String]) -> String? {
        for line in lines {
            if let year = statedYear(in: line) { return year }
        }
        return nil
    }

    private nonisolated static func statedYear(in line: String) -> String? {
        if let digit = firstCapture("\\b([12])\\s*(?:st|nd|rd|th)\\s*year\\b", in: line) { return digit }
        if let digit = firstCapture("\\byears?\\s*([12])\\b", in: line) { return digit }
        return nil
    }

    private nonisolated static func yearLabel(_ year: String) -> String {
        switch year {
        case "1": return "1st year"
        case "2": return "2nd year"
        default: return year
        }
    }

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

    private nonisolated static func collapse(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private nonisolated static func emptyToNil(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private nonisolated static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: text) else { return nil }
        let value = String(text[captured]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
