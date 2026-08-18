//
//  SchoolCalendarRepository.swift
//  BetterW4
//
//  Public UWCRCN Google Calendar (`calendar@uwcrcn.no`). Same feed as the W4 Home embed.
//  Only fetched when the student turns the overlay on (OQ-8).
//

import Foundation

actor SchoolCalendarRepository {

    static let shared = SchoolCalendarRepository()

    private let loadIcs: @Sendable (_ forceRefresh: Bool) async -> String?

    init(
        loadIcs: (@Sendable (_ forceRefresh: Bool) async -> String?)? = nil,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        if let loadIcs {
            self.loadIcs = loadIcs
        } else {
            self.loadIcs = { forceRefresh in
                await SchoolCalendarRepository.fetchAndCache(forceRefresh: forceRefresh, clock: clock)
            }
        }
    }

    /// Overlay week for ISO `year`/`week`, or `nil` when the feed is empty or unavailable.
    func weekOverlay(year: Int, week: Int, forceRefresh: Bool = false) async -> ScheduleWeek? {
        let events = await events(year: year, week: week, forceRefresh: forceRefresh)
        guard !events.isEmpty else { return nil }
        let empty = ScheduleWeek(year: year, week: week, source: .schoolCalendar)
        return SchoolCalendar.overlay(empty, with: events)
    }

    func events(year: Int, week: Int, forceRefresh: Bool = false) async -> [TimetableEvent] {
        guard let ics = await loadIcs(forceRefresh) else { return [] }
        return SchoolCalendar.events(ics: ics, year: year, week: week)
    }

    // MARK: - Production fetch

    private static func fetchAndCache(
        forceRefresh: Bool,
        clock: @escaping @Sendable () -> Date
    ) async -> String? {
        if !forceRefresh, let cached = readCache(now: clock()) {
            return cached
        }
        let fetched = await fetchIcs()
        if let fetched {
            writeCache(fetched, fetchedAt: clock())
            return fetched
        }
        return readCache(now: clock(), ignoreTTL: true)
    }

    private static func fetchIcs() async -> String? {
        guard let url = SchoolCalendar.icsURL else { return nil }
        var request = URLRequest(url: url)
        request.setValue(W4UserAgent.value, forHTTPHeaderField: "User-Agent")
        request.setValue("text/calendar, text/plain, */*", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            guard let body = String(data: data, encoding: .utf8),
                  body.range(of: "BEGIN:VCALENDAR", options: .caseInsensitive) != nil else {
                return nil
            }
            return body
        } catch {
            return nil
        }
    }

    private static func readCache(now: Date, ignoreTTL: Bool = false) -> String? {
        let url = cacheURL
        guard let data = try? Data(contentsOf: url),
              let body = String(data: data, encoding: .utf8),
              !body.isEmpty else {
            return nil
        }
        if !ignoreTTL {
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let fetchedAt = attrs?[.modificationDate] as? Date ?? .distantPast
            if now.timeIntervalSince(fetchedAt) >= SchoolCalendar.cacheTTL {
                return nil
            }
        }
        return body
    }

    private static func writeCache(_ body: String, fetchedAt: Date) {
        let url = cacheURL
        try? body.data(using: .utf8)?.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.modificationDate: fetchedAt], ofItemAtPath: url.path)
    }

    private static var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("school-calendar.ics")
    }
}
