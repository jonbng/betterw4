//
//  SchoolCalendar.swift
//  BetterW4
//
//  W4 port plan Wave 4, item 4.11 — identity, overlay geometry and feed
//  hygiene for the iCalendar layer. Spec: docs/spec/parsers.md §5;
//  docs/spec/features.md §1.2 and §1.14; open question OQ-8.
//
//  Two separate things live here, and they are only cousins:
//
//    1. `SchoolCalendar` — the college-wide, public Google Calendar the W4 Home
//       page embeds, plus the pure functions that lay its events over a
//       `ScheduleWeek`.
//    2. `PersonalFeedKind` / `PersonalFeed` — the per-user `academics/feeds`
//       URLs. **Their `token=` query value is password-equivalent** (README
//       §4.8): Keychain only, never `UserDefaults`, never a log line, never a
//       fixture. `PersonalFeed` therefore prints itself redacted, so even an
//       accidental `print(feed)` cannot leak one.
//
//  EVIDENCE — read before trusting the calendar id.
//
//    `references/pages/UWCRCN W4.html:255` **[V]** shows Home rendering
//    `<div id="calendar"><iframe … src="./UWCRCN W4_files/embed.html"></iframe>`,
//    i.e. the page really does embed a calendar. The *saved copy* of that iframe
//    is an empty `about:blank` document, so the `src` the server actually sends
//    has never been observed. `calendarID` / `icsURLString` below are inherited
//    from `android/.../schedule/SchoolCalendar.kt:17-19` — **[I], not verified**.
//    That is open question OQ-8, and it is why the overlay ships **off by
//    default** with a Settings toggle rather than fetching on first launch.
//
//  Everything in this file is pure and synchronous. Nothing fetches, nothing
//  caches, nothing reads a clock; the TTL constant is a number for a later
//  wave's repository to honour, not a timer.
//

import Foundation

// MARK: - SchoolCalendar

/// The public UWCRCN college calendar and the geometry for overlaying it.
enum SchoolCalendar {

    /// **[I] — OQ-8.** Inherited from the Android port; the Home iframe `src`
    /// that would confirm it has never been captured.
    static let calendarID = "calendar@uwcrcn.no"

    /// **[I] — OQ-8.** Public feed, no auth, no token. Safe to log; the
    /// `academics/feeds` URLs are not (see `PersonalFeed`).
    static let icsURLString =
        "https://calendar.google.com/calendar/ical/calendar%40uwcrcn.no/public/basic.ics"

    static let icsURL: URL? = URL(string: icsURLString)

    /// Prefixed onto every overlay event id so a Google event can never be
    /// mistaken for a scraped W4 lesson (`parsers.md` §5, plan D-9).
    static let idPrefix = "gcal-"

    /// How long a fetched feed stays fresh, mirroring
    /// `SchoolCalendarRepository.CACHE_TTL_MS` (features.md §5). Six hours: the
    /// college calendar changes a handful of times a term.
    static let cacheTTL: TimeInterval = 6 * 60 * 60

    /// The overlay is opt-in until OQ-8 is closed by a real capture of the Home
    /// iframe `src`. Shipping it on by default would mean every launch hits
    /// `calendar.google.com` for a calendar we are not certain is the right one.
    static let isEnabledByDefault = false

    /// True when `event` came from the school-calendar overlay rather than from
    /// a scraped W4 timetable.
    static func isSchoolCalendarEvent(_ event: TimetableEvent) -> Bool {
        if event.source == .schoolCalendar { return true }
        return event.id.lowercased().hasPrefix(idPrefix.lowercased())
    }

    /// Drops college-calendar overlay events when the student has hidden them.
    static func visibleEvents(
        _ events: [TimetableEvent],
        showSchoolCalendar: Bool
    ) -> [TimetableEvent] {
        guard !showSchoolCalendar else { return events }
        return events.filter { !isSchoolCalendarEvent($0) }
    }

    /// Every occurrence inside ISO week `week` of `week-year`, Monday to Sunday.
    ///
    /// The week is anchored in Europe/Oslo because W4's own week numbering is
    /// (`parsers.md` §0.1). Returns `[]` when the week does not exist.
    static func events(ics: String, year: Int, week: Int) -> [TimetableEvent] {
        guard let monday = W4Dates.startOfISOWeek(year: year, week: week) else {
            return []
        }
        return ICSCalendarParser.events(
            ics: ics,
            from: monday,
            toExclusive: W4Dates.adding(days: 7, to: monday)
        )
    }

    // MARK: Overlay

    /// Largest number of day-slices one multi-day event may produce. A feed that
    /// claims a five-year "event" must not paint 1 800 rows.
    static let maximumSpannedDays = 366

    /// Splits an event into one entry per Oslo day it touches.
    ///
    /// A single-day event comes back unchanged. A multi-day one comes back as
    /// several, each clamped to its own day, and each day that is covered end to
    /// end is promoted to all-day. The final day is governed by the exclusive
    /// midnight rule (`ICSCalendarParser.lastCoveredDay`): 13-Aug → 16-Aug
    /// yields 13, 14 and 15 — never 16.
    ///
    /// Slice ids are the source id plus `#dd-MMM-yyyy`, so they stay stable
    /// across refreshes and distinct between days.
    static func expandAcrossDays(_ event: TimetableEvent) -> [TimetableEvent] {
        let calendar = W4Dates.calendar
        guard let start = event.start else { return [event] }
        let end = event.end ?? start

        let firstDay = W4Dates.startOfDay(start)
        let lastDay = ICSCalendarParser.lastCoveredDay(start: start, end: end, calendar: calendar)
        guard lastDay > firstDay else { return [event] }

        var out: [TimetableEvent] = []
        var day = firstDay
        var guardCount = 0

        while day <= lastDay, guardCount < maximumSpannedDays {
            guardCount += 1
            let nextDay = W4Dates.adding(days: 1, to: day)
            let sliceStart = max(start, day)
            let sliceEnd = min(end, nextDay)
            let coversWholeDay = sliceStart <= day && sliceEnd >= nextDay

            out.append(
                TimetableEvent(
                    id: "\(event.id)#\(W4Dates.format(day))",
                    title: event.title,
                    subject: event.subject,
                    source: event.source,
                    start: sliceStart,
                    end: sliceEnd,
                    date: day,
                    room: event.room,
                    teacher: event.teacher,
                    teacherUwcId: event.teacherUwcId,
                    status: event.status,
                    attendance: event.attendance,
                    isAllDay: event.isAllDay || coversWholeDay,
                    href: event.href,
                    notes: event.notes,
                    rawTooltip: event.rawTooltip
                )
            )

            guard nextDay > day else { break }
            day = nextDay
        }

        return out
    }

    /// Lays `extra` over `week`, matching on the Oslo day.
    ///
    /// Days the grid never rendered are appended rather than dropped: a W4
    /// timetable that only returns weekdays would otherwise silently swallow a
    /// Saturday college event. Days are re-sorted by date, and each day's events
    /// by all-day-first then start time.
    ///
    /// Pure: it does not consult the clock and does not fabricate days that have
    /// no events, so overlaying an empty array is the identity.
    static func overlay(_ week: ScheduleWeek, with extra: [TimetableEvent]) -> ScheduleWeek {
        guard !extra.isEmpty else { return week }

        let expanded = extra.flatMap(expandAcrossDays(_:))
        var byDay = Dictionary(grouping: expanded) { W4Dates.startOfDay($0.date) }

        var days = week.days.map { day -> ScheduleDay in
            let key = W4Dates.startOfDay(day.date)
            guard let more = byDay.removeValue(forKey: key), !more.isEmpty else { return day }
            return day.withEvents(sortedForDay(day.events + more))
        }

        for (date, events) in byDay.sorted(by: { $0.key < $1.key }) {
            days.append(
                ScheduleDay(
                    date: date,
                    dayName: W4Dates.weekdayName(of: date),
                    events: sortedForDay(events)
                )
            )
        }

        days.sort { $0.date < $1.date }
        return week.withDays(days)
    }

    /// All-day blocks first (they render as a banner above the grid), then by
    /// start time, then by title so the order is deterministic.
    static func sortedForDay(_ events: [TimetableEvent]) -> [TimetableEvent] {
        events.sorted { lhs, rhs in
            if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
            switch (lhs.start, rhs.start) {
            case let (left?, right?):
                if left != right { return left < right }
            case (nil, _?):
                return true
            case (_?, nil):
                return false
            case (nil, nil):
                break
            }
            if lhs.title != rhs.title { return lhs.title < rhs.title }
            return lhs.id < rhs.id
        }
    }
}

// MARK: - Personal feeds

/// The eight per-user feeds `academics/feeds` lists (README §4.8).
///
/// **[U] — never captured.** The page itself has not been fetched; the route
/// slugs come from the README's reading of the live navigation.
enum PersonalFeedKind: String, Codable, CaseIterable, Equatable, Sendable {
    case acTimetableRSS
    case eaTimetableRSS
    case combinedRSS
    case assessmentsRSS
    case acTimetableICS
    case eaTimetableICS
    case combinedICS
    case assessmentsICS

    /// The `academics/feeds/<slug>` suffix W4 uses.
    var slug: String {
        switch self {
        case .acTimetableRSS: return "acttrss"
        case .eaTimetableRSS: return "eattrss"
        case .combinedRSS: return "combottrss"
        case .assessmentsRSS: return "sassttrss"
        case .acTimetableICS: return "acttical"
        case .eaTimetableICS: return "eattical"
        case .combinedICS: return "combottical"
        case .assessmentsICS: return "sassttical"
        }
    }

    /// The Yii `r=` route, e.g. `academics/feeds/acttical`.
    var route: String {
        "\(W4Routes.R.feeds)/\(slug)"
    }

    /// True for the four iCalendar variants — the ones `ICSCalendarParser` can read.
    var isCalendar: Bool {
        switch self {
        case .acTimetableICS, .eaTimetableICS, .combinedICS, .assessmentsICS:
            return true
        case .acTimetableRSS, .eaTimetableRSS, .combinedRSS, .assessmentsRSS:
            return false
        }
    }

    var displayName: String {
        switch self {
        case .acTimetableRSS: return "Academics timetable (RSS)"
        case .eaTimetableRSS: return "Extra Academics timetable (RSS)"
        case .combinedRSS: return "Combined timetable (RSS)"
        case .assessmentsRSS: return "Assessments (RSS)"
        case .acTimetableICS: return "Academics timetable (calendar)"
        case .eaTimetableICS: return "Extra Academics timetable (calendar)"
        case .combinedICS: return "Combined timetable (calendar)"
        case .assessmentsICS: return "Assessments (calendar)"
        }
    }
}

/// One personal feed URL, **including its secret**.
///
/// The `token=` query value authenticates the owner to an otherwise
/// unauthenticated endpoint, so it is password-equivalent. Rules, and they are
/// not negotiable:
///
///   * store only in the Keychain — `Codable` conformance exists for that, not
///     for `UserDefaults` or a cache file;
///   * never render it in full (`ui.md`: the Settings row masks it as `••••`);
///   * never log it. `description` and `debugDescription` are overridden to the
///     redacted form precisely so a stray `print(feed)` or `"\(feed)"` in a
///     future wave cannot leak one.
struct PersonalFeed: Identifiable, Codable, Equatable, Sendable {
    var id: String { kind.rawValue }
    let kind: PersonalFeedKind
    /// Carries the secret. Pass it to the system ("Add to Calendar"); do not
    /// print it, do not put it in an analytics event, do not put it in a bug
    /// report.
    let url: URL

    init(kind: PersonalFeedKind, url: URL) {
        self.kind = kind
        self.url = url
    }

    /// The URL with every secret-bearing component replaced by ``redactionMarker``,
    /// safe to show a human and safe to log.
    var redactedURLText: String {
        PersonalFeed.redacted(url)
    }

    /// Deliberately ASCII: `URLComponents` percent-encodes anything else, and a
    /// redaction that reads `%E2%80%A2%E2%80%A2` helps nobody. The Settings row
    /// renders its own `••••` mask on top of this (`ui.md`).
    static let redactionMarker = "REDACTED"

    /// Query keys whose values are secrets. `token` is the one W4 uses; the
    /// others are here so a future feed shape cannot quietly slip past.
    private static let secretQueryKeys: Set<String> = [
        "token", "key", "secret", "auth", "password", "pass", "sig", "signature", "magic"
    ]

    /// Redacts a feed URL: any secret query value, any embedded credentials, and
    /// Google's `/private-<key>/` path segment.
    static func redacted(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return redactionMarker
        }

        // Password first: `URLComponents` will not render a password without a user.
        components.password = nil
        components.user = nil

        components.path = components.path
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { segment -> String in
                segment.lowercased().hasPrefix("private-")
                    ? "private-\(redactionMarker)"
                    : String(segment)
            }
            .joined(separator: "/")

        if let items = components.queryItems {
            components.queryItems = items.map { item -> URLQueryItem in
                guard secretQueryKeys.contains(item.name.lowercased()) else { return item }
                return URLQueryItem(name: item.name, value: redactionMarker)
            }
        }

        return components.string ?? redactionMarker
    }
}

extension PersonalFeed: CustomStringConvertible, CustomDebugStringConvertible {
    var description: String { redactedURLText }
    var debugDescription: String { "PersonalFeed(\(kind.rawValue), \(redactedURLText))" }
}
