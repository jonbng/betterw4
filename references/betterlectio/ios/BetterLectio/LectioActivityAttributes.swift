//
//  LectioActivityAttributes.swift
//  BetterLectio
//
//  Created by Elliott Friedrich on 27/02/2026.
//

import ActivityKit
import Foundation
import SwiftUI

struct LectioActivityAttributes: ActivityAttributes {

    // MARK: - Embedded lesson snapshot (stored in static attributes)

    struct EmbeddedLesson: Codable, Hashable {
        let id: String
        let subjectName: String
        let subjectIconName: String
        let subjectColorHue: Int
        let room: String?
        let teacher: String?
        let startTime: String   // "08:10"
        let endTime: String     // "09:40"
        let date: Date
    }

    // Static — set once when activity starts, contains full day schedule
    let todaysLessons: [EmbeddedLesson]
    let variant: String

    // Dynamic — only bumped when the lesson list changes (e.g. cancellation)
    struct ContentState: Codable, Hashable {
        let version: Int
    }

    // MARK: - View helpers

    /// Returns the current active lesson, or the next upcoming lesson within 60 minutes.
    func currentOrUpcomingLesson(at date: Date) -> (lesson: EmbeddedLesson, isUpcoming: Bool)? {
        let cal = Calendar.current
        let h = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        let now = h * 60 + m

        let todays = todaysLessons.filter { cal.isDate($0.date, inSameDayAs: date) }

        if let active = todays.first(where: {
            let s = timeToMinutes($0.startTime)
            let e = timeToMinutes($0.endTime)
            return now >= s && now < e
        }) {
            return (active, false)
        }

        let upcoming = todays
            .filter {
                let s = timeToMinutes($0.startTime)
                return s > now && s - now <= 60
            }
            .min { timeToMinutes($0.startTime) < timeToMinutes($1.startTime) }

        return upcoming.map { ($0, true) }
    }

    /// Progress through a lesson from 0.0 to 1.0.
    func progress(for lesson: EmbeddedLesson, at date: Date) -> Double {
        let cal = Calendar.current
        let h = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        let now = h * 60 + m
        let s = timeToMinutes(lesson.startTime)
        let e = timeToMinutes(lesson.endTime)
        guard e > s else { return 0 }
        return min(1, max(0, Double(now - s) / Double(e - s)))
    }

    /// The next lesson scheduled after the given lesson ends.
    func nextLesson(after lesson: EmbeddedLesson) -> EmbeddedLesson? {
        let endMin = timeToMinutes(lesson.endTime)
        return todaysLessons
            .filter { timeToMinutes($0.startTime) >= endMin && $0.id != lesson.id }
            .min { timeToMinutes($0.startTime) < timeToMinutes($1.startTime) }
    }

    /// All lesson start and end dates for the day — used as an explicit TimelineView schedule
    /// so the system re-renders the live activity at each lesson transition.
    var lessonTransitionDates: [Date] {
        todaysLessons
            .filter { !$0.startTime.isEmpty && !$0.endTime.isEmpty }
            .flatMap { lesson in
                [
                    LectioActivityAttributes.dateFromTimeString(lesson.startTime, on: lesson.date),
                    LectioActivityAttributes.dateFromTimeString(lesson.endTime,   on: lesson.date)
                ]
            }
            .sorted()
    }

    // MARK: - Shared utilities

    /// Combines a calendar day with a time string such as `"08:10"` or `"08.10"`.
    static func dateFromTimeString(_ time: String, on day: Date) -> Date {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        let separator: Character = time.contains(":") ? ":" : "."
        let parts = time.split(separator: separator).compactMap { Int($0) }
        guard parts.count == 2 else { return dayStart }
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: dayStart) ?? dayStart
    }

    func timeToMinutes(_ t: String) -> Int {
        let sep: Character = t.contains(":") ? ":" : "."
        let p = t.split(separator: sep).compactMap { Int($0) }
        return p.count == 2 ? p[0] * 60 + p[1] : 0
    }
}

extension Color {
    static func lessonMappingHue(_ hue: Int) -> Color {
        let normalizedHue = Double(((hue % 360) + 360) % 360) / 360.0
        return Color(hue: normalizedHue, saturation: 0.72, brightness: 0.88)
    }
}
