//
//  W4OnDutyParser.swift
//  BetterW4
//
//  Parses `people/onduty` (today's staff cards) and `people/onduty/schedule`
//  (the month calendar). Live capture 19 Aug 2026.
//
//  Today's page: `<h3>` role headings, then a nested table per person with a
//  `{uwc_id}_thumb.jpg` photo, a bold name, and labelled Phone / E-mail /
//  Location rows. The calendar: `td.day` with `.onduty-group-name` +
//  `.onduty-group`.
//
//  Pure `(String) -> Model`. Never throws, never logs PII.
//

import Foundation
import SwiftSoup

enum W4OnDutyParser {

    private static let fieldLabels: Set<String> = ["phone", "e-mail", "email", "location"]

    // MARK: - Today

    nonisolated static func parseToday(_ html: String) -> OnDutyPage {
        guard let document = try? SwiftSoup.parse(html) else { return OnDutyPage() }
        let root = contentRoot(of: document)
        let heading = collapsed(try? root.select("h2").first()?.text())
        let date = dateFromHeading(heading)
        return OnDutyPage(
            title: heading,
            date: date,
            dateLabel: dateLabel(from: heading, date: date),
            groups: parseRoleGroups(in: root)
        )
    }

    // MARK: - Schedule

    nonisolated static func parseSchedule(_ html: String) -> OnDutySchedule {
        guard let document = try? SwiftSoup.parse(html) else { return OnDutySchedule() }
        let root = contentRoot(of: document)
        let navText = collapsed(try? root.select(".calendar-div .nav, .nav").first()?.text()) ?? ""
        let monthYear = firstMatch(#"[A-Za-z]+\s+\d{4}"#, in: navText)
        let parts = monthYear?.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let monthName = parts?.first.map(String.init)
        let year = parts?.last.flatMap { Int($0) }
        let month = monthName.flatMap(parseMonth)
        let cells = (try? root.select("table.calendar td.day").array()) ?? []
        let days = cells.compactMap { parseCalendarDay($0, year: year, month: month) }
        let label = [monthName, year.map(String.init)].compactMap { $0 }.joined(separator: " ")
        return OnDutySchedule(
            monthLabel: label.isEmpty ? nil : label,
            year: year,
            month: month,
            days: days
        )
    }

    nonisolated static func upcomingDays(
        in schedule: OnDutySchedule,
        from: Date = W4Dates.startOfDay(TimeProvider.now),
        limit: Int = 14
    ) -> [OnDutyDay] {
        let tomorrow = W4Dates.adding(days: 1, to: W4Dates.startOfDay(from))
        return schedule.days
            .filter { day in
                guard !day.people.isEmpty else { return false }
                guard let date = day.date else { return true }
                return date >= tomorrow
            }
            .prefix(limit)
            .map { $0 }
    }

    nonisolated static func enrich(_ people: [OnDutyPerson], with contacts: [OnDutyPerson]) -> [OnDutyPerson] {
        guard !contacts.isEmpty else { return people }
        return people.map { person in
            guard let match = contacts.first(where: { namesMatch($0.name, person.name) || uwcIdsMatch($0.uwcId, person.uwcId) }) else {
                return person
            }
            return OnDutyPerson(
                id: person.id,
                name: person.name,
                role: person.role,
                uwcId: person.uwcId ?? match.uwcId,
                phone: person.phone ?? match.phone,
                email: person.email ?? match.email,
                location: person.location ?? match.location,
                photoURL: person.photoURL ?? match.photoURL
            )
        }
    }

    nonisolated static func enrich(_ day: OnDutyDay, with contacts: [OnDutyPerson]) -> OnDutyDay {
        guard !contacts.isEmpty else { return day }
        return OnDutyDay(
            id: day.id,
            date: day.date,
            dateLabel: day.dateLabel,
            isToday: day.isToday,
            groups: day.groups.map { group in
                OnDutyGroup(role: group.role, people: enrich(group.people, with: contacts))
            }
        )
    }

    // MARK: - Role groups

    private nonisolated static func parseRoleGroups(in root: Element) -> [OnDutyGroup] {
        let headings = (try? root.select("h3").array()) ?? []
        if headings.isEmpty {
            let people = parsePeople(in: root, role: "On duty")
            return people.isEmpty ? [] : [OnDutyGroup(role: "On duty", people: people)]
        }
        var groups: [OnDutyGroup] = []
        for heading in headings {
            let role = collapsed(try? heading.text()) ?? "On duty"
            var people: [OnDutyPerson] = []
            var sibling = try? heading.nextElementSibling()
            while let current = sibling {
                if current.tagName().lowercased() == "h3" { break }
                people.append(contentsOf: parsePeople(in: current, role: role))
                sibling = try? current.nextElementSibling()
            }
            let unique = uniqued(people)
            if !unique.isEmpty {
                groups.append(OnDutyGroup(role: role, people: unique))
            }
        }
        return groups
    }

    private nonisolated static func parsePeople(in root: Element, role: String) -> [OnDutyPerson] {
        let tables = (try? root.select("table").array()) ?? []
        let innermost = tables.filter { table in
            !hasNestedTable(table) && looksLikePersonCard(table)
        }
        let cards = innermost.isEmpty ? tables.filter(looksLikePersonCard) : innermost
        return uniqued(cards.compactMap { parsePersonCard($0, role: role) })
    }

    private nonisolated static func hasNestedTable(_ table: Element) -> Bool {
        let nested = (try? table.select("table").array()) ?? []
        return nested.contains { $0 !== table }
    }

    private nonisolated static func looksLikePersonCard(_ table: Element) -> Bool {
        if (try? table.select("img[src*=user_photos], img[alt*=Photo of]").first()) != nil {
            return true
        }
        return labelledValue(in: table, labels: ["phone", "e-mail", "email"]) != nil
    }

    private nonisolated static func parsePersonCard(_ card: Element, role: String) -> OnDutyPerson? {
        let img = try? card.select("img[src*=user_photos], img[alt*=Photo of], img").first()
        let uwcId = uwcId(from: img) ?? uwcId(in: (try? card.html()) ?? "")
        guard let name = displayName(in: card) else { return nil }
        let phone = labelledValue(in: card, labels: ["phone"])
        let email = labelledValue(in: card, labels: ["e-mail", "email"])
        let location = labelledValue(in: card, labels: ["location"])
        let photoURL: URL?
        if let img, let uwcId {
            photoURL = W4PeopleParser.photoURL(fromSource: (try? img.attr("src")) ?? "", uwcId: uwcId)
        } else if let uwcId {
            photoURL = W4PeopleParser.photoURL(forUWCId: uwcId)
        } else {
            photoURL = nil
        }
        return OnDutyPerson(
            id: uwcId ?? slug("\(role)-\(name)"),
            name: name,
            role: role,
            uwcId: uwcId,
            phone: phone,
            email: email,
            location: location,
            photoURL: photoURL
        )
    }

    // MARK: - Calendar

    private nonisolated static func parseCalendarDay(
        _ cell: Element,
        year: Int?,
        month: Int?
    ) -> OnDutyDay? {
        guard let dayNumber = collapsed(try? cell.select(".day-header").first()?.text()).flatMap(Int.init) else {
            return nil
        }
        let date: Date?
        if let year, let month {
            date = W4Dates.date(year: year, month: month, day: dayNumber)
        } else {
            date = nil
        }
        let content = (try? cell.select(".day-content").first()) ?? cell
        let groups = parseCalendarGroups(in: content, date: date, dayNumber: dayNumber)
        let isToday = (try? cell.hasClass("today")) ?? false
        if groups.isEmpty, !isToday { return nil }
        return OnDutyDay(
            id: date.map { W4Dates.format($0) } ?? "day-\(dayNumber)",
            date: date,
            dateLabel: date.map(displayDay) ?? "\(dayNumber)",
            isToday: isToday,
            groups: groups
        )
    }

    private nonisolated static func parseCalendarGroups(
        in content: Element,
        date: Date?,
        dayNumber: Int
    ) -> [OnDutyGroup] {
        var groups: [OnDutyGroup] = []
        var currentRole: String?
        var currentPeople: [OnDutyPerson] = []

        func flush() {
            guard let role = currentRole?.trimmingCharacters(in: .whitespacesAndNewlines), !role.isEmpty else {
                currentPeople.removeAll()
                return
            }
            if !currentPeople.isEmpty {
                groups.append(OnDutyGroup(role: role, people: currentPeople))
            }
            currentPeople.removeAll()
        }

        for child in content.children().array() {
            let hasName = (try? child.hasClass("onduty-group-name")) ?? false
            let hasGroup = (try? child.hasClass("onduty-group")) ?? false
            if hasName {
                flush()
                currentRole = collapsed(try? child.text())
            } else if hasGroup {
                let role = currentRole?.trimmingCharacters(in: .whitespacesAndNewlines)
                let resolvedRole = (role?.isEmpty == false ? role : nil) ?? "On duty"
                let dayKey = date.map(W4Dates.format) ?? "day-\(dayNumber)"
                currentPeople.append(contentsOf: splitNames(in: child).map { name in
                    OnDutyPerson(
                        id: slug("\(dayKey)-\(resolvedRole)-\(name)"),
                        name: name,
                        role: resolvedRole,
                        uwcId: nil,
                        phone: nil,
                        email: nil,
                        location: nil,
                        photoURL: nil
                    )
                })
            }
        }
        flush()
        return groups
    }

    private nonisolated static func splitNames(in element: Element) -> [String] {
        let html = (try? element.html()) ?? ""
        let normalized = html.replacingOccurrences(
            of: #"<br\s*/?>"#,
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        let parts = normalized.components(separatedBy: "\n")
        let names = parts.compactMap { fragment -> String? in
            collapsed(try? SwiftSoup.parse(fragment).text())
        }.filter { !$0.isEmpty }
        if !names.isEmpty { return names }
        return collapsed(try? element.text())
            .map { $0.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
            ?? []
    }

    // MARK: - Fields

    private nonisolated static func displayName(in card: Element) -> String? {
        let bolds = (try? card.select("b").array()) ?? []
        for bold in bolds {
            let text = (collapsed(bold.ownText()) ?? collapsed(try? bold.text()) ?? "")
                .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            if !text.isEmpty, !fieldLabels.contains(text.lowercased()) {
                return text
            }
        }
        return nil
    }

    private nonisolated static func labelledValue(in root: Element, labels: [String]) -> String? {
        let wanted = Set(labels.map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ":")) })
        let bolds = (try? root.select("b").array()) ?? []
        for bold in bolds {
            let label = (collapsed(try? bold.text()) ?? "")
                .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
                .lowercased()
            guard wanted.contains(label) else { continue }
            var bits = ""
            var node = bold.nextSibling()
            while let current = node {
                if let element = current as? Element {
                    let tag = element.tagName().lowercased()
                    if tag == "br" || tag == "b" { break }
                    bits += (try? element.text()) ?? ""
                } else if let text = current as? TextNode {
                    bits += text.getWholeText()
                }
                node = current.nextSibling()
            }
            let value = bits
                .replacingOccurrences(of: "\u{00a0}", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return nil
    }

    private nonisolated static func uwcId(from img: Element?) -> String? {
        guard let img else { return nil }
        let haystack = [
            (try? img.attr("alt")) ?? "",
            (try? img.attr("src")) ?? ""
        ].joined(separator: " ")
        return uwcId(in: haystack)
    }

    private nonisolated static func uwcId(in text: String) -> String? {
        guard let match = firstMatch(#"\b(nc\d{2}[a-z]+)\b"#, in: text, captureGroups: 1) else {
            return nil
        }
        return match.lowercased()
    }

    // MARK: - Dates

    private nonisolated static func dateFromHeading(_ heading: String?) -> Date? {
        guard let heading, !heading.isEmpty else { return nil }
        if let match = firstMatch(#"\d{1,2}-[A-Za-z]{3,9}-\d{2,4}"#, in: heading) {
            return W4Dates.parseDate(match)
        }
        return W4Dates.parseDate(heading)
    }

    private nonisolated static func dateLabel(from heading: String?, date: Date?) -> String? {
        if let heading {
            let trimmed = heading.replacingOccurrences(
                of: "People on duty",
                with: "",
                options: .caseInsensitive
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return date.map(W4Dates.format)
    }

    private nonisolated static func parseMonth(_ raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = W4Dates.zone
        formatter.calendar = W4Dates.calendar
        formatter.dateFormat = "MMMM"
        if let date = formatter.date(from: trimmed) {
            return W4Dates.calendar.component(.month, from: date)
        }
        formatter.dateFormat = "MMM"
        if let date = formatter.date(from: trimmed) {
            return W4Dates.calendar.component(.month, from: date)
        }
        return Int(trimmed).flatMap { (1...12).contains($0) ? $0 : nil }
    }

    private nonisolated static func displayDay(_ date: Date) -> String {
        displayDayFormatter.string(from: date)
    }

    private static let displayDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = W4Dates.zone
        formatter.calendar = W4Dates.calendar
        formatter.dateFormat = "EEE d MMM"
        return formatter
    }()

    // MARK: - Helpers

    private nonisolated static func contentRoot(of document: Document) -> Element {
        (try? document.select("#content_inner").first()) ?? document.body() ?? document
    }

    private nonisolated static func collapsed(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private nonisolated static func namesMatch(_ a: String, _ b: String) -> Bool {
        let left = a.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let right = b.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left == right
    }

    private nonisolated static func uwcIdsMatch(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b, !a.isEmpty, !b.isEmpty else { return false }
        return a.caseInsensitiveCompare(b) == .orderedSame
    }

    private nonisolated static func uniqued(_ people: [OnDutyPerson]) -> [OnDutyPerson] {
        var seen = Set<String>()
        return people.filter { seen.insert($0.id).inserted }
    }

    private nonisolated static func slug(_ value: String) -> String {
        let lowered = value.lowercased()
        let dashed = lowered.replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
        let cleaned = dashed.replacingOccurrences(of: #"[^a-z0-9@._+-]+"#, with: "", options: .regularExpression)
        return cleaned.isEmpty ? value : cleaned
    }

    private nonisolated static func firstMatch(
        _ pattern: String,
        in text: String,
        captureGroups: Int = 0
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        let index = captureGroups > 0 ? min(captureGroups, match.numberOfRanges - 1) : 0
        guard index < match.numberOfRanges, let swiftRange = Range(match.range(at: index), in: text) else {
            return nil
        }
        return String(text[swiftRange])
    }
}
