//
//  AbsenceModels.swift
//  BetterW4
//
//  Presentation models for the Attendance screen (`AbsenceView`).
//
//  The *domain* lives in `AttendanceModels.swift` (`AttendanceMeter`, `AttendanceRecord`,
//  `SubjectAttendance`) and the *loading* lives in `AttendanceRepository`. What is left — and what
//  this file owns — is the small amount of shaping a list needs before SwiftUI can draw it: two
//  meter cards, and registrations grouped into day sections.
//
//  Everything the old Lectio absence model carried is gone, because W4 does not have it:
//  `AbsenceSummary` (the two percentages), `AbsenceEntry.absencePercent` / `registeredBy` /
//  `isApproved`, `ActivityDetails`, and the whole `AbsenceReasonOption` / `AbsenceEditDetails`
//  cause-editing pair. W4 counts *events* — "You have N absences and M latenesses so far" — and its
//  registration rows are read-only for students (`AttendanceRecord.isEditable` is `false`, always).
//  W4's analog of editing is `people/students/absences/register`, and its POST payload has never
//  been captured, so the app links out to it rather than pretending to submit one.
//
//  All types are `Sendable` value types: the view model builds them on the main actor from a
//  `Sendable` snapshot, and nothing here reads a clock except through the `now` it is handed.
//

import Foundation

// MARK: - Meters

/// One Home attendance meter, ready to draw.
///
/// `meter` is optional on purpose: a meter W4 did not render is *absent*, which is a different fact
/// from a meter that reads zero, and the card says so ("Not reported") instead of showing a
/// confident 0.
struct AttendanceMeterDisplay: Identifiable, Equatable, Sendable {
    let source: AttendanceSource
    let meter: AttendanceMeter?

    var id: String { source.rawValue }

    /// "Academics" / "Extra Academics".
    var title: String { source.displayName }

    var absences: Int? { meter?.absences }
    var latenesses: Int? { meter?.latenesses }
    var isReported: Bool { meter != nil }
    var isClean: Bool { meter?.isClean ?? false }

    /// "2 absences and 1 lateness so far" — W4's own sentence, in English, rebuilt from the counts
    /// rather than echoed, so the plural is right for every number.
    var sentence: String {
        guard let meter else { return "Not reported yet." }
        return "You have \(Self.count(meter.absences, "absence", "absences")) "
            + "and \(Self.count(meter.latenesses, "lateness", "latenesses")) so far."
    }

    static func count(_ value: Int, _ singular: String, _ plural: String) -> String {
        "\(value) \(value == 1 ? singular : plural)"
    }

    /// Both meters, Academics first, in the order the screen shows them.
    static func all(from meters: AttendanceMeters) -> [AttendanceMeterDisplay] {
        AttendanceSource.allCases.map {
            AttendanceMeterDisplay(source: $0, meter: meters.meter(for: $0))
        }
    }
}

// MARK: - Day sections

/// One day of registrations, for a sectioned list.
///
/// Rows W4 gave no parsable date are not dropped — they are collected into a trailing section keyed
/// by whatever the date cell actually said, so an unfamiliar date format costs a heading, not a row.
struct AttendanceDaySection: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let date: Date?
    let records: [AttendanceRecord]

    var isEmpty: Bool { records.isEmpty }

    /// Groups records into day sections, newest first.
    ///
    /// Undated rows sort last and keep the order W4 rendered them in — with no date there is
    /// nothing honest to sort them by.
    static func sections(
        from records: [AttendanceRecord],
        now: Date = TimeProvider.now
    ) -> [AttendanceDaySection] {
        guard !records.isEmpty else { return [] }

        var order: [String] = []
        var buckets: [String: [AttendanceRecord]] = [:]
        var days: [String: Date] = [:]

        for record in records {
            let key: String
            if let date = record.date {
                let day = W4Dates.startOfDay(date)
                key = "d-\(Int(day.timeIntervalSince1970))"
                days[key] = day
            } else {
                let raw = record.displayDate.trimmingCharacters(in: .whitespacesAndNewlines)
                key = "u-\(raw.isEmpty ? "none" : raw)"
            }
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = []
            }
            buckets[key]?.append(record)
        }

        let sections: [AttendanceDaySection] = order.compactMap { key in
            guard let bucket = buckets[key] else { return nil }
            let day = days[key]
            return AttendanceDaySection(
                id: key,
                title: day.map { title(for: $0, now: now) } ?? undatedTitle(for: bucket),
                date: day,
                records: bucket
            )
        }

        return sections.sorted { left, right in
            switch (left.date, right.date) {
            case let (l?, r?): return l > r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return false
            }
        }
    }

    /// "Today", "Yesterday", "Tomorrow", otherwise "Mon 12 May 2026".
    static func title(for day: Date, now: Date) -> String {
        let today = W4Dates.startOfDay(now)
        if W4Dates.isSameDay(day, today) { return "Today" }
        if W4Dates.isSameDay(day, W4Dates.adding(days: -1, to: today)) { return "Yesterday" }
        if W4Dates.isSameDay(day, W4Dates.adding(days: 1, to: today)) { return "Tomorrow" }
        return headingFormatter.string(from: day)
    }

    private static func undatedTitle(for bucket: [AttendanceRecord]) -> String {
        let raw = bucket.first?.displayDate.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? "No date" : raw
    }

    /// `en_GB`, Europe/Oslo — the same locale and zone every other W4 date uses.
    private static let headingFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = W4Dates.zone
        formatter.calendar = W4Dates.calendar
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM yyyy")
        return formatter
    }()
}
