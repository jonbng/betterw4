//
//  CustomEventsStore.swift
//  BetterW4
//
//  Persists device-local custom timetable events per student in UserDefaults.
//  Survives logout and cache clear on purpose — they are user data, not a W4
//  page cache. Two accounts on one device keep separate lists.
//

import Combine
import Foundation

struct StoredCustomEvent: Codable, Equatable, Sendable {
    var id: String
    var title: String
    var notes: String?
    var start: Date
    var end: Date
    var isAllDay: Bool

    func asTimetableEvent() -> TimetableEvent {
        CustomEvents.makeEvent(
            id: id,
            title: title,
            notes: notes,
            start: start,
            end: end,
            isAllDay: isAllDay
        )
    }

    static func from(_ event: TimetableEvent) -> StoredCustomEvent? {
        guard let start = event.start else { return nil }
        let end = event.end ?? start
        return StoredCustomEvent(
            id: event.id,
            title: event.title,
            notes: event.notes,
            start: start,
            end: end,
            isAllDay: event.isAllDay
        )
    }
}

@MainActor
final class CustomEventsStore: ObservableObject {
    static let shared = CustomEventsStore()

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    @Published private(set) var events: [TimetableEvent] = []
    private(set) var studentId: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func activate(studentId: String) {
        self.studentId = studentId
        events = load(studentId: studentId)
    }

    func events(year: Int, week: Int) -> [TimetableEvent] {
        guard let monday = W4Dates.startOfISOWeek(year: year, week: week) else { return [] }
        let end = W4Dates.adding(days: 7, to: monday)
        return events.filter { event in
            let start = event.start ?? event.date
            let finish = event.end ?? start
            start < end && finish > monday
        }
    }

    @discardableResult
    func save(title: String, notes: String, start: Date, end: Date, isAllDay: Bool, replacing id: String? = nil) -> TimetableEvent {
        let event = CustomEvents.makeEvent(
            id: id ?? "local-\(UUID().uuidString)",
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes,
            start: start,
            end: end,
            isAllDay: isAllDay
        )
        if let id {
            events.removeAll { $0.id == id }
        }
        events.append(event)
        persist()
        return event
    }

    func delete(id: String) {
        let before = events.count
        events.removeAll { $0.id == id }
        if events.count != before {
            persist()
        }
    }

    func overlay(_ week: ScheduleWeek) -> ScheduleWeek {
        CustomEvents.overlay(week, with: events)
    }

    private func persist() {
        guard let studentId else { return }
        let stored = events.compactMap(StoredCustomEvent.from)
        guard let data = try? encoder.encode(stored) else { return }
        defaults.set(data, forKey: Self.key(studentId: studentId))
    }

    private func load(studentId: String) -> [TimetableEvent] {
        guard let data = defaults.data(forKey: Self.key(studentId: studentId)),
              let stored = try? decoder.decode([StoredCustomEvent].self, from: data) else {
            return []
        }
        return stored.map { $0.asTimetableEvent() }
    }

    static func key(studentId: String) -> String {
        "w4.customEvents.\(studentId)"
    }
}
