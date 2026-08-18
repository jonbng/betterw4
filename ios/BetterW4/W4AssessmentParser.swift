//
//  W4AssessmentParser.swift
//  BetterW4
//
//  Parser for the W4 assessments calendar, `index.php?r=academics/deadlines`
//  (side-menu route confirmed in `references/pages/Academics.html`; the calendar body is not).
//
//  READ THIS BEFORE TRUSTING ANY SELECTOR IN THIS FILE
//  ---------------------------------------------------
//  Nothing about this page has ever been captured — docs/spec/parsers.md section 6, bug B12,
//  docs/spec/reviewer-notes.md section 7. Every `data-assessment-*` attribute below is invented
//  by `android/.../feature/homework/W4AssessmentParser.kt`, and the Android fixture that
//  "proves" it is itself hand-written. The only independently corroborated names are the form
//  fields in `AssessmentFieldNames` (README section 5.2, read off a live page).
//
//  Consequences, and they are binding:
//    * every node, attribute and sub-node is optional;
//    * nothing is force-unwrapped and no sub-step throws — the worst case is `[]` plus a
//      DEBUG-only warning;
//    * writes stay behind `AssessmentFeatureFlags.writesEnabled` (OQ-3) until capture C-3
//      (`academics/deadlines` in term time plus one Confirm-done round trip) lands.
//
//  Concurrency (plan D-30): a pure `nonisolated` namespace over `String`. No I/O, no actor
//  hops, no singletons.
//
//  Dates (plan D-11): every date goes through the shared `W4Dates` (Europe/Oslo,
//  en_GB_POSIX, fixed Gregorian). `TimeZone.current` never appears here.
//

import Foundation
import SwiftSoup

nonisolated enum W4AssessmentParser {

    // MARK: - Public API

    /// Parses the month calendar into domain items.
    ///
    /// Only the initial `SwiftSoup.parse` can throw; every step after it degrades to an empty
    /// result. An empty array means "nothing recognisable on this page", which on the
    /// assessments calendar is a completely normal state (an empty month, or markup that does
    /// not match the invented selectors).
    static func parse(_ html: String) throws -> [Assessment] {
        let document = try SwiftSoup.parse(html)
        let scripts = scriptText(in: document)
        let calendarMonth = monthAndYear(scriptText: scripts, html: html)

        guard let links = try? document.select("a.assessment-link").array(), !links.isEmpty else {
            warn("no `a.assessment-link` nodes — empty month, or the invented selector is wrong (B12)")
            return []
        }

        var results: [Assessment] = []
        results.reserveCapacity(links.count)
        var seenIDs = Set<String>()

        for link in links {
            guard let item = assessment(from: link, calendarMonth: calendarMonth) else { continue }
            // A month grid can render the same item in more than one cell; identity wins.
            if seenIDs.insert(item.id).inserted {
                results.append(item)
            }
        }

        if results.isEmpty {
            warn("\(links.count) `a.assessment-link` node(s) matched but none carried a usable id")
        }
        return results
    }

    /// Recovers the confirm / revert / save / create / delete endpoints from the page's inline
    /// `var ajax_urls = { … }` object.
    ///
    /// Returns `nil` when W4 published nothing at all — the signal to keep every write
    /// affordance hidden. The URLs carry `&month=&year=&uwc_id=` and are regenerated per page
    /// render, so they must never be hardcoded.
    static func parseAjaxURLs(_ html: String) throws -> AssessmentActionURLs? {
        let document = try SwiftSoup.parse(html)
        return ajaxURLs(scriptText: scriptText(in: document), html: html)
    }

    /// The POST body for a "Confirm done" / "Revert to pending" transition.
    ///
    /// Keyed by kind, and getting it backwards is the failure mode this whole function exists
    /// to prevent: a class-assigned item posts `assessment_id`, a student-created item posts
    /// `student_assessment_id`. Send the wrong key and W4 accepts the request and changes
    /// nothing, so "confirm done" silently does nothing.
    ///
    /// The same payload serves `delete` for a student-created item.
    static func statusFields(for item: Assessment) -> [String: String] {
        statusFields(kind: item.kind, rawId: item.rawId)
    }

    /// Kind-keyed payload builder for callers that do not hold a whole `Assessment`.
    static func statusFields(kind: AssessmentKind, rawId: String) -> [String: String] {
        let trimmed = rawId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            warn("statusFields called with an empty raw id; refusing to build a payload")
            return [:]
        }
        return [kind.identifierFieldName: trimmed]
    }

    // MARK: - One calendar entry

    private static func assessment(
        from link: Element,
        calendarMonth: (month: Int, year: Int)?
    ) -> Assessment? {
        let rawId = attribute("data-assessment-id", of: link)
        guard !rawId.isEmpty else { return nil }

        let rawKind = attribute("data-assessment-type", of: link)
        let kind = AssessmentKind.from(rawKind)

        let rawStatus = attribute("data-status", of: link)
        let status = AssessmentStatus.from(rawStatus)

        let subject = attribute("data-subject-name", of: link)
        let unit = attribute("data-unit", of: link)
        let anchorText = ((try? link.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let title = [anchorText, unit, subject].first(where: { !$0.isEmpty }) ?? "Assessment"

        // "Overdue" arrives either as `data-css-class` or as a class on the anchor itself.
        let cssClass = attribute("data-css-class", of: link).lowercased()
        let anchorClasses = ((try? link.className()) ?? "").lowercased()
        let isOverdue = cssClass.contains("overdue") || anchorClasses.contains("overdue")

        let rawDate = attribute("data-assessment-date", of: link)
        let dueDate = (rawDate.isEmpty ? nil : W4Dates.parseDate(rawDate))
            ?? dayCellDate(for: link, calendarMonth: calendarMonth)

        return Assessment(
            id: "\(kind.rawValue):\(rawId)",
            rawId: rawId,
            kind: kind,
            rawKind: rawKind,
            title: title,
            subject: nilIfBlank(subject),
            classCode: nilIfBlank(attribute("data-class-id", of: link)),
            teacher: nilIfBlank(attribute("data-teacher-name", of: link)),
            unit: nilIfBlank(unit),
            dueDate: dueDate,
            daysLeft: Int(attribute("data-days-left", of: link)),
            status: status,
            rawStatus: rawStatus,
            isOverdue: isOverdue,
            isEditable: isTruthy(attribute("data-editable", of: link)),
            href: normalizedHref(attribute("href", of: link))
        )
    }

    // MARK: - Date fallback (calendar cell + page month/year)

    /// An item with no `data-assessment-date` falls back to the day number of the calendar cell
    /// it sits in, plus the month and year the page itself declares.
    private static func dayCellDate(
        for link: Element,
        calendarMonth: (month: Int, year: Int)?
    ) -> Date? {
        guard let calendarMonth = calendarMonth else { return nil }
        guard let day = dayNumber(forCellContaining: link) else { return nil }
        guard day >= 1, day <= daysInMonth(month: calendarMonth.month, year: calendarMonth.year) else {
            warn("day \(day) is out of range for \(calendarMonth.month)/\(calendarMonth.year)")
            return nil
        }
        return W4Dates.parseDate(
            wireDate(day: day, month: calendarMonth.month, year: calendarMonth.year)
        )
    }

    /// Walks up to the enclosing calendar cell and reads its `.day-header` number.
    /// `td.no-day` padding cells are skipped — they carry no day.
    private static func dayNumber(forCellContaining link: Element) -> Int? {
        for ancestor in link.parents().array() {
            if ancestor.hasClass("no-day") { continue }
            let looksLikeDayCell = ancestor.hasClass("day")
                || ancestor.children().array().contains { $0.hasClass("day-header") }
            guard looksLikeDayCell else { continue }
            guard let header = try? ancestor.select(".day-header").first(),
                  let text = try? header.text() else { continue }
            if let digits = firstCapture(#"(\d{1,2})"#, in: text), let day = Int(digits) {
                return day
            }
        }
        return nil
    }

    /// Renders `dd-MMM-yyyy` with hardcoded English month abbreviations, which is exactly what
    /// `W4Dates`' `en_GB_POSIX` locale expects and what W4 itself emits.
    private static func wireDate(day: Int, month: Int, year: Int) -> String {
        guard month >= 1, month <= monthAbbreviations.count else { return "" }
        let dayPart = day < 10 ? "0\(day)" : "\(day)"
        return "\(dayPart)-\(monthAbbreviations[month - 1])-\(year)"
    }

    private static let monthAbbreviations = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ]

    private static func daysInMonth(month: Int, year: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        case 2: return isLeapYear(year) ? 29 : 28
        default: return 0
        }
    }

    private static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    // MARK: - Page month / year (bug B11)

    /// The month and year the calendar is showing.
    ///
    /// Bug B11: the Android regexes `month=(\d+)` / `year=(\d{4})` do **not** match a
    /// declaration like `var month = 08 - 1;` (spaces around `=`); they only ever matched by
    /// accident inside the `ajax_urls` query strings. Both forms are handled here, script text
    /// first so a "previous month" nav link cannot win over the page's own state.
    private static func monthAndYear(scriptText: String, html: String) -> (month: Int, year: Int)? {
        var month: Int?
        var year: Int?
        for source in [scriptText, html] where !source.isEmpty {
            if month == nil { month = parsedMonth(in: source) }
            if year == nil { year = parsedYear(in: source) }
            if month != nil, year != nil { break }
        }
        guard let month = month, let year = year else {
            warn("page declares no month/year; items without `data-assessment-date` get no date")
            return nil
        }
        return (month, year)
    }

    private static func parsedMonth(in source: String) -> Int? {
        // Form A: `var month = 08 - 1;`. The literal is the 1-based month; the `- 1` is only
        // there to feed JavaScript's 0-based `Date` constructor.
        if let value = intCapture(#"\bmonth\s*=\s*(\d{1,2})\s*-\s*1\b"#, in: source, within: 1...12) {
            return value
        }
        // Form B: a `month=MM` query key, inside `ajax_urls` or a navigation link. Yii query
        // params are 1-based.
        if let value = intCapture(#"[?&]month=(\d{1,2})"#, in: source, within: 1...12) {
            return value
        }
        // Bare declaration. Genuinely ambiguous — W4 could already be 0-based here — so it is
        // the last resort and it is logged.
        if let value = intCapture(#"\bmonth\s*=\s*(\d{1,2})"#, in: source, within: 1...12) {
            warn("month came from a bare `month = N` declaration; assuming 1-based (OQ-3)")
            return value
        }
        return nil
    }

    private static func parsedYear(in source: String) -> Int? {
        intCapture(#"\byear\s*=\s*(\d{4})"#, in: source, within: 1900...2200)
            ?? intCapture(#"[?&]year=(\d{4})"#, in: source, within: 1900...2200)
    }

    // MARK: - AJAX endpoints

    private static func ajaxURLs(scriptText: String, html: String) -> AssessmentActionURLs? {
        for source in [scriptText, html] where !source.isEmpty {
            // Prefer the `ajax_urls = { … }` object so an unrelated `save: '…'` elsewhere on
            // the page cannot be mistaken for an endpoint.
            let scope = firstCapture(#"ajax_urls\s*=\s*\{([^}]*)\}"#, in: source) ?? source
            var found: [String: String] = [:]
            for pair in keyedStringLiterals(in: scope) where found[pair.key] == nil {
                found[pair.key] = pair.value
            }
            let urls = AssessmentActionURLs(
                confirm: found["confirm"] ?? "",
                revert: found["revert"] ?? "",
                save: found["save"] ?? "",
                create: found["create"] ?? "",
                delete: found["delete"] ?? ""
            )
            if !urls.isEmpty { return urls }
        }
        warn("no `ajax_urls` block found; assessment writes must stay disabled")
        return nil
    }

    /// `delete` is a JavaScript reserved word, so Yii may quote the key (`'delete': '…'`);
    /// the optional quotes in this pattern are what make that case work.
    private static let ajaxPairPattern =
        #"["']?\b(confirm|revert|save|create|delete)\b["']?\s*:\s*["']([^"']*)["']"#

    private static func keyedStringLiterals(in text: String) -> [(key: String, value: String)] {
        guard !text.isEmpty,
              let regex = try? NSRegularExpression(pattern: ajaxPairPattern, options: [.caseInsensitive])
        else { return [] }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var pairs: [(key: String, value: String)] = []
        for match in regex.matches(in: text, options: [], range: range) {
            guard match.numberOfRanges >= 3,
                  let keyRange = Range(match.range(at: 1), in: text),
                  let valueRange = Range(match.range(at: 2), in: text) else { continue }
            let key = String(text[keyRange]).lowercased()
            let value = decodeJavaScriptString(String(text[valueRange]))
                .replacingOccurrences(of: "&amp;", with: "&")
            pairs.append((key: key, value: value))
        }
        return pairs
    }

    /// Yii's `CJavaScript::encode` escapes `/` as `\x2F` — `references/pages/UWCRCN W4.html`
    /// publishes the campus-status endpoint as `site\x2Fsetstatus`, so the assessments
    /// endpoints are very likely escaped the same way. Decoding is cheap insurance; a URL that
    /// needs no decoding passes straight through.
    private static func decodeJavaScriptString(_ raw: String) -> String {
        guard raw.contains("\\") else { return raw }
        let characters = Array(raw)
        var result = ""
        result.reserveCapacity(characters.count)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            guard character == "\\", index + 1 < characters.count else {
                result.append(character)
                index += 1
                continue
            }
            let next = characters[index + 1]
            switch next {
            case "x", "X":
                if let scalar = hexScalar(characters, start: index + 2, length: 2) {
                    result.append(Character(scalar))
                    index += 4
                } else {
                    result.append(character)
                    index += 1
                }
            case "u", "U":
                if let scalar = hexScalar(characters, start: index + 2, length: 4) {
                    result.append(Character(scalar))
                    index += 6
                } else {
                    result.append(character)
                    index += 1
                }
            case "n":
                result.append("\n")
                index += 2
            case "t":
                result.append("\t")
                index += 2
            case "r":
                result.append("\r")
                index += 2
            default:
                // Covers \/ \\ \' \" and any escape we have not seen: keep the character,
                // drop the backslash.
                result.append(next)
                index += 2
            }
        }
        return result
    }

    private static func hexScalar(_ characters: [Character], start: Int, length: Int) -> Unicode.Scalar? {
        let end = start + length
        guard start >= 0, end <= characters.count else { return nil }
        let digits = String(characters[start..<end])
        guard digits.count == length,
              digits.allSatisfy({ $0.isHexDigit }),
              let value = UInt32(digits, radix: 16),
              let scalar = Unicode.Scalar(value) else { return nil }
        return scalar
    }

    // MARK: - SwiftSoup helpers

    private static func scriptText(in document: Document) -> String {
        guard let scripts = try? document.select("script").array(), !scripts.isEmpty else { return "" }
        return scripts.map { $0.data() }.joined(separator: "\n")
    }

    private static func attribute(_ name: String, of element: Element) -> String {
        ((try? element.attr(name)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func nilIfBlank(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }

    private static func isTruthy(_ value: String) -> Bool {
        ["1", "true", "yes"].contains(value.lowercased())
    }

    private static func normalizedHref(_ raw: String) -> String? {
        guard !raw.isEmpty, raw != "#" else { return nil }
        if raw.lowercased().hasPrefix("javascript:") { return nil }
        return raw
    }

    // MARK: - Regex helpers

    private static func firstCapture(_ pattern: String, in text: String, group: Int = 1) -> String? {
        guard !text.isEmpty,
              let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > group,
              let captured = Range(match.range(at: group), in: text) else { return nil }
        return String(text[captured])
    }

    private static func intCapture(
        _ pattern: String,
        in text: String,
        within bounds: ClosedRange<Int>
    ) -> Int? {
        guard let captured = firstCapture(pattern, in: text), let value = Int(captured) else { return nil }
        return bounds.contains(value) ? value : nil
    }

    // MARK: - Logging

    /// DEBUG-only, and never prints page content — only what the parser failed to find.
    private static func warn(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("⚠️ W4AssessmentParser: \(message())")
        #endif
    }
}
