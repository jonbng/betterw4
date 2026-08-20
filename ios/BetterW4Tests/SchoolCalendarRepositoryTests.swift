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
