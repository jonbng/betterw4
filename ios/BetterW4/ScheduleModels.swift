//
//  ScheduleModels.swift
//  BetterW4
//
//  Created by Elliott Friedrich on 03/02/2026.
//

import Foundation

// MARK: - Schedule Models

struct ScheduleEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let startTime: String
    let endTime: String
    let teacher: String?
    let teacherId: String?
    let room: String?
    let status: EventStatus
    let date: Date
    let notes: String?
    let homework: String?
    let isAllDay: Bool

    init(
        id: String? = nil,
        title: String,
        subtitle: String,
        startTime: String,
        endTime: String,
        teacher: String? = nil,
        teacherId: String? = nil,
        room: String? = nil,
        status: EventStatus = .normal,
        date: Date,
        notes: String? = nil,
        homework: String? = nil,
        isAllDay: Bool = false
    ) {
        self.id = id ?? UUID().uuidString
        self.title = title
        self.subtitle = subtitle
        self.startTime = startTime
        self.endTime = endTime
        self.teacher = teacher
        self.teacherId = teacherId
        self.room = room
        self.status = status
        self.date = date
        self.notes = notes
        self.homework = homework
        self.isAllDay = isAllDay
    }
}

extension ScheduleEvent: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, title, subtitle, startTime, endTime, teacher, teacherId,
             room, status, date, notes, homework, isAllDay
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        subtitle = try c.decode(String.self, forKey: .subtitle)
        startTime = try c.decode(String.self, forKey: .startTime)
        endTime = try c.decode(String.self, forKey: .endTime)
        teacher = try c.decodeIfPresent(String.self, forKey: .teacher)
        teacherId = try c.decodeIfPresent(String.self, forKey: .teacherId)
        room = try c.decodeIfPresent(String.self, forKey: .room)
        status = try c.decode(EventStatus.self, forKey: .status)
        date = try c.decode(Date.self, forKey: .date)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        homework = try c.decodeIfPresent(String.self, forKey: .homework)
        isAllDay = (try? c.decode(Bool.self, forKey: .isAllDay)) ?? false
    }
}

enum EventStatus: String, Codable {
    case normal
    case cancelled
    case moved
    case changed

    var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .cancelled: return "Cancelled"
        case .moved: return "Moved"
        case .changed: return "Changed"
        }
    }
}

// MARK: - Lesson Content Models

struct LessonContent: Codable, Equatable {
    let teacherNote: String?
    let items: [LessonContentItem]

    var homework: [LessonContentItem] {
        items.filter { $0.isHomework }
    }

    var otherContent: [LessonContentItem] {
        items.filter { !$0.isHomework }
    }

    static let empty = LessonContent(teacherNote: nil, items: [])
}

struct LessonContentItem: Equatable, Identifiable {
    let id: String
    let title: String?
    let note: String?
    let blocks: [ContentBlock]
    let links: [LessonLink]
    let isHomework: Bool

    init(id: String, title: String?, note: String?, blocks: [ContentBlock],
         links: [LessonLink], isHomework: Bool) {
        self.id = id
        self.title = title
        self.note = note
        self.blocks = blocks
        self.links = links
        self.isHomework = isHomework
    }
}

extension LessonContentItem: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, title, note, blocks, links, isHomework
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(note, forKey: .note)
        try c.encode(blocks, forKey: .blocks)
        try c.encode(links, forKey: .links)
        try c.encode(isHomework, forKey: .isHomework)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        // Backward compat: old cached JSON has `body: String?` but no `blocks`
        blocks = (try? c.decode([ContentBlock].self, forKey: .blocks)) ?? []
        links = (try? c.decode([LessonLink].self, forKey: .links)) ?? []
        isHomework = (try? c.decode(Bool.self, forKey: .isHomework)) ?? true
    }
}

struct LessonLink: Codable, Equatable {
    let title: String
    let url: String
    let type: LessonLinkType
}

enum LessonLinkType: String, Codable {
    case file
    case external
}

// MARK: - Rich Content Blocks

enum InlineElement: Equatable {
    case text(String)
    case link(text: String, url: String, type: LessonLinkType)
    case image(url: String, alt: String)
}

extension InlineElement: Codable {
    private enum CodingKeys: String, CodingKey { case type, text, url, linkType, alt }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let s):
            try c.encode("text", forKey: .type)
            try c.encode(s, forKey: .text)
        case .link(let text, let url, let linkType):
            try c.encode("link", forKey: .type)
            try c.encode(text, forKey: .text)
            try c.encode(url, forKey: .url)
            try c.encode(linkType, forKey: .linkType)
        case .image(let url, let alt):
            try c.encode("image", forKey: .type)
            try c.encode(url, forKey: .url)
            try c.encode(alt, forKey: .alt)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try c.decode(String.self, forKey: .text))
        case "link":
            let linkTypeRaw = try c.decode(String.self, forKey: .linkType)
            let linkType = LessonLinkType(rawValue: linkTypeRaw) ?? .external
            self = .link(
                text: try c.decode(String.self, forKey: .text),
                url: try c.decode(String.self, forKey: .url),
                type: linkType
            )
        case "image":
            self = .image(
                url: try c.decode(String.self, forKey: .url),
                alt: (try? c.decode(String.self, forKey: .alt)) ?? ""
            )
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c,
                debugDescription: "Unknown InlineElement type: \(type)")
        }
    }
}

enum ContentBlock: Equatable {
    case heading(level: Int, inlines: [InlineElement])
    case paragraph(inlines: [InlineElement])
    case image(url: String, alt: String)
    case divider
}

extension ContentBlock: Codable {
    private enum CodingKeys: String, CodingKey { case type, level, inlines, url, alt }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .heading(let level, let inlines):
            try c.encode("heading", forKey: .type)
            try c.encode(level, forKey: .level)
            try c.encode(inlines, forKey: .inlines)
        case .paragraph(let inlines):
            try c.encode("paragraph", forKey: .type)
            try c.encode(inlines, forKey: .inlines)
        case .image(let url, let alt):
            try c.encode("image", forKey: .type)
            try c.encode(url, forKey: .url)
            try c.encode(alt, forKey: .alt)
        case .divider:
            try c.encode("divider", forKey: .type)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "heading":
            self = .heading(
                level: try c.decode(Int.self, forKey: .level),
                inlines: try c.decode([InlineElement].self, forKey: .inlines)
            )
        case "paragraph":
            self = .paragraph(inlines: try c.decode([InlineElement].self, forKey: .inlines))
        case "image":
            self = .image(
                url: try c.decode(String.self, forKey: .url),
                alt: (try? c.decode(String.self, forKey: .alt)) ?? ""
            )
        case "divider":
            self = .divider
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c,
                debugDescription: "Unknown ContentBlock type: \(type)")
        }
    }
}

// MARK: - W4 timetable domain models (port plan Wave 4, item 4.1)
//
// These are the models `W4TimetableParser` produces and the models the W4 UI
// will consume from Wave 6 on. They are ADDITIVE: the Lectio-era
// `ScheduleEvent` above still has ~14 callers (ScheduleStore, ScheduleView,
// ScheduleViewModel, DemoDataProvider, …) which no item in this wave owns, so
// it is left exactly as it is and will be deleted once its last caller is
// ported. The new event type is therefore called `TimetableEvent` rather than
// `ScheduleEvent`; renaming it back is a mechanical find-and-replace once the
// legacy type is gone.
//
// Naming follows plan D-5 (domain models are unprefixed) and D-6/D-8/D-9:
//
//   D-6  `EventSource { academics, extraAcademics, schoolCalendar, local }`
//   D-8  the event field set is `features.md`'s spelling (`subject`,
//        `teacherUwcId`, `href`, `notes`) plus `attendance` and `rawTooltip`
//        from `parsers.md`.
//   D-9  event ids are source-prefixed ("ac-w4-42"), because AC class 42 and
//        EA group 42 genuinely collide once the two timetables are merged.
//   D-10 there is deliberately no `nowMinutesFromStart` stored property: the
//        captured `#current_time` offset was written by JavaScript in the
//        browser before the page was saved, so parsing it would pin the
//        now-line to 13:34 forever. It is computed from the clock instead.
//
// `EventStatus` above is reused as-is; the W4 parser only ever produces
// `.normal`, `.changed` and `.cancelled` (`.moved` is Lectio-only).

/// Which W4 timetable (or overlay) an event came from.
///
/// The raw values are persisted, so they must stay stable.
enum EventSource: String, Codable, Equatable, Sendable, CaseIterable {
    case academics
    case extraAcademics
    case schoolCalendar
    case local

    /// Prefix used to keep event ids unique across sources (plan D-9,
    /// `parsers.md` bug B20). Without it an Academics class and an Extra
    /// Academics group that share a numeric id collapse into one event when
    /// the two weeks are merged.
    var idPrefix: String {
        switch self {
        case .academics: return "ac"
        case .extraAcademics: return "ea"
        case .schoolCalendar: return "cal"
        case .local: return "local"
        }
    }

    /// Matches the W4 main-menu labels.
    var displayName: String {
        switch self {
        case .academics: return "Academics"
        case .extraAcademics: return "Extra Academics"
        case .schoolCalendar: return "School Calendar"
        case .local: return "On This Device"
        }
    }
}

/// Attendance marker rendered inside a lesson block.
///
/// Live absence-week captures prove `.absence.not-checked` with a `?` badge.
/// The remaining class names come from W4's own `display_full_timetable.css`.
/// Always optional; `nil` means the block carried no attendance marker.
enum LessonAttendance: String, Codable, Equatable, Sendable {
    /// `.absence.not-checked` with a `?` badge — not yet marked.
    case unchecked
    /// `.present` — green in W4's own stylesheet.
    case present
    /// `.normal` (unexcused, red) or a bare `.absence` marker.
    case absent
    /// `.prearranged` — blue in W4's own stylesheet.
    case prearranged
    case unknown

    var displayName: String {
        switch self {
        case .unchecked: return "Not marked"
        case .present: return "Present"
        case .absent: return "Absent"
        case .prearranged: return "Prearranged"
        case .unknown: return "Unknown"
        }
    }
}

/// One lesson block from a W4 `#timetable` grid.
///
/// Everything except `id`, `title`, `date` and `source` is optional on purpose:
/// no real `.period` element has ever been captured, so a parser that insists
/// on a room or a time range would return nothing the first time W4 surprises
/// us. Times are Oslo wall-clock instants built with `W4Dates`.
struct TimetableEvent: Identifiable, Codable, Equatable, Sendable {
    /// Source-prefixed: `"ac-w4-42"` when the block links a numeric id,
    /// `"ac-2026-08-10-0"` otherwise (plan D-9).
    let id: String
    /// Human title of the block, with the datetime/room/attendance chrome removed.
    let title: String
    /// Canonical-ish label used for colour and rename lookups. Equal to `title`
    /// unless the block carries a separate subject label.
    let subject: String
    let source: EventSource
    /// Start instant, Oslo. `nil` for an all-day or unplaceable block.
    let start: Date?
    /// End instant, Oslo. `nil` for an all-day or unplaceable block.
    let end: Date?
    /// Start of the Oslo day this block renders on.
    let date: Date
    let room: String?
    let teacher: String?
    /// `nc\d{2}[a-z]+`, taken from a staff/student profile link inside the block.
    let teacherUwcId: String?
    let status: EventStatus
    let attendance: LessonAttendance?
    /// Badge text inside W4's attendance node, retained verbatim (for example `?`).
    let attendanceLabel: String?
    /// Final parenthetical attendance phrase in W4's tooltip (for example `no absence`).
    let attendanceTooltip: String?
    let isAllDay: Bool
    /// `href` of the first anchor inside the block, verbatim.
    let href: String?
    let notes: String?
    /// The raw `title` attribute of `div.period` (`parsers.md` bug B3).
    ///
    /// `UWCRCN W4.html:279` proves every block carries one — jQuery's tooltip
    /// plugin reads `$(this).prop('title')`. It is the likeliest home of
    /// teacher, full subject name and change notes, so it is captured raw and
    /// left unparsed until a term-time capture tells us its shape.
    let rawTooltip: String?

    init(
        id: String,
        title: String,
        subject: String? = nil,
        source: EventSource,
        start: Date? = nil,
        end: Date? = nil,
        date: Date,
        room: String? = nil,
        teacher: String? = nil,
        teacherUwcId: String? = nil,
        status: EventStatus = .normal,
        attendance: LessonAttendance? = nil,
        attendanceLabel: String? = nil,
        attendanceTooltip: String? = nil,
        isAllDay: Bool = false,
        href: String? = nil,
        notes: String? = nil,
        rawTooltip: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subject = subject ?? title
        self.source = source
        self.start = start
        self.end = end
        self.date = date
        self.room = room
        self.teacher = teacher
        self.teacherUwcId = teacherUwcId
        self.status = status
        self.attendance = attendance
        self.attendanceLabel = attendanceLabel
        self.attendanceTooltip = attendanceTooltip
        self.isAllDay = isAllDay
        self.href = href
        self.notes = notes
        self.rawTooltip = rawTooltip
    }

    /// Minutes from Oslo midnight, or `nil` when the block has no start time.
    var startMinutesFromMidnight: Int? {
        start.map(W4Dates.minutesFromMidnight)
    }

    /// Minutes from Oslo midnight, or `nil` when the block has no end time.
    var endMinutesFromMidnight: Int? {
        end.map(W4Dates.minutesFromMidnight)
    }

    /// `08:00 – 09:00`, or `nil` when the block is all-day/unplaceable.
    var timeRangeText: String? {
        guard let start, let end else { return nil }
        return "\(W4Dates.formatTime(start))\u{2013}\(W4Dates.formatTime(end))"
    }
}

/// One day column of a W4 week grid.
struct ScheduleDay: Identifiable, Codable, Equatable, Sendable {
    var id: Date { date }

    /// Start of the Oslo day, read from the header `dd-MMM-yyyy` cell
    /// (`parsers.md` bug B5 — the header is the truth, never an index offset
    /// from an assumed Monday).
    let date: Date
    /// `"Monday"` … `"Sunday"`, from `.day-name`.
    let dayName: String
    /// `"Day 1"` … `"Day 5"`, or `"Weekend"`.
    let rotationDay: String?
    /// True when the rotation-day element carries the `no-classes` **class**
    /// (`parsers.md` bug B4 — it is a class, not the literal text "No-Classes").
    let isNoClasses: Bool
    /// The Extra Academics line from the header cell; `"No EA"` when empty.
    let eaNote: String?
    /// True when the day column carried `column current`, i.e. W4 rendered this
    /// page on that day. Prefer comparing `date` against the clock for a live
    /// "today" check — a cached page keeps a stale `current` column.
    let isToday: Bool
    let events: [TimetableEvent]

    init(
        date: Date,
        dayName: String = "",
        rotationDay: String? = nil,
        isNoClasses: Bool = false,
        eaNote: String? = nil,
        isToday: Bool = false,
        events: [TimetableEvent] = []
    ) {
        self.date = date
        self.dayName = dayName
        self.rotationDay = rotationDay
        self.isNoClasses = isNoClasses
        self.eaNote = eaNote
        self.isToday = isToday
        self.events = events
    }

    /// True when W4 rendered a weekend or holiday marker for this day.
    var isWeekend: Bool {
        rotationDay?.caseInsensitiveCompare("Weekend") == .orderedSame
    }

    func withEvents(_ events: [TimetableEvent]) -> ScheduleDay {
        ScheduleDay(
            date: date,
            dayName: dayName,
            rotationDay: rotationDay,
            isNoClasses: isNoClasses,
            eaNote: eaNote,
            isToday: isToday,
            events: events
        )
    }
}

/// A whole W4 week grid: seven Monday-first days plus the grid's hour bounds.
struct ScheduleWeek: Codable, Equatable, Sendable {
    /// ISO week-year, derived from `days.first?.date` (bug B5).
    let year: Int
    /// ISO week number, derived from `days.first?.date` (bug B5).
    let week: Int
    /// The grid heading verbatim, e.g. `"August 2026, week 33"`.
    let title: String?
    /// The source this grid was fetched from; a merge keeps the primary's.
    let source: EventSource
    /// `tt_start_hour` from the page script; 7 in every capture we have.
    let startHour: Int
    /// `tt_end_hour` from the page script; 22 in every capture we have.
    let endHour: Int
    /// Always Monday-first, and always as many entries as the grid had header
    /// dates — seven on every capture, but never assumed.
    let days: [ScheduleDay]
    /// Set by the repository that fetched the page, not by the parser: parsers
    /// are pure and must not read a clock.
    let fetchedAt: Date?

    init(
        year: Int,
        week: Int,
        title: String? = nil,
        source: EventSource,
        startHour: Int = W4TimetableGeometry.defaultStartHour,
        endHour: Int = W4TimetableGeometry.defaultEndHour,
        days: [ScheduleDay] = [],
        fetchedAt: Date? = nil
    ) {
        self.year = year
        self.week = week
        self.title = title
        self.source = source
        self.startHour = startHour
        self.endHour = endHour
        self.days = days
        self.fetchedAt = fetchedAt
    }

    /// The honest empty result: no days, no events, default hour bounds.
    static func empty(source: EventSource) -> ScheduleWeek {
        ScheduleWeek(year: 0, week: 0, title: nil, source: source)
    }

    var allEvents: [TimetableEvent] {
        days.flatMap(\.events)
    }

    var hasEvents: Bool {
        days.contains { !$0.events.isEmpty }
    }

    /// `7...21` for the captured grid: one row per hour label.
    var hourLabels: [Int] {
        guard endHour > startHour else { return [] }
        return Array(startHour..<endHour)
    }

    /// Total minutes the grid spans, i.e. its pixel height (1 px == 1 minute).
    var minuteSpan: Int {
        max(0, (endHour - startHour) * 60)
    }

    func day(on date: Date) -> ScheduleDay? {
        days.first { W4Dates.isSameDay($0.date, date) }
    }

    /// Minutes from `startHour:00` to `now`, for drawing the now-line
    /// (plan D-10). Returns `nil` when `now` is not inside this week or falls
    /// outside the grid's hour bounds, so the caller simply draws nothing.
    ///
    /// Callers pass `TimeProvider.now`; it is a parameter rather than a default
    /// so that this stays a pure function of its inputs.
    func nowMinutesFromStart(now: Date) -> Int? {
        guard day(on: now) != nil else { return nil }
        let minutes = W4Dates.minutesFromMidnight(now) - startHour * 60
        guard minutes >= 0, minutes <= minuteSpan else { return nil }
        return minutes
    }

    /// Index of the day containing `now`, or `nil` when the week does not.
    func todayIndex(now: Date) -> Int? {
        days.firstIndex { W4Dates.isSameDay($0.date, now) }
    }

    func withDays(_ days: [ScheduleDay]) -> ScheduleWeek {
        ScheduleWeek(
            year: year,
            week: week,
            title: title,
            source: source,
            startHour: startHour,
            endHour: endHour,
            days: days,
            fetchedAt: fetchedAt
        )
    }

    func withFetchedAt(_ date: Date?) -> ScheduleWeek {
        ScheduleWeek(
            year: year,
            week: week,
            title: title,
            source: source,
            startHour: startHour,
            endHour: endHour,
            days: days,
            fetchedAt: date
        )
    }
}

// MARK: - Schedule Data

struct ScheduleData: Codable {
    let studentId: String
    let events: [ScheduleEvent]
    let lastUpdated: Date

    var eventsByDate: [Date: [ScheduleEvent]] {
        Dictionary(grouping: events) { event in
            Calendar.current.startOfDay(for: event.date)
        }
    }
}
