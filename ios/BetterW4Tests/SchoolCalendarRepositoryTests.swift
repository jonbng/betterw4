//
//  SchoolCalendarRepositoryTests.swift
//  BetterW4Tests
//

import XCTest
@testable import BetterW4

final class SchoolCalendarRepositoryTests: XCTestCase {

    func testWeekOverlayBuildsSchoolCalendarEventsFromInjectedICS() async throws {
        let ics = try fixture()
        let repository = SchoolCalendarRepository(loadIcs: { _ in ics })

        let overlay = await repository.weekOverlay(year: 2026, week: 33)

        XCTAssertEqual(overlay?.source, .schoolCalendar)
        let titles = overlay?.allEvents.map(\.title) ?? []
        XCTAssertTrue(titles.contains("Year 1 arrival in Bergen"))
        XCTAssertTrue(overlay?.allEvents.allSatisfy(SchoolCalendar.isSchoolCalendarEvent) == true)
    }

    func testWeekOverlayIsNilWhenTheFeedIsEmpty() async {
        let repository = SchoolCalendarRepository(loadIcs: { _ in nil })
        let overlay = await repository.weekOverlay(year: 2026, week: 33)
        XCTAssertNil(overlay)
    }

    func testICSIsLoadedOnceAcrossWeeksUntilForced() async throws {
        let ics = try fixture()
        let counter = ICSLoadCounter()
        let repository = SchoolCalendarRepository(loadIcs: { _ in
            await counter.increment()
            return ics
        })

        let first = await repository.weekOverlay(year: 2026, week: 33)
        let second = await repository.weekOverlay(year: 2026, week: 33)
        XCTAssertEqual(await counter.count, 1, "the same week must reuse the in-memory ICS")
        XCTAssertEqual(first?.allEvents.map(\.id), second?.allEvents.map(\.id))

        _ = await repository.weekOverlay(year: 2026, week: 34)
        XCTAssertEqual(await counter.count, 1, "a neighbouring week must reuse the same ICS body")

        _ = await repository.weekOverlay(year: 2026, week: 33, forceRefresh: true)
        XCTAssertEqual(await counter.count, 2, "forceRefresh must re-read the feed")
    }

    private func fixture() throws -> String {
        let bundle = Bundle(for: type(of: self))
        if let url = bundle.url(forResource: "school-calendar", withExtension: "ics", subdirectory: "Fixtures/W4")
            ?? bundle.url(forResource: "school-calendar", withExtension: "ics") {
            return try String(contentsOf: url, encoding: .utf8)
        }
        let onDisk = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/W4/school-calendar.ics")
        if FileManager.default.fileExists(atPath: onDisk.path) {
            return try String(contentsOf: onDisk, encoding: .utf8)
        }
        throw XCTSkip("Fixture school-calendar.ics is not in the test bundle")
    }
}

private actor ICSLoadCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}
