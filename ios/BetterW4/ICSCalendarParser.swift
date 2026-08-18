//
//  ICSCalendarParser.swift
//  BetterW4
//
//  W4 port plan Wave 4, item 4.11 — the iCalendar overlay.
//  Spec: docs/spec/parsers.md §5; open question OQ-8; bug register entry B21.
//
//  WHAT THIS PARSES
//
//    Two kinds of iCalendar stream feed the timetable:
//
//      1. The college-wide Google Calendar that Home embeds in its `#calendar`
//         iframe (`SchoolCalendar.icsURLString`). Public, no auth.
//      2. The per-user W4 feeds under `academics/feeds` (`…/acttical`,
//         `eattical`, `combottical`, `sassttical`), each carrying a
//         `token=<secret>` query parameter.
//
//    This file only ever sees the **bytes**, never a URL: `events(ics:…)` takes
//    a `String`. That is deliberate. The `token=` value in a personal feed URL
//    is password-equivalent (README §4.8, features.md §1.14), so no code path
//    here can log one — see `warn(_:)`, whose parameter is a `StaticString` and
//    therefore cannot carry a runtime value at all.
//
//  EVIDENCE
//
//    **[I] — nothing here is verified against a live W4 feed.** No
//    `academics/feeds` response has ever been captured, and the saved copy of
//    the Home `#calendar` iframe (`references/pages/UWCRCN W4_files/embed.html`)
//    is an empty `about:blank` document, so even the Google calendar id is
//    inherited from the Android port rather than observed (OQ-8). The iCalendar
//    grammar itself is RFC 5545, which is real; the fixture that exercises it is
//    hand-written and proves this PARSER, not W4.
//
//    Consequence, as everywhere else in this wave: a stream we cannot read
//    yields an empty array plus a structural warning. Nothing throws, nothing is
//    force-unwrapped, and every runaway construct is capped.
//
//  TIMEZONE (bug B21)
//
//    The Kotlin original takes a `zone` parameter and then ignores it, hardcoding
//    Europe/Oslo inside `parseUtcDateTime`. Here the zone is threaded all the way
//    through:
//
//      * `DTSTART:20260818T113000Z`             → a UTC instant.
//      * `DTSTART;TZID=Europe/Oslo:20260814T140000` → that zone's wall clock.
//      * `DTSTART:20260814T140000` (floating)   → `zone`'s wall clock, i.e.
//        Europe/Oslo by default, because that is what W4 renders in.
//      * `DTSTART;VALUE=DATE:20260814`          → midnight in `zone`.
//
//    `TimeZone.current` appears nowhere, and all calendar arithmetic runs in a
//    Gregorian calendar pinned to `zone`, so a weekly 08:30 lesson stays 08:30
//    across a DST change.
//

import Foundation

/// Pure, synchronous iCalendar reader: text in, `TimetableEvent`s out.
/// No network, no storage, no clock reads.
enum ICSCalendarParser {

    // MARK: - Caps
    //
    // A feed is remote input. Every loop below is bounded so a malformed or
    // hostile `RRULE` (`FREQ=DAILY;INTERVAL=0`, an `UNTIL` in the year 9999, a
    // `COUNT` of ten million) cannot spin the app. The four recurrence caps are
    // the ones `parsers.md` §5 specifies.

    enum Limits {
        /// Iterations of an unbounded `FREQ=DAILY` walk (~13 months).
        static let dailyIterations = 400
        /// Iterations of an unbounded `FREQ=WEEKLY` walk (~18 months).
        static let weeklyIterations = 80
        /// Iterations of an unbounded `FREQ=MONTHLY` walk (3 years).
        static let monthlyIterations = 36
        /// Iterations of an unbounded `FREQ=YEARLY` walk.
        static let yearlyIterations = 8
        /// `COUNT` is walked from `DTSTART`, so it gets its own cap. A rule with
        /// a larger `COUNT` is truncated rather than obeyed.
        static let countedOccurrences = 800
        /// `VEVENT` blocks read from one stream.
        static let events = 10_000
        /// `EXDATE` instants remembered per event.
        static let exceptions = 2_000
        /// Occurrences returned from one `events(ics:…)` call.
        static let totalOccurrences = 20_000
    }

    // MARK: - Public API

    /// Every occurrence that touches the Oslo days `[from, toExclusive)`.
    ///
    /// - Parameters:
    ///   - ics: the raw iCalendar text. Never a URL — see the file header.
    ///   - from: first day of the window; truncated to the start of that day.
    ///   - toExclusive: first day **after** the window, also truncated.
    ///   - zone: the wall-clock zone floating times are read in and every result
    ///     is bucketed by. Defaults to `W4Dates.zone` (Europe/Oslo). Never
    ///     `TimeZone.current`.
    ///   - idPrefix: prepended to every event id so overlay events stay
    ///     distinguishable from scraped ones (`"gcal-"`).
    ///   - source: the `EventSource` stamped on every event.
    /// - Returns: occurrences sorted by start, then title, then id. Empty when
    ///   the stream is unreadable or the range is empty.
    static func events(
        ics: String,
        from: Date,
        toExclusive: Date,
        zone: TimeZone = W4Dates.zone,
        idPrefix: String = SchoolCalendar.idPrefix,
        source: EventSource = .schoolCalendar
    ) -> [TimetableEvent] {
        let calendar = gregorian(in: zone)
        let rangeStart = calendar.startOfDay(for: from)
        let rangeEnd = calendar.startOfDay(for: toExclusive)

        guard rangeEnd > rangeStart else {
            warn("empty or inverted date range — no occurrences returned")
            return []
        }

        let blocks = vevents(in: ics)
        guard !blocks.isEmpty else { return [] }

        // Pass 1: RECURRENCE-ID overrides. An override replaces one instance of
        // its parent series, so the parent must not also emit that instance.
        var overrides: [String: Set<Date>] = [:]
        for block in blocks {
            guard let identifier = uid(in: block), !identifier.isEmpty,
                  let property = block["RECURRENCE-ID"]?.first,
                  let moment = temporal(property, zone: zone, calendar: calendar)
            else { continue }
            overrides[identifier, default: []].insert(moment.instant)
        }

        // Pass 2: expand.
        var out: [TimetableEvent] = []
        var seenIDs = Set<String>()

        for block in blocks {
            guard var parsed = event(from: block, zone: zone, calendar: calendar) else { continue }
            guard !parsed.isCancelled else { continue }

            if parsed.isSeriesMaster, let extra = overrides[parsed.uid], !extra.isEmpty {
                parsed.exceptions.formUnion(extra)
            }

            for occurrence in expand(parsed, rangeStart: rangeStart, rangeEnd: rangeEnd, calendar: calendar) {
                let mapped = timetableEvent(
                    occurrence,
                    of: parsed,
                    idPrefix: idPrefix,
                    source: source,
                    calendar: calendar
                )
                guard seenIDs.insert(mapped.id).inserted else { continue }
                out.append(mapped)
                if out.count >= Limits.totalOccurrences {
                    warn("occurrence cap reached — remaining events dropped")
                    return sorted(out)
                }
            }
        }

        return sorted(out)
    }

    /// The last day in `calendar`'s zone that `start…end` touches.
    ///
    /// An end that lands **exactly** on midnight is exclusive, which is the rule
    /// `parsers.md` §5 calls out: an all-day event `DTSTART:20260813` /
    /// `DTEND:20260816` covers 13, 14 and 15 August and **not** the 16th.
    /// Getting this wrong paints a phantom day in the UI.
    static func lastCoveredDay(start: Date, end: Date, calendar: Calendar) -> Date {
        let firstDay = calendar.startOfDay(for: start)
        guard end > start else { return firstDay }
        let endDay = calendar.startOfDay(for: end)
        if endDay == end, endDay > firstDay {
            return calendar.date(byAdding: .day, value: -1, to: endDay) ?? firstDay
        }
        return max(firstDay, endDay)
    }

    // MARK: - Content lines

    /// One unfolded `NAME;PARAM=value:value` content line.
    struct Property: Equatable {
        /// Upper-cased property name (`DTSTART`).
        let name: String
        /// Upper-cased parameter names, values verbatim with any quotes stripped.
        let params: [String: String]
        /// Raw value, still escaped.
        let value: String
    }

    /// RFC 5545 line unfolding: a line beginning with a single SP or HTAB is a
    /// continuation of the previous one, and that one character is dropped.
    /// Blank lines are discarded; `\r\n`, `\n` and a lone `\r` all terminate a line.
    ///
    /// The separator is matched with a predicate rather than
    /// `split(separator: "\n")` because **Swift treats CRLF as ONE `Character`**
    /// (it is a single extended grapheme cluster). Splitting a real, CRLF-lined
    /// feed on the character `"\n"` finds no separators at all and hands the
    /// whole calendar back as one line.
    static func unfold(_ ics: String) -> [String] {
        var out: [String] = []
        var buffer = ""
        var hasBuffer = false

        func flush() {
            if hasBuffer { out.append(buffer) }
            buffer = ""
            hasBuffer = false
        }

        let lines = ics.split(omittingEmptySubsequences: false) { character in
            character == "\n" || character == "\r\n" || character == "\r"
        }

        for rawLine in lines {
            var line = String(rawLine)
            if line.hasSuffix("\r") { line.removeLast() }

            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                if hasBuffer { buffer += String(line.dropFirst()) }
            } else {
                flush()
                if !line.isEmpty {
                    buffer = line
                    hasBuffer = true
                }
            }
        }
        flush()
        return out
    }

    /// Splits one content line. The colon and the parameter separators are found
    /// with a quote-aware scan, because RFC 5545 allows `;` and `:` inside a
    /// quoted parameter value (`TZID="GMT+02:00"`).
    static func property(from line: String) -> Property? {
        var inQuotes = false
        var colon: String.Index?
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character == "\"" {
                inQuotes.toggle()
            } else if character == ":" && !inQuotes {
                colon = index
                break
            }
            index = line.index(after: index)
        }

        guard let colon else { return nil }
        let head = String(line[line.startIndex..<colon])
        let value = String(line[line.index(after: colon)...])

        let pieces = splitOutsideQuotes(head, separator: ";")
        guard let name = pieces.first, !name.isEmpty else { return nil }

        var params: [String: String] = [:]
        for piece in pieces.dropFirst() {
            guard let equals = piece.firstIndex(of: "=") else {
                params[piece.uppercased()] = ""
                continue
            }
            let key = String(piece[piece.startIndex..<equals]).uppercased()
            var raw = String(piece[piece.index(after: equals)...])
            if raw.count >= 2, raw.hasPrefix("\""), raw.hasSuffix("\"") {
                raw = String(raw.dropFirst().dropLast())
            }
            params[key] = raw
        }

        return Property(name: name.uppercased(), params: params, value: value)
    }

    /// Every `VEVENT` in the stream, as name → properties in document order.
    ///
    /// Components nested inside a `VEVENT` (`VALARM`) are skipped wholesale, so
    /// an alarm's `DURATION` can never be mistaken for the event's.
    static func vevents(in ics: String) -> [[String: [Property]]] {
        var blocks: [[String: [Property]]] = []
        var current: [String: [Property]] = [:]
        var inEvent = false
        var nesting = 0

        for line in unfold(ics) {
            let upper = line.uppercased()

            if upper == "BEGIN:VEVENT" {
                if inEvent { warn("unterminated VEVENT — the earlier block was discarded") }
                current = [:]
                inEvent = true
                nesting = 0
                continue
            }

            if upper == "END:VEVENT" {
                if inEvent, !current.isEmpty { blocks.append(current) }
                current = [:]
                inEvent = false
                nesting = 0
                if blocks.count >= Limits.events {
                    warn("VEVENT cap reached — the rest of the stream was ignored")
                    return blocks
                }
                continue
            }

            guard inEvent else { continue }

            if upper.hasPrefix("BEGIN:") { nesting += 1; continue }
            if upper.hasPrefix("END:") { nesting = max(0, nesting - 1); continue }
            guard nesting == 0 else { continue }

            guard let parsed = property(from: line) else { continue }
            current[parsed.name, default: []].append(parsed)
        }

        if inEvent { warn("stream ended inside a VEVENT — the block was discarded") }
        return blocks
    }

    /// Undoes RFC 5545 text escaping: `\n`/`\N` become a newline, `\,` `\;` `\\`
    /// become the bare character, and any other `\x` collapses to `x`.
    static func unescape(_ value: String) -> String {
        guard value.contains("\\") else { return value }
        var out = ""
        out.reserveCapacity(value.count)
        var index = value.startIndex
        while index < value.endIndex {
            let character = value[index]
            guard character == "\\" else {
                out.append(character)
                index = value.index(after: index)
                continue
            }
            let next = value.index(after: index)
            guard next < value.endIndex else {
                out.append(character)
                break
            }
            switch value[next] {
            case "n", "N": out.append("\n")
            default: out.append(value[next])
            }
            index = value.index(after: next)
        }
        return out
    }

    // MARK: - Parsed event

    /// A `DTSTART`/`DTEND`/`EXDATE` value resolved to an absolute instant.
    private struct Temporal {
        let instant: Date
        let isAllDay: Bool
    }

    /// How long an occurrence lasts. All-day events are measured in **whole
    /// days** so a multi-day span stays correct across a DST change; timed
    /// events carry an optional whole-day part plus seconds for the same reason.
    private enum Span {
        case days(Int)
        case daysAndSeconds(Int, TimeInterval)
    }

    private enum Frequency {
        case daily, weekly, monthly, yearly
    }

    private struct RecurrenceRule {
        let frequency: Frequency
        /// Always ≥ 1; a missing or nonsense `INTERVAL` is clamped.
        let interval: Int
        let count: Int?
        let until: Date?
        /// `Calendar` weekday numbers (1 = Sunday … 7 = Saturday). Empty means
        /// "the weekday `DTSTART` falls on".
        let weekdays: [Int]
    }

    private struct ParsedEvent {
        let uid: String
        let title: String
        let location: String?
        let notes: String?
        let start: Date
        let isAllDay: Bool
        let span: Span
        let rule: RecurrenceRule?
        var exceptions: Set<Date>
        let isCancelled: Bool
        /// False for a `RECURRENCE-ID` override, which is a single replacement
        /// instance rather than the head of a series.
        let isSeriesMaster: Bool
    }

    private struct Occurrence {
        let start: Date
        let end: Date
    }

    private static func uid(in block: [String: [Property]]) -> String? {
        guard let raw = block["UID"]?.first?.value else { return nil }
        return unescape(raw).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func event(
        from block: [String: [Property]],
        zone: TimeZone,
        calendar: Calendar
    ) -> ParsedEvent? {
        guard let startProperty = block["DTSTART"]?.first,
              let start = temporal(startProperty, zone: zone, calendar: calendar) else {
            warn("VEVENT without a readable DTSTART — skipped")
            return nil
        }

        let title = unescape(block["SUMMARY"]?.first?.value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            warn("VEVENT without a SUMMARY — skipped")
            return nil
        }

        let eventSpan = span(for: start, block: block, zone: zone, calendar: calendar)

        let location = unescape(block["LOCATION"]?.first?.value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = stripHTML(unescape(block["DESCRIPTION"]?.first?.value ?? ""))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let statusValue = (block["STATUS"]?.first?.value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let isCancelled = statusValue.caseInsensitiveCompare("CANCELLED") == .orderedSame

        let rule = block["RRULE"]?.first
            .flatMap { recurrenceRule(from: $0.value, zone: zone, calendar: calendar) }

        let exdates = exceptions(block["EXDATE"] ?? [], zone: zone, calendar: calendar)

        // The UID falls back to the raw DTSTART so two summary-identical events
        // on different days still get different ids.
        var identifier = uid(in: block) ?? ""
        if identifier.isEmpty { identifier = startProperty.value }

        return ParsedEvent(
            uid: identifier,
            title: title,
            location: location.isEmpty ? nil : location,
            notes: notes.isEmpty ? nil : notes,
            start: start.instant,
            isAllDay: start.isAllDay,
            span: eventSpan,
            rule: rule,
            exceptions: exdates,
            isCancelled: isCancelled,
            isSeriesMaster: block["RECURRENCE-ID"] == nil
        )
    }

    /// `DTEND` wins; then `DURATION`; then the RFC default (one day for an
    /// all-day event, one hour otherwise).
    private static func span(
        for start: Temporal,
        block: [String: [Property]],
        zone: TimeZone,
        calendar: Calendar
    ) -> Span {
        if let endProperty = block["DTEND"]?.first,
           let end = temporal(endProperty, zone: zone, calendar: calendar) {
            if start.isAllDay {
                // The all-day DTEND is EXCLUSIVE, so the day difference IS the
                // number of days covered.
                let days = calendar.dateComponents(
                    [.day],
                    from: calendar.startOfDay(for: start.instant),
                    to: calendar.startOfDay(for: end.instant)
                ).day ?? 1
                return .days(max(1, days))
            }
            let seconds = end.instant.timeIntervalSince(start.instant)
            return .daysAndSeconds(0, seconds > 0 ? seconds : 3600)
        }

        if let duration = block["DURATION"]?.first?.value,
           let parsed = span(fromDuration: duration, isAllDay: start.isAllDay) {
            return parsed
        }

        return start.isAllDay ? .days(1) : .daysAndSeconds(0, 3600)
    }

    /// RFC 5545 `DURATION`: `P[n]W`, `P[n]D`, `PT[n]H[n]M[n]S` and combinations.
    /// A negative duration is treated as its magnitude — an event that ends
    /// before it starts is nonsense we render forwards rather than drop.
    private static func span(fromDuration raw: String, isAllDay: Bool) -> Span? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let parts = groups(
            in: text,
            pattern: #"^[+-]?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$"#,
            count: 5
        ) else {
            warn("unreadable DURATION — falling back to the default length")
            return nil
        }

        let weeks = Int(parts[0]) ?? 0
        let days = Int(parts[1]) ?? 0
        let hours = Int(parts[2]) ?? 0
        let minutes = Int(parts[3]) ?? 0
        let seconds = Int(parts[4]) ?? 0

        let wholeDays = weeks * 7 + days
        let timeSeconds = TimeInterval(hours * 3600 + minutes * 60 + seconds)

        if isAllDay {
            // An all-day event keeps day granularity; a stray time component
            // rounds up to a whole day rather than turning it into a timed slot.
            let total = wholeDays + (timeSeconds > 0 ? 1 : 0)
            return .days(max(1, total))
        }

        guard wholeDays > 0 || timeSeconds > 0 else { return nil }
        return .daysAndSeconds(wholeDays, timeSeconds)
    }

    private static func end(of start: Date, span: Span, calendar: Calendar) -> Date {
        switch span {
        case .days(let count):
            return calendar.date(byAdding: .day, value: count, to: start)
                ?? start.addingTimeInterval(TimeInterval(count) * 86_400)
        case .daysAndSeconds(let days, let seconds):
            let base: Date
            if days == 0 {
                base = start
            } else {
                base = calendar.date(byAdding: .day, value: days, to: start)
                    ?? start.addingTimeInterval(TimeInterval(days) * 86_400)
            }
            return base.addingTimeInterval(seconds)
        }
    }

    // MARK: - Temporal values

    private static func temporal(
        _ property: Property,
        zone: TimeZone,
        calendar: Calendar
    ) -> Temporal? {
        temporal(value: property.value, params: property.params, zone: zone, calendar: calendar)
    }

    private static func temporal(
        value rawValue: String,
        params: [String: String],
        zone: TimeZone,
        calendar: Calendar
    ) -> Temporal? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let fields = dateFields(in: value) else { return nil }

        let declaredDate = (params["VALUE"] ?? "")
            .caseInsensitiveCompare("DATE") == .orderedSame
        if declaredDate || !fields.hasTime {
            guard let midnight = instant(fields, in: zone, calendar: calendar, atMidnight: true) else {
                return nil
            }
            return Temporal(instant: calendar.startOfDay(for: midnight), isAllDay: true)
        }

        if fields.isUTC {
            guard let utc = TimeZone(secondsFromGMT: 0),
                  let moment = instant(fields, in: utc, calendar: calendar) else { return nil }
            return Temporal(instant: moment, isAllDay: false)
        }

        // No `Z` suffix: either an explicit TZID, or a floating time that W4
        // renders as Oslo wall clock (bug B21 — `zone` is honoured, never
        // hardcoded, and never `TimeZone.current`).
        var resolved = zone
        if let tzid = params["TZID"]?.trimmingCharacters(in: .whitespacesAndNewlines), !tzid.isEmpty {
            if let named = TimeZone(identifier: tzid) {
                resolved = named
            } else {
                warn("unknown TZID — reading the value in the requested zone instead")
            }
        }

        guard let moment = instant(fields, in: resolved, calendar: calendar) else { return nil }
        return Temporal(instant: moment, isAllDay: false)
    }

    private struct DateFields {
        let year: Int
        let month: Int
        let day: Int
        let hour: Int
        let minute: Int
        let second: Int
        let hasTime: Bool
        let isUTC: Bool
    }

    /// `yyyyMMdd`, `yyyyMMdd'T'HHmm[ss]` and the same with a trailing `Z`.
    /// Hand-rolled rather than `DateFormatter`-driven: the zone varies per value,
    /// and a fixed digit grammar cannot be dragged off course by a locale.
    private static func dateFields(in value: String) -> DateFields? {
        let characters = Array(value)

        func number(at start: Int, length: Int) -> Int? {
            guard start >= 0, start + length <= characters.count else { return nil }
            var result = 0
            for index in start..<(start + length) {
                let character = characters[index]
                guard character.isASCII, let digit = character.wholeNumberValue,
                      (0...9).contains(digit) else { return nil }
                result = result * 10 + digit
            }
            return result
        }

        guard characters.count >= 8,
              let year = number(at: 0, length: 4),
              let month = number(at: 4, length: 2),
              let day = number(at: 6, length: 2),
              (1...12).contains(month),
              (1...31).contains(day)
        else { return nil }

        if characters.count == 8 {
            return DateFields(
                year: year, month: month, day: day,
                hour: 0, minute: 0, second: 0,
                hasTime: false, isUTC: false
            )
        }

        guard characters.count >= 13,
              characters[8] == "T" || characters[8] == "t",
              let hour = number(at: 9, length: 2),
              let minute = number(at: 11, length: 2),
              hour <= 23, minute <= 59
        else { return nil }

        var second = 0
        var next = 13
        if characters.count >= 15, let parsed = number(at: 13, length: 2) {
            second = min(parsed, 59)
            next = 15
        }

        var isUTC = false
        if next < characters.count {
            let suffix = String(characters[next...]).uppercased()
            guard suffix == "Z" else { return nil }
            isUTC = true
        }

        return DateFields(
            year: year, month: month, day: day,
            hour: hour, minute: minute, second: second,
            hasTime: true, isUTC: isUTC
        )
    }

    private static func instant(
        _ fields: DateFields,
        in zone: TimeZone,
        calendar: Calendar,
        atMidnight: Bool = false
    ) -> Date? {
        var components = DateComponents()
        components.timeZone = zone
        components.year = fields.year
        components.month = fields.month
        components.day = fields.day
        components.hour = atMidnight ? 0 : fields.hour
        components.minute = atMidnight ? 0 : fields.minute
        components.second = atMidnight ? 0 : fields.second
        return calendar.date(from: components)
    }

    // MARK: - Recurrence

    private static func recurrenceRule(
        from raw: String,
        zone: TimeZone,
        calendar: Calendar
    ) -> RecurrenceRule? {
        var parts: [String: String] = [:]
        for piece in raw.split(separator: ";") {
            guard let equals = piece.firstIndex(of: "=") else { continue }
            let key = String(piece[piece.startIndex..<equals]).uppercased()
            let value = String(piece[piece.index(after: equals)...])
            parts[key] = value
        }

        let frequency: Frequency
        switch (parts["FREQ"] ?? "").uppercased() {
        case "DAILY": frequency = .daily
        case "WEEKLY": frequency = .weekly
        case "MONTHLY": frequency = .monthly
        case "YEARLY": frequency = .yearly
        default:
            // SECONDLY/MINUTELY/HOURLY and anything unparseable degrade to a
            // single occurrence. Inventing a frequency would invent lessons.
            warn("unsupported RRULE FREQ — the event renders once, at DTSTART")
            return nil
        }

        let interval = max(1, parts["INTERVAL"].flatMap { Int($0) } ?? 1)
        let count = parts["COUNT"].flatMap { Int($0) }.map { max(1, $0) }
        let until = parts["UNTIL"].flatMap { untilDate($0, zone: zone, calendar: calendar) }

        // BYDAY tokens may carry an ordinal (`2MO`, `-1SU`). The ordinal is not
        // supported; the weekday still is, which is the conservative reading.
        let weekdays = (parts["BYDAY"] ?? "")
            .split(separator: ",")
            .compactMap { token -> Int? in
                let code = String(token.suffix(2)).uppercased()
                return weekdayNumbers[code]
            }

        return RecurrenceRule(
            frequency: frequency,
            interval: interval,
            count: count,
            until: until,
            weekdays: weekdays
        )
    }

    /// `Calendar` weekday numbers: 1 = Sunday … 7 = Saturday.
    private static let weekdayNumbers: [String: Int] = [
        "SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7
    ]

    /// `UNTIL` is inclusive. A date-only `UNTIL` covers the whole of that day.
    private static func untilDate(_ raw: String, zone: TimeZone, calendar: Calendar) -> Date? {
        guard let parsed = temporal(value: raw, params: [:], zone: zone, calendar: calendar) else {
            warn("unreadable RRULE UNTIL — the series is bounded by the range instead")
            return nil
        }
        guard parsed.isAllDay else { return parsed.instant }
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: parsed.instant) else {
            return parsed.instant
        }
        return nextDay.addingTimeInterval(-1)
    }

    private static func exceptions(
        _ properties: [Property],
        zone: TimeZone,
        calendar: Calendar
    ) -> Set<Date> {
        var out: Set<Date> = []
        for property in properties {
            for token in property.value.split(separator: ",") {
                let raw = token.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty,
                      let parsed = temporal(
                        value: raw,
                        params: property.params,
                        zone: zone,
                        calendar: calendar
                      )
                else { continue }
                out.insert(parsed.instant)
                if out.count >= Limits.exceptions {
                    warn("EXDATE cap reached — later exclusions were ignored")
                    return out
                }
            }
        }
        return out
    }

    private static func isExcluded(_ start: Date, in exceptions: Set<Date>, calendar: Calendar) -> Bool {
        guard !exceptions.isEmpty else { return false }
        if exceptions.contains(start) { return true }
        return exceptions.contains(calendar.startOfDay(for: start))
    }

    // MARK: - Expansion

    private static func expand(
        _ event: ParsedEvent,
        rangeStart: Date,
        rangeEnd: Date,
        calendar: Calendar
    ) -> [Occurrence] {
        guard let rule = event.rule else {
            return occurrence(
                event,
                start: event.start,
                rangeStart: rangeStart,
                rangeEnd: rangeEnd,
                calendar: calendar
            ).map { [$0] } ?? []
        }

        var out: [Occurrence] = []
        var generated = 0
        var stop = false

        /// Applies UNTIL / COUNT / EXDATE to one candidate start.
        func consider(_ start: Date) {
            guard !stop else { return }
            // A BYDAY rule can generate candidates earlier in DTSTART's own week.
            guard start >= event.start else { return }
            if let until = rule.until, start > until {
                stop = true
                return
            }
            if let limit = rule.count, generated >= limit {
                stop = true
                return
            }
            // RFC 5545: COUNT bounds what the rule generates, EXDATE then
            // subtracts, so an excluded instance still consumes its slot.
            generated += 1
            guard !isExcluded(start, in: event.exceptions, calendar: calendar) else { return }
            if let found = occurrence(
                event,
                start: start,
                rangeStart: rangeStart,
                rangeEnd: rangeEnd,
                calendar: calendar
            ) {
                out.append(found)
                if out.count >= Limits.totalOccurrences { stop = true }
            }
        }

        // A counted rule must be walked from DTSTART, because COUNT includes it.
        // An uncounted rule may jump straight to the requested window.
        let walksFromStart = rule.count != nil

        switch rule.frequency {
        case .daily:
            let cap = walksFromStart
                ? min(rule.count ?? 0, Limits.countedOccurrences)
                : Limits.dailyIterations
            var cursor = walksFromStart
                ? event.start
                : skippingDays(from: event.start, to: rangeStart, interval: rule.interval, calendar: calendar)
            var iterations = 0
            while iterations < cap, !stop {
                iterations += 1
                consider(cursor)
                if stop { break }
                guard cursor < rangeEnd else { break }
                guard let next = calendar.date(byAdding: .day, value: rule.interval, to: cursor),
                      next > cursor else { break }
                cursor = next
            }

        case .weekly:
            let weekdays = rule.weekdays.isEmpty
                ? [calendar.component(.weekday, from: event.start)]
                : rule.weekdays
            let ordered = Array(Set(weekdays)).sorted { mondayIndex($0) < mondayIndex($1) }

            var weekStart = startOfWeek(containing: event.start, calendar: calendar)
            if !walksFromStart {
                weekStart = skippingWeeks(
                    from: weekStart,
                    to: rangeStart,
                    interval: rule.interval,
                    calendar: calendar
                )
            }

            let cap = walksFromStart
                ? min(rule.count ?? 0, Limits.countedOccurrences)
                : Limits.weeklyIterations
            var iterations = 0
            while iterations < cap, !stop {
                iterations += 1
                for weekday in ordered {
                    guard let candidate = date(
                        inWeekStartingAt: weekStart,
                        weekday: weekday,
                        timeOfDayOf: event.start,
                        calendar: calendar
                    ) else { continue }
                    consider(candidate)
                    if stop { break }
                }
                if stop { break }
                guard weekStart < rangeEnd else { break }
                guard let next = calendar.date(
                    byAdding: .day,
                    value: 7 * rule.interval,
                    to: weekStart
                ), next > weekStart else { break }
                weekStart = next
            }

        case .monthly:
            let cap = walksFromStart
                ? min(rule.count ?? 0, Limits.countedOccurrences)
                : Limits.monthlyIterations
            var cursor = walksFromStart
                ? event.start
                : skippingMonths(from: event.start, to: rangeStart, interval: rule.interval, calendar: calendar)
            var iterations = 0
            while iterations < cap, !stop {
                iterations += 1
                consider(cursor)
                if stop { break }
                guard cursor < rangeEnd else { break }
                guard let next = calendar.date(byAdding: .month, value: rule.interval, to: cursor),
                      next > cursor else { break }
                cursor = next
            }

        case .yearly:
            let cap = walksFromStart
                ? min(rule.count ?? 0, Limits.countedOccurrences)
                : Limits.yearlyIterations
            var cursor = walksFromStart
                ? event.start
                : skippingYears(from: event.start, to: rangeStart, interval: rule.interval, calendar: calendar)
            var iterations = 0
            while iterations < cap, !stop {
                iterations += 1
                consider(cursor)
                if stop { break }
                guard cursor < rangeEnd else { break }
                guard let next = calendar.date(byAdding: .year, value: rule.interval, to: cursor),
                      next > cursor else { break }
                cursor = next
            }
        }

        return out
    }

    private static func occurrence(
        _ event: ParsedEvent,
        start: Date,
        rangeStart: Date,
        rangeEnd: Date,
        calendar: Calendar
    ) -> Occurrence? {
        let finish = end(of: start, span: event.span, calendar: calendar)
        guard overlaps(
            start: start,
            end: finish,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            calendar: calendar
        ) else { return nil }
        return Occurrence(start: start, end: finish)
    }

    private static func overlaps(
        start: Date,
        end: Date,
        rangeStart: Date,
        rangeEnd: Date,
        calendar: Calendar
    ) -> Bool {
        guard calendar.startOfDay(for: start) < rangeEnd else { return false }
        return lastCoveredDay(start: start, end: end, calendar: calendar) >= rangeStart
    }

    // MARK: - Calendar arithmetic
    //
    // Every helper below runs in `calendar`, whose `timeZone` is the zone the
    // caller asked for. Adding days/weeks/months/years this way preserves the
    // wall-clock time of day across a DST boundary, which adding seconds does not.

    private static func gregorian(in zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.locale = W4Dates.locale
        calendar.firstWeekday = 2           // Monday
        calendar.minimumDaysInFirstWeek = 4 // ISO 8601
        return calendar
    }

    /// Monday 00:00 of the week containing `date`.
    private static func startOfWeek(containing date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day) // 1 = Sunday
        let offset = mondayIndex(weekday)
        guard offset > 0 else { return day }
        return calendar.date(byAdding: .day, value: -offset, to: day) ?? day
    }

    /// Monday = 0 … Sunday = 6, for a `Calendar` weekday number.
    private static func mondayIndex(_ weekday: Int) -> Int {
        ((weekday + 5) % 7 + 7) % 7
    }

    private static func date(
        inWeekStartingAt weekStart: Date,
        weekday: Int,
        timeOfDayOf reference: Date,
        calendar: Calendar
    ) -> Date? {
        guard let day = calendar.date(
            byAdding: .day,
            value: mondayIndex(weekday),
            to: weekStart
        ) else { return nil }
        return applyingTimeOfDay(of: reference, to: day, calendar: calendar)
    }

    private static func applyingTimeOfDay(
        of reference: Date,
        to day: Date,
        calendar: Calendar
    ) -> Date? {
        let time = calendar.dateComponents([.hour, .minute, .second], from: reference)
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = time.hour
        components.minute = time.minute
        components.second = time.second
        return calendar.date(from: components)
    }

    private static func skippingDays(
        from start: Date,
        to rangeStart: Date,
        interval: Int,
        calendar: Calendar
    ) -> Date {
        let fromDay = calendar.startOfDay(for: start)
        let toDay = calendar.startOfDay(for: rangeStart)
        guard toDay > fromDay,
              let days = calendar.dateComponents([.day], from: fromDay, to: toDay).day,
              days > 0
        else { return start }
        let steps = (days + interval - 1) / interval
        return calendar.date(byAdding: .day, value: steps * interval, to: start) ?? start
    }

    private static func skippingWeeks(
        from weekStart: Date,
        to rangeStart: Date,
        interval: Int,
        calendar: Calendar
    ) -> Date {
        let target = startOfWeek(containing: rangeStart, calendar: calendar)
        guard target > weekStart,
              let days = calendar.dateComponents([.day], from: weekStart, to: target).day,
              days >= 7
        else { return weekStart }
        let weeks = days / 7
        let steps = (weeks + interval - 1) / interval
        return calendar.date(byAdding: .day, value: steps * 7 * interval, to: weekStart) ?? weekStart
    }

    private static func skippingMonths(
        from start: Date,
        to rangeStart: Date,
        interval: Int,
        calendar: Calendar
    ) -> Date {
        guard let fromMonth = firstOfMonth(start, calendar: calendar),
              let toMonth = firstOfMonth(rangeStart, calendar: calendar),
              toMonth > fromMonth,
              let months = calendar.dateComponents([.month], from: fromMonth, to: toMonth).month,
              months > 0
        else { return start }
        let steps = (months + interval - 1) / interval
        return calendar.date(byAdding: .month, value: steps * interval, to: start) ?? start
    }

    private static func skippingYears(
        from start: Date,
        to rangeStart: Date,
        interval: Int,
        calendar: Calendar
    ) -> Date {
        let fromYear = calendar.component(.year, from: start)
        let toYear = calendar.component(.year, from: rangeStart)
        let years = toYear - fromYear
        guard years > 0 else { return start }
        let steps = (years + interval - 1) / interval
        return calendar.date(byAdding: .year, value: steps * interval, to: start) ?? start
    }

    private static func firstOfMonth(_ date: Date, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents([.year, .month], from: date)
        components.day = 1
        components.hour = 0
        components.minute = 0
        components.second = 0
        return calendar.date(from: components)
    }

    // MARK: - Output

    private static func timetableEvent(
        _ occurrence: Occurrence,
        of event: ParsedEvent,
        idPrefix: String,
        source: EventSource,
        calendar: Calendar
    ) -> TimetableEvent {
        TimetableEvent(
            id: "\(idPrefix)\(event.uid)/\(stamp(occurrence.start, calendar: calendar))",
            title: event.title,
            source: source,
            start: occurrence.start,
            end: occurrence.end,
            date: calendar.startOfDay(for: occurrence.start),
            room: event.location,
            status: .normal,
            isAllDay: event.isAllDay,
            notes: event.notes
        )
    }

    /// `yyyyMMdd'T'HHmmss` in the parse zone — stable, locale-free, and unique
    /// per occurrence of a series.
    private static func stamp(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )

        func padded(_ value: Int?, _ width: Int) -> String {
            let text = String(max(0, value ?? 0))
            guard text.count < width else { return text }
            return String(repeating: "0", count: width - text.count) + text
        }

        return padded(parts.year, 4)
            + padded(parts.month, 2)
            + padded(parts.day, 2)
            + "T"
            + padded(parts.hour, 2)
            + padded(parts.minute, 2)
            + padded(parts.second, 2)
    }

    private static func sorted(_ events: [TimetableEvent]) -> [TimetableEvent] {
        events.sorted { lhs, rhs in
            let left = lhs.start ?? lhs.date
            let right = rhs.start ?? rhs.date
            if left != right { return left < right }
            if lhs.title != rhs.title { return lhs.title < rhs.title }
            return lhs.id < rhs.id
        }
    }

    // MARK: - Text helpers

    private static func splitOutsideQuotes(_ text: String, separator: Character) -> [String] {
        var out: [String] = []
        var current = ""
        var inQuotes = false
        for character in text {
            if character == "\"" {
                inQuotes.toggle()
                current.append(character)
            } else if character == separator && !inQuotes {
                out.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        out.append(current)
        return out
    }

    /// Google puts HTML in `DESCRIPTION`; the UI renders plain text.
    private static func stripHTML(_ value: String) -> String {
        guard value.contains("<") || value.contains("&") else { return value }
        var text = replacing(#"(?i)<br\s*/?>"#, in: value, with: "\n")
        text = replacing("<[^>]+>", in: text, with: "")
        // `&amp;` goes last so `&amp;lt;` does not decode twice.
        for (entity, replacement) in [
            ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")
        ] {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return text
    }

    private static func replacing(_ pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: NSRange(text.startIndex..<text.endIndex, in: text),
            withTemplate: NSRegularExpression.escapedTemplate(for: replacement)
        )
    }

    /// Capture groups 1…`count`, with `""` for a group that did not participate,
    /// so the caller can index them positionally.
    private static func groups(in text: String, pattern: String, count: Int) -> [String]? {
        guard count >= 1,
              let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(
                in: text,
                options: [],
                range: NSRange(text.startIndex..<text.endIndex, in: text)
              ),
              match.numberOfRanges > count
        else { return nil }

        return (1...count).map { index -> String in
            guard let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
    }

    // MARK: - Logging

    /// Structural diagnostics only.
    ///
    /// The parameter is a `StaticString` on purpose: it can only ever be a
    /// literal, so no feed content — and above all no `academics/feeds`
    /// `token=` value — can be interpolated into a log line from here. Do not
    /// widen it to `String`.
    private static func warn(_ message: StaticString) {
        #if DEBUG
        print("⚠️ [ICSCalendarParser] \(message)")
        #endif
    }
}
