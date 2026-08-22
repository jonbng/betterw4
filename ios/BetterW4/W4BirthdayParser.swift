//
//  W4BirthdayParser.swift
//  BetterW4
//
//  Parses `people/birthdays` (and `people/birthdays/index&month=&year=`).
//  Live capture 21 Aug 2026.
//
//  Shape: `div.calendar-div > .nav` ("August 2026") plus `table.calendar
//  td.day`. Each person is `a[title][href*=uwc_id] > img.photo`. Staff and
//  students share the grid; kind is decided per href.
//
//  Pure `(String) -> Model`. Never throws, never logs PII. Does not read the
//  clock — "today" is a UI concern over the parsed dates.
//

import Foundation
import SwiftSoup

enum W4BirthdayParser {

    private static let monthYearPattern = #"([A-Za-z]+)\s+(\d{4})"#
    private static let displayDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = W4Dates.zone
        formatter.calendar = W4Dates.calendar
        formatter.dateFormat = "EEE d MMM"
        return formatter
    }()

    nonisolated static func parse(_ html: String) -> BirthdayMonth {
        guard let document = try? SwiftSoup.parse(html) else { return BirthdayMonth() }
        let root = contentRoot(of: document)
        let nav = firstElement(root, ".calendar-div .nav") ?? firstElement(root, ".nav")
        let navText = collapsed(try? nav?.text()) ?? ""
        let monthName = firstMatch(monthYearPattern, in: navText, captureGroups: 1)
        let year = firstMatch(monthYearPattern, in: navText, captureGroups: 2).flatMap(Int.init)
        let month = monthName.flatMap(parseMonth)
        let navLinks = adjacentRefs(in: nav, year: year, month: month)
        let previous = navLinks.previous ?? fallbackAdjacent(year: year, month: month, offset: -1)
        let next = navLinks.next ?? fallbackAdjacent(year: year, month: month, offset: 1)
        let cells = (try? root.select("table.calendar td.day").array()) ?? []
        let days = cells.compactMap { parseDay($0, year: year, month: month) }
        let label = [monthName, year.map(String.init)].compactMap { $0 }.joined(separator: " ")
        return BirthdayMonth(
            monthLabel: label.isEmpty ? nil : label,
            year: year,
            month: month,
            previous: previous,
            next: next,
            days: days
        )
    }

    // MARK: - Day

    private nonisolated static func parseDay(_ cell: Element, year: Int?, month: Int?) -> BirthdayDay? {
        let header = firstElement(cell, ".day-header")
        let numberText = collapsed(try? header?.text()) ?? collapsed(cell.ownText())
        guard let dayNumber = numberText.flatMap(Int.init), dayNumber > 0 else { return nil }
        let date: Date?
        if let year, let month {
            date = W4Dates.date(year: year, month: month, day: dayNumber)
        } else {
            date = nil
        }
        let content = firstElement(cell, ".day-content") ?? cell
        let people = uniqued(parsePeople(in: content))
        let label = date.map { displayDayFormatter.string(from: $0) } ?? "\(dayNumber)"
        return BirthdayDay(
            date: date,
            dayNumber: dayNumber,
            dateLabel: label,
            people: people
        )
    }

    private nonisolated static func parsePeople(in root: Element) -> [BirthdayPerson] {
        let anchors = (try? root.select("a[href*=uwc_id]").array()) ?? []
        return anchors.compactMap(parsePerson)
    }

    private nonisolated static func parsePerson(_ anchor: Element) -> BirthdayPerson? {
        let href = attribute(anchor, "href")
        guard let uwcId = W4PeopleParser.uwcId(fromHref: href) else { return nil }
        let kind = W4PeopleParser.kind(fromHref: href) ?? .student
        let title = collapsed(attribute(anchor, "title"))
        let image = firstElement(anchor, "img.photo") ?? firstElement(anchor, "img")
        let photoSource = image.map { attribute($0, "src") } ?? ""
        let photoURL = W4PeopleParser.photoURL(fromSource: photoSource, uwcId: uwcId)
        let name = displayName(title, uwcId: uwcId)
            ?? displayName(collapsed(try? anchor.ownText()), uwcId: uwcId)
            ?? displayName(collapsed(try? image?.attr("alt")), uwcId: uwcId)
        let route: String
        switch kind {
        case .staff:
            route = "\(W4Routes.R.staffProfile)&uwc_id=\(uwcId)"
        case .student:
            route = "\(W4Routes.R.studentProfile)&uwc_id=\(uwcId)"
        }
        return BirthdayPerson(
            uwcId: uwcId,
            name: name,
            isStaff: kind == .staff,
            profileRoute: route,
            profileURL: W4Routes.url(kind.profileRoute, ["uwc_id": uwcId]),
            photoURL: photoURL
        )
    }

    private nonisolated static func displayName(_ raw: String?, uwcId: String) -> String? {
        guard var value = collapsed(raw) else { return nil }
        if let range = value.range(of: "^photo of\\s*", options: [.regularExpression, .caseInsensitive]) {
            value.removeSubrange(range)
            value = collapsed(value) ?? ""
        }
        guard !value.isEmpty else { return nil }
        guard value.caseInsensitiveCompare(uwcId) != .orderedSame else { return nil }
        return value
    }

    // MARK: - Navigation

    private nonisolated static func adjacentRefs(
        in nav: Element?,
        year: Int?,
        month: Int?
    ) -> (previous: BirthdayMonthRef?, next: BirthdayMonthRef?) {
        let links = (try? nav?.select("a[href*=month]").array()) ?? []
        var previous: BirthdayMonthRef?
        var next: BirthdayMonthRef?
        for link in links {
            guard let ref = monthRef(fromHref: attribute(link, "href")) else { continue }
            if let year, let month {
                if ref.year < year || (ref.year == year && ref.month < month) {
                    previous = ref
                } else {
                    next = ref
                }
            } else if previous == nil {
                previous = ref
            } else {
                next = ref
            }
        }
        return (previous, next)
    }

    private nonisolated static func monthRef(fromHref href: String?) -> BirthdayMonthRef? {
        guard let href, !href.isEmpty else { return nil }
        let decoded = href.removingPercentEncoding ?? href
        guard let month = firstMatch(#"[?&]month=(\d{1,2})"#, in: decoded, captureGroups: 1).flatMap(Int.init),
              (1...12).contains(month),
              let year = firstMatch(#"[?&]year=(\d{4})"#, in: decoded, captureGroups: 1).flatMap(Int.init)
        else {
            return nil
        }
        return BirthdayMonthRef(year: year, month: month)
    }

    private nonisolated static func fallbackAdjacent(year: Int?, month: Int?, offset: Int) -> BirthdayMonthRef? {
        guard let year, let month else { return nil }
        return BirthdayMonthRef(year: year, month: month).offset(by: offset)
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

    // MARK: - Helpers

    private nonisolated static func contentRoot(of document: Document) -> Element {
        (try? document.select("#content_inner").first()) ?? document.body() ?? document
    }

    private nonisolated static func firstElement(_ root: Element?, _ css: String) -> Element? {
        guard let root else { return nil }
        return try? root.select(css).first()
    }

    private nonisolated static func attribute(_ element: Element?, _ name: String) -> String {
        guard let element else { return "" }
        return (try? element.attr(name)) ?? ""
    }

    private nonisolated static func collapsed(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private nonisolated static func uniqued(_ people: [BirthdayPerson]) -> [BirthdayPerson] {
        var seen = Set<String>()
        return people.filter { seen.insert($0.uwcId.lowercased()).inserted }
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
        guard match.numberOfRanges > index,
              let swiftRange = Range(match.range(at: index), in: text)
        else {
            return nil
        }
        return String(text[swiftRange])
    }
}
