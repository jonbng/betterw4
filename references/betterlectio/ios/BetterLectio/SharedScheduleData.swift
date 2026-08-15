//
//  SharedScheduleData.swift
//  BetterLectio
//
//  Created by Elliott Friedrich on 23/03/2026.
//

import Foundation

/// Lesson snapshot stored in the App Group for the widget extension.
struct SharedLesson: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let displayName: String
    let iconName: String
    let colorHue: Int
    let room: String?
    let teacher: String?
    let startTime: String
    let endTime: String
    /// `EventStatus.rawValue`
    let status: String
    let date: Date
}

enum SharedScheduleData {
    private static let appGroupId = "group.dk.elliottf.betterlectio"
    private static let lessonsKey = "sharedScheduleLessons"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    @discardableResult
    static func save(lessons: [SharedLesson]) -> Bool {
        guard let defaults else { return false }
        guard let data = try? JSONEncoder().encode(lessons) else { return false }
        guard defaults.data(forKey: lessonsKey) != data else { return false }
        defaults.set(data, forKey: lessonsKey)
        return true
    }

    static func load() -> [SharedLesson] {
        guard let defaults,
              let data = defaults.data(forKey: lessonsKey),
              let lessons = try? JSONDecoder().decode([SharedLesson].self, from: data)
        else {
            return []
        }
        return lessons
    }

    /// Clears widget snapshot data (call when schedule cache is cleared).
    static func clear() {
        defaults?.removeObject(forKey: lessonsKey)
    }
}
