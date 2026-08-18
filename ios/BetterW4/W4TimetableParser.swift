//
//  W4TimetableParser.swift
//  BetterW4
//
//  Parses a W4 `#timetable` week grid — the Home page grid, `academics/timetable/mytimetable`
//  and `extraacademics/timetable/mytimetable` all render the same structure.
//
//  What is VERIFIED against `references/pages/UWCRCN W4.html`:
//
//    * The page ships **two** elements with `id="timetable"` (parsers.md bug B1). The outer one
//      holds the `<h3>` heading and `#timetable-header`; the inner one holds the day columns.
//      `getElementById` returns the wrong one, so the grid is taken with `select(...).last()`.
//    * `#timetable-header .header-cell` carries `.day-name`, a `dd-MMM-yyyy` date line,
//      `.rotation-day` ("Day 1"…"Day 5" / "Weekend", with class `no-classes`), and an EA line
//      that reads "No EA" when empty.
//    * The grid is an hour gutter column of 15 `.cell` labels ("7:00 — 8:00" … "21:00 — 22:00")
//      followed by one `.column` per day; today's column also carries `current`.
//    * `tt_start_hour = 7`, `tt_end_hour = 22`, column height 900px over 15 hours, therefore
//      **1px == 1 minute** measured from `tt_start_hour`.
//
//  What is NOT verified, and why this file is defensive everywhere:
//
//    The only capture we have is a holiday week containing **zero** `.period` elements. Every
//    lesson-block selector below (`.period`, `.inner`, `.datetime`, `.room`, the attendance
//    marker classes) is inherited from the Android port and has never been seen against real W4
//    lesson markup. Nothing here force-unwraps, and a block that matches nothing we expect still
//    produces an event positioned by pixel geometry — which is the part we can actually prove.
//

import Foundation
import SwiftSoup

/// The grid's coordinate system: hour bounds and the pixel-to-minute mapping.
enum W4TimetableGeometry {
    /// `tt_start_hour` in every capture.
    static let defaultStartHour = 7
    /// `tt_end_hour` in every capture.
    static let defaultEndHour = 22

    /// 900px spanning 15 hours ⇒ one minute per pixel. This is the one piece of lesson-block
    /// geometry we can prove without ever having seen a lesson block.
    static let minutesPerPixel = 1.0

    /// Shortest block we will render; a sub-15-minute sliver is unreadable and almost certainly
    /// a rounding artefact rather than a real lesson.
    static let minimumBlockMinutes = 15

    /// Converts a `top:` offset inside the grid into minutes from midnight.
    static func minutesFromMidnight(topPixels: Double, startHour: Int) -> Int {
        startHour * 60 + Int((topPixels * minutesPerPixel).rounded())
    }
}

/// Pure, `nonisolated` parser: HTML in, models out. No clock, no network, no storage.
enum W4TimetableParser {

    // MARK: - Public API

    /// Parses one week grid.
    ///
    /// - Parameters:
    ///   - html: the full page HTML.
    ///   - source: which timetable this is, so event ids stay unique after an AC+EA merge (D-9).
    ///   - fallbackYear/fallbackWeek: used only when the header carries no parseable dates.
    static func parseWeek(
        html: String,
        source: EventSource,
        fallbackYear: Int? = nil,
        fallbackWeek: Int? = nil
    ) -> ScheduleWeek {
        guard let document = try? SwiftSoup.parse(html) else {
            W4TimetableParser.warn("HTML would not parse")
            return emptyWeek(source: source, year: fallbackYear, week: fallbackWeek)
        }

        let startHour = scriptInt(in: html, variable: "tt_start_hour")
            ?? W4TimetableGeometry.defaultStartHour
        let endHour = scriptInt(in: html, variable: "tt_end_hour")
            ?? W4TimetableGeometry.defaultEndHour

        let headerCells = (try? document.select("#timetable-header .header-cell").array()) ?? []
        var days = headerCells.compactMap(parseHeaderCell)

        // Bug B1: the grid is the LAST `#timetable`, never `getElementById`.
        let grid = (try? document.select("div#timetable").array())?.last
        let dayColumns = grid.map(dayColumns(in:)) ?? []

        // No header dates, but the grid did render columns: synthesise the ISO week so the
        // lessons still land somewhere sensible, one day per column.
        //
        // The `!dayColumns.isEmpty` condition is load-bearing. A page with neither header cells
        // nor columns — an error page, a truncated response, markup we do not recognise — must
        // produce an EMPTY week, not seven invented empty days. The repository treats a week with
        // no days as a failed fetch and keeps the copy it already had; seven blank days would
        // instead read as "this week genuinely has no lessons" and silently wipe a good week.
        if days.isEmpty, !dayColumns.isEmpty {
            days = fallbackDays(count: dayColumns.count, year: fallbackYear, week: fallbackWeek)
        }

        days = days.enumerated().map { index, day in
            guard let column = dayColumns[safe: index] else { return day }
            let events = parseColumn(column, day: day, source: source, startHour: startHour)
            let isToday = day.isToday || hasClass(column, "current")
            return ScheduleDay(
                date: day.date,
                dayName: day.dayName,
                rotationDay: day.rotationDay,
                isNoClasses: day.isNoClasses,
                eaNote: day.eaNote,
                isToday: isToday,
                events: events
            )
        }

        let title = (try? document.select("#timetable h3").first()?.text())?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Bug B5: the header date is the truth. Never assume the grid starts on a Monday.
        let isoWeek = days.first.map { W4Dates.isoWeek(of: $0.date) }

        return ScheduleWeek(
            year: isoWeek?.year ?? fallbackYear ?? 0,
            week: isoWeek?.week ?? fallbackWeek ?? 0,
            title: title?.isEmpty == false ? title : nil,
            source: source,
            startHour: startHour,
            endHour: endHour,
            days: days
        )
    }

    /// Overlays a second grid (typically Extra Academics) onto a primary one, matching on date.
    /// The primary week's identity and hour bounds win; only events are merged.
    static func merge(_ primary: ScheduleWeek, with extra: ScheduleWeek) -> ScheduleWeek {
        let extraByDay = Dictionary(
            extra.days.map { (W4Dates.startOfDay($0.date), $0.events) },
            uniquingKeysWith: { $0 + $1 }
        )

        let days = primary.days.map { day -> ScheduleDay in
            guard let additional = extraByDay[W4Dates.startOfDay(day.date)], !additional.isEmpty else {
                return day
            }
            return day.withEvents(sorted(day.events + additional))
        }

        return ScheduleWeek(
            year: primary.year,
            week: primary.week,
            title: primary.title,
            source: primary.source,
            startHour: min(primary.startHour, extra.startHour),
            endHour: max(primary.endHour, extra.endHour),
            days: days,
            fetchedAt: primary.fetchedAt
        )
    }

    // MARK: - Header

    /// One `.header-cell`: day name, date, rotation day, EA note.
    private static func parseHeaderCell(_ cell: Element) -> ScheduleDay? {
        let dayName = text(of: cell, selector: ".day-name") ?? ""

        // The date is its own `<div>` with no class, so scan every child for the first parseable
        // `dd-MMM-yyyy`. Without a date the column cannot be placed at all.
        let children = cell.children().array()
        let date = children
            .compactMap { child -> Date? in
                let raw = ((try? child.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty else { return nil }
                return W4Dates.parseDate(raw)
            }
            .first

        guard let date else {
            warn("header cell without a parseable date — column skipped")
            return nil
        }

        let rotationElement = try? cell.select(".rotation-day").first()
        let rotationDay = (try? rotationElement?.text())?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Bug B4: `no-classes` is a CLASS, not the literal text "No-Classes".
        let isNoClasses = rotationElement.map { hasClass($0, "no-classes") } ?? false

        // The EA line is the last unclassed child that is not the date and not the day name.
        let eaNote = children
            .compactMap { child -> String? in
                guard classNames(of: child).isEmpty else { return nil }
                let raw = ((try? child.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty, W4Dates.parseDate(raw) == nil else { return nil }
                return raw
            }
            .last

        return ScheduleDay(
            date: W4Dates.startOfDay(date),
            dayName: dayName,
            rotationDay: rotationDay?.isEmpty == false ? rotationDay : nil,
            isNoClasses: isNoClasses,
            eaNote: eaNote
        )
    }

    private static func fallbackDays(count: Int, year: Int?, week: Int?) -> [ScheduleDay] {
        guard let year, let week, let monday = W4Dates.startOfISOWeek(year: year, week: week) else {
            return []
        }
        warn("no header dates — falling back to ISO week \(week)/\(year)")
        return (0..<count).map { offset in
            let date = W4Dates.adding(days: offset, to: monday)
            return ScheduleDay(date: date, dayName: W4Dates.weekdayName(of: date))
        }
    }

    // MARK: - Columns

    /// Day columns are `.column` elements that do NOT contain `.cell` labels — the one that does
    /// is the hour gutter down the left-hand side.
    private static func dayColumns(in grid: Element) -> [Element] {
        grid.children().array().filter { child in
            guard classNames(of: child).contains("column") else { return false }
            let hasHourLabels = ((try? child.select(".cell").first()) ?? nil) != nil
            return !hasHourLabels
        }
    }

    private static func parseColumn(
        _ column: Element,
        day: ScheduleDay,
        source: EventSource,
        startHour: Int
    ) -> [TimetableEvent] {
        let blocks = (try? column.select(".period").array()) ?? []
        let events = blocks.enumerated().compactMap { index, block in
            parseBlock(block, day: day, source: source, startHour: startHour, index: index)
        }
        return sorted(events)
    }

    // MARK: - Lesson blocks

    /// **[I] — no real `.period` element has ever been captured.** Everything here is optional and
    /// falls back to pixel geometry, which is the only verified part.
    private static func parseBlock(
        _ block: Element,
        day: ScheduleDay,
        source: EventSource,
        startHour: Int,
        index: Int
    ) -> TimetableEvent? {
        let inner = (try? block.select(".inner").first()) ?? block

        let datetimeText = text(of: inner, selector: ".datetime") ?? ""
        let room = text(of: inner, selector: ".room")
        let href = try? block.select("a[href]").first()?.attr("href")
        // Bug B3: `div.period[title]` is proven to exist and is the likeliest home of teacher,
        // full subject name and change notes. Captured raw, deliberately unparsed.
        let rawTooltip = (try? block.attr("title"))?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let title = blockTitle(inner)
        // A "No-Classes" filler block is grid furniture, not a lesson.
        guard !title.isEmpty, title.caseInsensitiveCompare("No-Classes") != .orderedSame else {
            return nil
        }

        let range = timeRange(in: datetimeText) ?? timeRange(in: (try? inner.text()) ?? "")
        let placement = range.map { range -> (start: Date?, end: Date?) in
            (
                W4Dates.date(onDayOf: day.date, minutesFromMidnight: range.startMinutes),
                W4Dates.date(onDayOf: day.date, minutesFromMidnight: range.endMinutes)
            )
        } ?? pixelPlacement(of: block, day: day, startHour: startHour)

        return TimetableEvent(
            id: eventID(href: href, source: source, day: day, index: index),
            title: title,
            source: source,
            start: placement.start,
            end: placement.end,
            date: day.date,
            room: room,
            teacherUwcId: uwcId(in: href),
            status: status(of: block, inner: inner),
            attendance: attendance(of: inner),
            isAllDay: placement.start == nil,
            href: href?.isEmpty == false ? href : nil,
            rawTooltip: rawTooltip?.isEmpty == false ? rawTooltip : nil
        )
    }

    /// The verified fallback: `top`/`height` in pixels, one minute per pixel from `tt_start_hour`.
    private static func pixelPlacement(
        of block: Element,
        day: ScheduleDay,
        startHour: Int
    ) -> (start: Date?, end: Date?) {
        let style = (try? block.attr("style")) ?? ""
        guard let top = pixels(in: style, property: "top") else { return (nil, nil) }
        let height = pixels(in: style, property: "height") ?? 60
        let startMinutes = W4TimetableGeometry.minutesFromMidnight(topPixels: top, startHour: startHour)
        let endMinutes = startMinutes + max(
            W4TimetableGeometry.minimumBlockMinutes,
            Int((height * W4TimetableGeometry.minutesPerPixel).rounded())
        )
        return (
            W4Dates.date(onDayOf: day.date, minutesFromMidnight: startMinutes),
            W4Dates.date(onDayOf: day.date, minutesFromMidnight: endMinutes)
        )
    }

    /// Title = the block's text minus the chrome we render separately.
    private static func blockTitle(_ inner: Element) -> String {
        var parts: [String] = []
        for node in inner.getChildNodes() {
            if let element = node as? Element {
                guard element.tagName().lowercased() != "br" else { continue }
                guard classNames(of: element).isDisjoint(with: chromeClasses) else { continue }
                let text = ((try? element.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { parts.append(text) }
            } else if let textNode = node as? TextNode {
                let text = textNode.text().trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { parts.append(text) }
            }
        }
        if parts.isEmpty {
            // Everything was chrome (or an unexpected shape) — fall back to the whole block.
            let whole = ((try? inner.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return whole
        }
        return parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Chrome rendered from dedicated fields, so it must not leak into the title.
    private static let chromeClasses: Set<String> = [
        "datetime", "room", "absence", "present", "normal", "prearranged", "close"
    ]

    private static func status(of block: Element, inner: Element) -> EventStatus {
        let classes = classNames(of: block).union(classNames(of: inner))
        if classes.contains("cancelled") || classes.contains("canceled") { return .cancelled }
        if classes.contains("moved") { return .moved }
        if classes.contains("changed") { return .changed }
        return .normal
    }

    private static func attendance(of inner: Element) -> LessonAttendance? {
        let classes = classNames(of: inner)
        // `.normal` inside an attendance marker means an unexcused absence in W4's own stylesheet,
        // which is why it is not treated as "nothing to report".
        if classes.contains("prearranged") { return .prearranged }
        if classes.contains("present") { return .present }
        if classes.contains("absence") || classes.contains("normal") { return .absent }
        if let marker = try? inner.select(".absence, .present, .normal, .prearranged").first() {
            let markerClasses = classNames(of: marker)
            if markerClasses.contains("prearranged") { return .prearranged }
            if markerClasses.contains("present") { return .present }
            if markerClasses.contains("absence") || markerClasses.contains("normal") { return .absent }
        }
        return nil
    }

    /// Source-prefixed so an Academics class and an EA group with the same numeric id do not
    /// collapse into one event when the two weeks merge (bug B20 / plan D-9).
    private static func eventID(
        href: String?,
        source: EventSource,
        day: ScheduleDay,
        index: Int
    ) -> String {
        if let href, let match = firstGroup(in: href, pattern: #"(?:id|class_id|group_id)=(\d+)"#) {
            return "\(source.idPrefix)-w4-\(match)"
        }
        return "\(source.idPrefix)-\(W4Dates.format(day.date))-\(index)"
    }

    // MARK: - Text helpers

    private struct TimeRange {
        let startMinutes: Int
        let endMinutes: Int
    }

    /// Accepts an em dash (U+2014, what W4 actually renders), an en dash and a plain hyphen.
    private static func timeRange(in text: String) -> TimeRange? {
        guard let match = firstMatch(
            in: text,
            pattern: #"(\d{1,2}):(\d{2})\s*[—–-]\s*(\d{1,2}):(\d{2})"#,
            groups: 4
        ) else { return nil }

        guard let startHour = Int(match[0]), let startMinute = Int(match[1]),
              let endHour = Int(match[2]), let endMinute = Int(match[3]) else { return nil }

        return TimeRange(
            startMinutes: startHour * 60 + startMinute,
            endMinutes: endHour * 60 + endMinute
        )
    }

    private static func pixels(in style: String, property: String) -> Double? {
        guard let raw = firstGroup(
            in: style,
            pattern: property + #"\s*:\s*(-?\d+(?:\.\d+)?)px"#
        ) else { return nil }
        return Double(raw)
    }

    private static func scriptInt(in html: String, variable: String) -> Int? {
        firstGroup(in: html, pattern: variable + #"\s*=\s*(\d+)"#).flatMap(Int.init)
    }

    private static func uwcId(in href: String?) -> String? {
        guard let href else { return nil }
        return firstGroup(in: href, pattern: #"\b(nc\d{2}[a-z]+)\b"#)?.lowercased()
    }

    private static func text(of element: Element, selector: String) -> String? {
        guard let found = try? element.select(selector).first(),
              let text = try? found.text() else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func classNames(of element: Element) -> Set<String> {
        let raw = (try? element.attr("class")) ?? ""
        return Set(raw.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init))
    }

    private static func hasClass(_ element: Element, _ name: String) -> Bool {
        classNames(of: element).contains(name)
    }

    private static func sorted(_ events: [TimetableEvent]) -> [TimetableEvent] {
        events.sorted { lhs, rhs in
            switch (lhs.start, rhs.start) {
            case let (left?, right?):
                return left == right ? lhs.title < rhs.title : left < right
            case (nil, _?):
                return true          // all-day blocks first
            case (_?, nil):
                return false
            case (nil, nil):
                return lhs.title < rhs.title
            }
        }
    }

    private static func emptyWeek(source: EventSource, year: Int?, week: Int?) -> ScheduleWeek {
        ScheduleWeek(year: year ?? 0, week: week ?? 0, source: source)
    }

    private static func warn(_ message: String) {
        #if DEBUG
        print("⚠️ [W4TimetableParser] \(message)")
        #endif
    }

    // MARK: - Regex

    private static func firstMatch(in text: String, pattern: String, groups: Int) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(
                in: text,
                options: [],
                range: NSRange(text.startIndex..<text.endIndex, in: text)
              ),
              match.numberOfRanges > groups
        else { return nil }

        return (1...groups).compactMap { index in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func firstGroup(in text: String, pattern: String) -> String? {
        firstMatch(in: text, pattern: pattern, groups: 1)?.first
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
