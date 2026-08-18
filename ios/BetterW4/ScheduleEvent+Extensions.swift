//
//  ScheduleEvent+Extensions.swift
//  BetterW4
//
//  Presentation helpers for `TimetableEvent`, the model `W4TimetableParser` produces.
//
//  Everything here is derived from the event's own `start`/`end` instants, which `W4Dates` already
//  built in Europe/Oslo. Nothing parses a time string and nothing reads `Calendar.current`: a phone
//  set to another timezone still shows the Oslo timetable (plan D-11).
//
//  Every field except the title, the date and the source is optional in the model, because no real
//  `.period` block has ever been captured. So every accessor here answers `nil` rather than a
//  placeholder, and the views decide what to omit.
//

import Foundation
import SwiftUI

extension TimetableEvent {

    // MARK: - Naming and colour

    /// The subject name the student renamed it to, or W4's own label.
    var displayTitle: String {
        let mapped = SubjectMapper.displayName(for: subject)
        return mapped.isEmpty ? title : mapped
    }

    /// SF Symbol for the subject group.
    var iconName: String {
        SubjectMapper.iconName(for: subject)
    }

    /// Subject hue, or the status colour when subject colours are switched off.
    ///
    /// `SettingsStore.accentColor(for:)` still speaks the legacy Lectio event type, so the same
    /// rule is applied here against the W4 model rather than converting between the two.
    func accentColor(useSubjectColors: Bool) -> Color {
        if SchoolCalendar.isSchoolCalendarEvent(self) {
            return Color(red: 11 / 255, green: 128 / 255, blue: 67 / 255) // #0B8043
        }
        if useSubjectColors {
            return SubjectMapper.color(for: subject)
        }
        switch status {
        case .normal:
            return Color(red: 51 / 255, green: 98 / 255, blue: 225 / 255)   // BrandBlue #3362E1
        case .changed, .moved:
            return Color(red: 46 / 255, green: 158 / 255, blue: 91 / 255)   // #2E9E5B
        case .cancelled:
            return Color(red: 211 / 255, green: 47 / 255, blue: 47 / 255)   // #D32F2F
        }
    }

    // MARK: - Placement

    /// True when this block can be drawn on a clock. All-day blocks and blocks W4 gave us no
    /// pixel offset for belong in the strip above the timeline instead.
    var isPlaceable: Bool {
        !isAllDay && start != nil
    }

    /// Duration in minutes, or `nil` when either end of the range is missing.
    var durationMinutes: Int? {
        guard let startMinutes = startMinutesFromMidnight,
              let endMinutes = endMinutesFromMidnight else { return nil }
        return max(0, endMinutes - startMinutes)
    }

    /// True when `instant` falls inside this lesson.
    func isLive(at instant: Date) -> Bool {
        guard let start, let end else { return false }
        return instant >= start && instant < end
    }

    /// Whole minutes until the lesson starts, or `nil` once it has started.
    func minutesUntilStart(from instant: Date) -> Int? {
        guard let start, start > instant else { return nil }
        return Int((start.timeIntervalSince(instant) / 60).rounded(.up))
    }

    /// Whole minutes left of the lesson, or `nil` when it is not running.
    func minutesRemaining(at instant: Date) -> Int? {
        guard isLive(at: instant), let end else { return nil }
        return Int((end.timeIntervalSince(instant) / 60).rounded(.up))
    }

    /// How far through the lesson `instant` is, 0…1, or `nil` when it is not running.
    func progress(at instant: Date) -> Double? {
        guard let start, let end, end > start else { return nil }
        let elapsed = instant.timeIntervalSince(start)
        let total = end.timeIntervalSince(start)
        return min(1, max(0, elapsed / total))
    }

    // MARK: - Text

    /// `Cancelled` / `Changed`, or `nil` for an ordinary lesson.
    var statusLabel: String? {
        switch status {
        case .normal: return nil
        case .cancelled: return "Cancelled"
        case .changed, .moved: return "Changed"
        }
    }

    /// `Room 12 · A. Nordby`, whichever halves exist, or `nil` when neither does.
    var locationLine: String? {
        let parts = [room, teacher]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The best single line to put under a card: the room if there is one, otherwise the time.
    var subtitleLine: String? {
        if let room = room?.trimmingCharacters(in: .whitespacesAndNewlines), !room.isEmpty {
            return room
        }
        return timeRangeText
    }

    /// Extra tooltip text after Class/Teacher/Room are pulled out. `<br>` becomes a newline;
    /// tags are stripped so the sheet never shows raw W4 markup.
    var detailText: String? {
        if let notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            return nil
        }
        guard let raw = rawTooltip?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let tooltip = PeriodTooltip.parse(raw)
        if let extra = tooltip.extraNotes?.trimmingCharacters(in: .whitespacesAndNewlines), !extra.isEmpty {
            let alreadyShown = [title, subject, room, teacher]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if alreadyShown.contains(where: { $0.caseInsensitiveCompare(extra) == .orderedSame }) {
                return nil
            }
            return extra
        }
        if tooltip.className != nil || tooltip.teacher != nil || tooltip.room != nil || tooltip.blockName != nil {
            return nil
        }
        let stripped = PeriodTooltip.plainText(raw)
        let alreadyShown = [title, subject, room, teacher]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !stripped.isEmpty,
              !alreadyShown.contains(where: { $0.caseInsensitiveCompare(stripped) == .orderedSame }) else {
            return nil
        }
        return stripped
    }
}

extension Array where Element == TimetableEvent {
    /// Blocks that belong on the timed timeline, earliest first.
    var timed: [TimetableEvent] {
        filter(\.isPlaceable).sorted { lhs, rhs in
            let left = lhs.startMinutesFromMidnight ?? 0
            let right = rhs.startMinutesFromMidnight ?? 0
            return left == right ? lhs.id < rhs.id : left < right
        }
    }

    /// Blocks to render in the strip above the timeline: all-day blocks, and anything W4 gave us
    /// no time for at all.
    var allDay: [TimetableEvent] {
        filter { !$0.isPlaceable }
    }
}
