//
//  W4TimetableParserTests.swift
//  BetterW4Tests
//
//  Fixture provenance:
//    home.html — [V] REAL CAPTURE of the W4 Home page (sanitized: identities replaced).
//
//  Read this before adding assertions: the captured week is **August 2026, week 33, a holiday
//  week**. It contains seven day columns and ZERO `.period` elements. So these tests verify the
//  grid, the header dates, the rotation days and the hour bounds — all of which are real — and
//  they assert that a week with no lessons parses as a week with no lessons.
//
//  They deliberately do NOT assert anything about lesson-block internals, because no lesson block
//  has ever been captured. The synthesized-grid test at the bottom is marked [I] and verifies the
//  PARSER's pixel geometry, not W4's markup.
//

import XCTest
@testable import BetterW4

final class W4TimetableParserTests: XCTestCase {

    // MARK: - Fixtures

    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: "html", subdirectory: "Fixtures/W4")
            ?? bundle.url(forResource: name, withExtension: "html") else {
            throw XCTSkip("Fixture \(name).html is not in the test bundle")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func osloDate(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(W4Dates.date(year: year, month: month, day: day))
    }

    // MARK: - The real capture

    func testCapturedWeekHasSevenDaysWithHeaderDates() throws {
        let week = W4TimetableParser.parseWeek(html: try fixture("home"), source: .academics)

        XCTAssertEqual(week.days.count, 7)
        XCTAssertEqual(week.days.first?.date, try osloDate(2026, 8, 10), "Monday 10-Aug-2026")
        XCTAssertEqual(week.days.last?.date, try osloDate(2026, 8, 16), "Sunday 16-Aug-2026")
        XCTAssertEqual(week.days.map(\.dayName).first, "Monday")
        XCTAssertEqual(week.days.map(\.dayName).last, "Sunday")
    }

    func testCapturedWeekIsWeek33Of2026() throws {
        let week = W4TimetableParser.parseWeek(html: try fixture("home"), source: .academics)

        XCTAssertEqual(week.year, 2026)
        XCTAssertEqual(week.week, 33)
        XCTAssertEqual(week.title, "August 2026, week 33")
    }

    func testCapturedWeekHourBounds() throws {
        let week = W4TimetableParser.parseWeek(html: try fixture("home"), source: .academics)

        // tt_start_hour = 7 / tt_end_hour = 22, read from the page script.
        XCTAssertEqual(week.startHour, 7)
        XCTAssertEqual(week.endHour, 22)
    }

    func testCapturedWeekRotationDays() throws {
        let week = W4TimetableParser.parseWeek(html: try fixture("home"), source: .academics)

        XCTAssertEqual(week.days[0].rotationDay, "Day 1")
        XCTAssertEqual(week.days[4].rotationDay, "Day 5")
        XCTAssertEqual(week.days[5].rotationDay, "Weekend")
        XCTAssertTrue(week.days[5].isWeekend)
        // `no-classes` is a class, not the text "No-Classes" (bug B4).
        XCTAssertTrue(week.days[5].isNoClasses, "Saturday carries the no-classes class")
        XCTAssertFalse(week.days[0].isNoClasses)
    }

    func testCapturedWeekExtraAcademicsNote() throws {
        let week = W4TimetableParser.parseWeek(html: try fixture("home"), source: .academics)
        XCTAssertEqual(week.days[0].eaNote, "No EA")
    }

    /// The whole point of an honest fixture test: a holiday week has no lessons, and the parser
    /// must say so rather than inventing blocks from grid furniture.
    func testCapturedHolidayWeekHasNoEvents() throws {
        let week = W4TimetableParser.parseWeek(html: try fixture("home"), source: .academics)

        XCTAssertTrue(
            week.days.allSatisfy { $0.events.isEmpty },
            "The captured week is a holiday week with zero .period elements. If this ever fails, "
            + "the parser has started inventing events out of grid furniture."
        )
    }

    func testExactlyOneColumnIsMarkedCurrent() throws {
        let week = W4TimetableParser.parseWeek(html: try fixture("home"), source: .academics)
        XCTAssertEqual(week.days.filter(\.isToday).count, 1, "one div.column.current in the grid")
    }

    /// Proof that D-11 holds: dates come from Europe/Oslo, never TimeZone.current. If the parser
    /// used the device zone, a machine west of Greenwich would parse 10-Aug as 9-Aug.
    func testDatesAreOsloRegardlessOfDeviceTimeZone() throws {
        let week = W4TimetableParser.parseWeek(html: try fixture("home"), source: .academics)
        let monday = try XCTUnwrap(week.days.first?.date)

        var osloCalendar = Calendar(identifier: .gregorian)
        osloCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Oslo"))
        let components = osloCalendar.dateComponents([.year, .month, .day, .hour], from: monday)

        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 8)
        XCTAssertEqual(components.day, 10)
        XCTAssertEqual(components.hour, 0, "Parsed dates are Oslo midnight, not device midnight")
    }

    // MARK: - Source prefixing

    func testEventIDsArePrefixedBySource() throws {
        // AC and EA genuinely reuse numeric ids; without the prefix a merge collapses them (D-9).
        let html = Self.syntheticGrid(periodHTML: """
            <div class="period" style="top: 60px; height: 60px;" title="Biology HL with A. Teacher">
              <div class="inner"><a href="index.php?r=academics/classes/class&amp;id=42">Biology HL</a>
                <div class="datetime">8:00 — 9:00</div><div class="room">Lab 2</div>
              </div>
            </div>
            """)

        let academics = W4TimetableParser.parseWeek(html: html, source: .academics)
        let extraAcademics = W4TimetableParser.parseWeek(html: html, source: .extraAcademics)

        XCTAssertEqual(academics.days.first?.events.first?.id, "ac-w4-42")
        XCTAssertEqual(extraAcademics.days.first?.events.first?.id, "ea-w4-42")
        XCTAssertNotEqual(
            academics.days.first?.events.first?.id,
            extraAcademics.days.first?.events.first?.id
        )
    }

    // MARK: - [I] SYNTHESIZED — verifies the parser, not W4

    /// **[I]** No real `.period` element has ever been captured. The markup below is invented from
    /// the Android port's selectors, so this test proves the parser handles that shape — it is NOT
    /// evidence that W4 emits it. Revisit when a term-time capture exists.
    func testSynthesizedLessonBlockParsesTimeRoomAndTooltip() throws {
        let week = W4TimetableParser.parseWeek(
            html: Self.syntheticGrid(periodHTML: """
                <div class="period" style="top: 60px; height: 90px;" title="Biology HL — room Lab 2">
                  <div class="inner">Biology HL
                    <div class="datetime">8:00 — 9:30</div><div class="room">Lab 2</div>
                  </div>
                </div>
                """),
            source: .academics
        )

        let event = try XCTUnwrap(week.days.first?.events.first)
        XCTAssertEqual(event.title, "Biology HL", "datetime/room chrome must not leak into the title")
        XCTAssertEqual(event.room, "Lab 2")
        XCTAssertEqual(event.rawTooltip, "Biology HL — room Lab 2", "bug B3: title attr captured raw")
        XCTAssertEqual(event.startMinutesFromMidnight, 8 * 60)
        XCTAssertEqual(event.endMinutesFromMidnight, 9 * 60 + 30)
        XCTAssertFalse(event.isAllDay)
    }

    /// **[I]** The pixel fallback is the one part of block placement we CAN prove: 900px over 15
    /// hours from tt_start_hour = 7 means 1px = 1 minute. A block with no parseable time range
    /// must still land in the right slot.
    func testSynthesizedBlockWithoutTimeTextFallsBackToPixelGeometry() throws {
        let week = W4TimetableParser.parseWeek(
            html: Self.syntheticGrid(periodHTML: """
                <div class="period" style="top: 120px; height: 45px;">
                  <div class="inner">Theory of Knowledge</div>
                </div>
                """),
            source: .academics
        )

        let event = try XCTUnwrap(week.days.first?.events.first)
        // top 120px ⇒ 120 minutes after 07:00 ⇒ 09:00; height 45px ⇒ 45 minutes.
        XCTAssertEqual(event.startMinutesFromMidnight, 9 * 60)
        XCTAssertEqual(event.endMinutesFromMidnight, 9 * 60 + 45)
    }

    /// **[I]** Grid furniture must not become an event.
    func testNoClassesFillerBlockIsIgnored() throws {
        let week = W4TimetableParser.parseWeek(
            html: Self.syntheticGrid(periodHTML: """
                <div class="period" style="top: 0px; height: 900px;">
                  <div class="inner">No-Classes</div>
                </div>
                """),
            source: .academics
        )
        XCTAssertTrue(week.days.first?.events.isEmpty ?? false)
    }

    func testMergeCombinesAcademicsAndExtraAcademicsOnTheSameDay() throws {
        let academics = W4TimetableParser.parseWeek(
            html: Self.syntheticGrid(periodHTML: """
                <div class="period" style="top: 60px; height: 60px;">
                  <div class="inner">Biology HL<div class="datetime">8:00 — 9:00</div></div>
                </div>
                """),
            source: .academics
        )
        let extraAcademics = W4TimetableParser.parseWeek(
            html: Self.syntheticGrid(periodHTML: """
                <div class="period" style="top: 600px; height: 60px;">
                  <div class="inner">Kayaking<div class="datetime">17:00 — 18:00</div></div>
                </div>
                """),
            source: .extraAcademics
        )

        let merged = W4TimetableParser.merge(academics, with: extraAcademics)
        let events = try XCTUnwrap(merged.days.first?.events)

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.map(\.title), ["Biology HL", "Kayaking"], "sorted by start time")
        XCTAssertEqual(events.map(\.source), [.academics, .extraAcademics])
    }

    // MARK: - Malformed input

    func testEmptyAndGarbageInputDoNotThrow() {
        let empty = W4TimetableParser.parseWeek(html: "", source: .academics)
        XCTAssertTrue(empty.days.isEmpty)

        let garbage = W4TimetableParser.parseWeek(html: "<html><body><p>nope</p></body></html>",
                                                  source: .academics)
        XCTAssertTrue(garbage.days.isEmpty)
    }

    // MARK: - Synthetic grid builder

    /// Mirrors the real capture's structure, including the TWO `id="timetable"` elements (bug B1)
    /// so every synthesized test also exercises the outer/inner disambiguation.
    private static func syntheticGrid(periodHTML: String) -> String {
        """
        <html><body>
        <script>tt_start_hour = 7; tt_end_hour = 22;</script>
        <div id="timetable">
          <h3>August 2026, week 33</h3>
          <div id="timetable-header">
            <div class="header-row">
              <div class="header-cell first">&nbsp;</div>
              <div class="header-cell">
                <div class="day-name">Monday</div><div>10-Aug-2026</div>
                <div class="rotation-day">Day 1</div><div>No EA</div>
              </div>
            </div>
          </div>
          <div id="timetable">
            <div class="column" style="height: 900px">
              <div class="cell">7:00 — 8:00</div><div class="cell">8:00 — 9:00</div>
            </div>
            <div class="column" style="height: 900px">
              \(periodHTML)
            </div>
          </div>
        </div>
        </body></html>
        """
    }
}
