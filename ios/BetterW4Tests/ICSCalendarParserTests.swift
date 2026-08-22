//
//  ICSCalendarParserTests.swift
//  BetterW4Tests
//
//  W4 port plan Wave 4, item 4.11. Spec: docs/spec/parsers.md §5.
//
//  FIXTURE PROVENANCE — read this before adding an assertion.
//
//    `Fixtures/W4/school-calendar.ics` is **[I] — SYNTHESIZED**. It was written
//    by hand (ported from the Android port's test resource), not captured. No
//    `academics/feeds` response and no `calendar.google.com` response for
//    UWCRCN has ever been fetched, and the saved copy of the Home `#calendar`
//    iframe is an empty `about:blank` document (OQ-8).
//
//    Therefore **every assertion in this file verifies `ICSCalendarParser`
//    against RFC 5545, not against the bytes UWCRCN actually serves.** The
//    inline strings below are synthesized too, and each is marked [I] where it
//    is built. Nothing here is evidence about W4's real feeds. There are no [V]
//    assertions in this file, because there is nothing verified to assert.
//
//    No real personal-feed secret appears anywhere in this file or in the
//    fixture, and none ever may: the `academics/feeds` query secret is
//    password-equivalent (README §4.8). The redaction tests at the bottom use an
//    obvious placeholder.
//

import XCTest
@testable import BetterW4

final class ICSCalendarParserTests: XCTestCase {

    // MARK: - Fixtures and helpers

    /// Loads a `.ics` from the test bundle, falling back to the source tree so a
    /// resource-copy hiccup skips rather than silently passes.
    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: type(of: self))
        if let url = bundle.url(forResource: name, withExtension: "ics", subdirectory: "Fixtures/W4")
            ?? bundle.url(forResource: name, withExtension: "ics") {
            return try String(contentsOf: url, encoding: .utf8)
        }

        let onDisk = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/W4/\(name).ics")
        if FileManager.default.fileExists(atPath: onDisk.path) {
            return try String(contentsOf: onDisk, encoding: .utf8)
        }

        throw XCTSkip("Fixture \(name).ics is not in the test bundle")
    }

    private func oslo(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0
    ) throws -> Date {
        try XCTUnwrap(W4Dates.date(year: year, month: month, day: day, hour: hour, minute: minute))
    }

    /// The 7 Oslo days starting on `monday`, as the half-open range the parser takes.
    private func week(from monday: Date) -> (from: Date, toExclusive: Date) {
        (monday, W4Dates.adding(days: 7, to: monday))
    }

    private func schoolCalendarEvents(
        _ ics: String,
        from: Date,
        toExclusive: Date,
        zone: TimeZone = W4Dates.zone
    ) -> [TimetableEvent] {
        ICSCalendarParser.events(ics: ics, from: from, toExclusive: toExclusive, zone: zone)
    }

    // MARK: - The synthesized 7-VEVENT fixture, week 33 of 2026 (10–16 August)

    /// [I] synthesized fixture — verifies the parser's selection and ordering.
    func testWeek33ContainsExactlyTheFiveExpectedOccurrences() throws {
        let ics = try fixture("school-calendar")
        let range = week(from: try oslo(2026, 8, 10))
        let events = schoolCalendarEvents(ics, from: range.from, toExclusive: range.toExclusive)

        XCTAssertEqual(
            events.map(\.title),
            [
                "Staff Intro week, campus",      // 10 Aug, all-day, proves `\,`
                "Advisor check in",              // 10 Aug 08:30, weekly RRULE from 2025
                "Year 2 Red Cross Day",          // 13 Aug, all-day, 3 days
                "Year 1 arrival in Bergen",      // 14 Aug, all-day
                "Partial eclipse visible in Norway" // 14 Aug 14:00, proves unfolding
            ]
        )
    }

    /// [I] synthesized fixture — `STATUS:CANCELLED` is dropped, not rendered.
    func testCancelledEventIsSkippedEntirely() throws {
        let ics = try fixture("school-calendar")
        let range = week(from: try oslo(2026, 8, 10))
        let events = schoolCalendarEvents(ics, from: range.from, toExclusive: range.toExclusive)

        XCTAssertFalse(events.contains { $0.title == "Should not appear" })
    }

    /// [I] synthesized fixture — a one-day all-day event, its id, and `\n` unescaping.
    func testAllDayEventCarriesOsloMidnightBoundsAndUnescapedNotes() throws {
        let ics = try fixture("school-calendar")
        let range = week(from: try oslo(2026, 8, 10))
        let events = schoolCalendarEvents(ics, from: range.from, toExclusive: range.toExclusive)

        let arrival = try XCTUnwrap(events.first { $0.title == "Year 1 arrival in Bergen" })
        XCTAssertTrue(arrival.isAllDay)
        XCTAssertEqual(arrival.date, try oslo(2026, 8, 14))
        XCTAssertEqual(arrival.start, try oslo(2026, 8, 14))
        XCTAssertEqual(arrival.end, try oslo(2026, 8, 15))
        XCTAssertEqual(arrival.source, .schoolCalendar)
        XCTAssertEqual(arrival.id, "gcal-allday-arrival/20260814T000000")
        XCTAssertEqual(arrival.notes, "Welcome to RCN.\nNational dress optional.")
        XCTAssertNil(arrival.room)
        XCTAssertTrue(SchoolCalendar.isSchoolCalendarEvent(arrival))
    }

    /// [I] synthesized fixture — **the end-exclusivity rule**. `DTEND:20260816`
    /// on an all-day event means the 16th is NOT covered. An off-by-one here
    /// paints a phantom day in the UI.
    func testAllDayDTENDIsExclusive() throws {
        let ics = try fixture("school-calendar")
        let range = week(from: try oslo(2026, 8, 10))
        let events = schoolCalendarEvents(ics, from: range.from, toExclusive: range.toExclusive)

        let redCross = try XCTUnwrap(events.first { $0.title == "Year 2 Red Cross Day" })
        XCTAssertTrue(redCross.isAllDay)
        XCTAssertEqual(redCross.start, try oslo(2026, 8, 13))
        XCTAssertEqual(redCross.end, try oslo(2026, 8, 16), "the exclusive end instant is kept verbatim")

        XCTAssertEqual(
            ICSCalendarParser.lastCoveredDay(
                start: try XCTUnwrap(redCross.start),
                end: try XCTUnwrap(redCross.end),
                calendar: W4Dates.calendar
            ),
            try oslo(2026, 8, 15),
            "13 → 16 exclusive covers the 15th last"
        )

        let perDay = SchoolCalendar.expandAcrossDays(redCross)
        XCTAssertEqual(
            perDay.map(\.date),
            [try oslo(2026, 8, 13), try oslo(2026, 8, 14), try oslo(2026, 8, 15)],
            "13, 14 and 15 — never the 16th"
        )
        XCTAssertTrue(perDay.allSatisfy(\.isAllDay))
        XCTAssertEqual(perDay.map(\.title), Array(repeating: "Year 2 Red Cross Day", count: 3))
        XCTAssertEqual(Set(perDay.map(\.id)).count, 3, "each day slice gets its own id")
    }

    /// [I] synthesized fixture — a single-day event is not sliced.
    func testSingleDayEventIsNotExpanded() throws {
        let ics = try fixture("school-calendar")
        let range = week(from: try oslo(2026, 8, 10))
        let events = schoolCalendarEvents(ics, from: range.from, toExclusive: range.toExclusive)

        let arrival = try XCTUnwrap(events.first { $0.title == "Year 1 arrival in Bergen" })
        let expanded = SchoolCalendar.expandAcrossDays(arrival)
        XCTAssertEqual(expanded.count, 1)
        XCTAssertEqual(expanded.first?.id, arrival.id)
    }

    /// [I] synthesized fixture — folded `SUMMARY` and an explicit `TZID`.
    func testFoldedSummaryAndTZIDTime() throws {
        let ics = try fixture("school-calendar")
        let range = week(from: try oslo(2026, 8, 10))
        let events = schoolCalendarEvents(ics, from: range.from, toExclusive: range.toExclusive)

        let eclipse = try XCTUnwrap(events.first { $0.title == "Partial eclipse visible in Norway" })
        XCTAssertFalse(eclipse.isAllDay)
        XCTAssertEqual(eclipse.start, try oslo(2026, 8, 14, 14, 0))
        XCTAssertEqual(eclipse.end, try oslo(2026, 8, 14, 15, 0))
        XCTAssertEqual(eclipse.room, "Outside")
    }

    /// [I] synthesized fixture — `\,` unescaping inside a SUMMARY.
    func testEscapedCommaIsUnescaped() throws {
        let ics = try fixture("school-calendar")
        let range = week(from: try oslo(2026, 8, 10))
        let events = schoolCalendarEvents(ics, from: range.from, toExclusive: range.toExclusive)

        XCTAssertTrue(events.contains { $0.title == "Staff Intro week, campus" })
        XCTAssertFalse(events.contains { $0.title.contains("\\") })
    }

    // MARK: - Week 34 of 2026 (17–23 August)

    /// [I] synthesized fixture — a `Z` timestamp converts to Oslo wall clock.
    /// 11:30 UTC in August is 13:30 in Europe/Oslo (CEST).
    func testUTCDateTimeConvertsToOslo() throws {
        let ics = try fixture("school-calendar")
        let range = week(from: try oslo(2026, 8, 17))
        let events = schoolCalendarEvents(ics, from: range.from, toExclusive: range.toExclusive)

        let meeting = try XCTUnwrap(events.first { $0.title == "First College Meeting" })
        XCTAssertEqual(meeting.start, try oslo(2026, 8, 18, 13, 30))
        XCTAssertEqual(meeting.end, try oslo(2026, 8, 18, 14, 30))
        XCTAssertEqual(meeting.room, "Auditorium")
        XCTAssertEqual(meeting.notes, "National Dress")
        XCTAssertEqual(meeting.date, try oslo(2026, 8, 18))
    }

    /// [I] synthesized fixture — an event outside the window is absent, and
    /// present once the window is widened.
    func testRangeIsHonouredAtBothEnds() throws {
        let ics = try fixture("school-calendar")

        let week33 = week(from: try oslo(2026, 8, 10))
        let inWeek33 = schoolCalendarEvents(ics, from: week33.from, toExclusive: week33.toExclusive)
        XCTAssertFalse(inWeek33.contains { $0.title == "First College Meeting" })

        let fortnight = (from: try oslo(2026, 8, 10), toExclusive: try oslo(2026, 8, 24))
        let inFortnight = schoolCalendarEvents(
            ics,
            from: fortnight.from,
            toExclusive: fortnight.toExclusive
        )
        XCTAssertTrue(inFortnight.contains { $0.title == "First College Meeting" })
    }

    /// [I] synthesized fixture — an unbounded weekly `BYDAY=MO` rule whose
    /// `DTSTART` is a year before the window still lands on the right Monday.
    func testWeeklyRRULEFromPreviousYearHitsBothMondays() throws {
        let ics = try fixture("school-calendar")

        let week33 = week(from: try oslo(2026, 8, 10))
        let first = schoolCalendarEvents(ics, from: week33.from, toExclusive: week33.toExclusive)
            .filter { $0.title == "Advisor check in" }
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first.first?.start, try oslo(2026, 8, 10, 8, 30))
        XCTAssertEqual(first.first?.end, try oslo(2026, 8, 10, 9, 0))

        let week34 = week(from: try oslo(2026, 8, 17))
        let second = schoolCalendarEvents(ics, from: week34.from, toExclusive: week34.toExclusive)
            .filter { $0.title == "Advisor check in" }
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second.first?.start, try oslo(2026, 8, 17, 8, 30))

        XCTAssertNotEqual(first.first?.id, second.first?.id, "occurrence ids carry the start stamp")
    }

    func testDescriptionHTMLBreaksBecomeNewlines() throws {
        let ics = """
            BEGIN:VCALENDAR
            BEGIN:VEVENT
            DTSTART;VALUE=DATE:20260818
            DTEND;VALUE=DATE:20260819
            SUMMARY:Economics
            DESCRIPTION:Bring calculator&lt;br /&gt;Sit in A 1.2
            UID:html-desc
            END:VEVENT
            END:VCALENDAR
            """
        let events = schoolCalendarEvents(
            ics,
            from: try oslo(2026, 8, 18),
            toExclusive: try oslo(2026, 8, 19)
        )
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.notes, "Bring calculator\nSit in A 1.2")
    }

    // MARK: - Overlay onto a ScheduleWeek

    /// [I] synthesized fixture — overlaying keeps the scraped events and adds
    /// the calendar ones, all-day first.
    func testOverlayMergesIntoAFullSevenDayGrid() throws {
        let ics = try fixture("school-calendar")
        let monday = try oslo(2026, 8, 10)
        let range = week(from: monday)
        let extra = schoolCalendarEvents(ics, from: range.from, toExclusive: range.toExclusive)

        let biology = TimetableEvent(
            id: "ac-w4-1",
            title: "Biology HL",
            source: .academics,
            start: try oslo(2026, 8, 10, 8, 0),
            end: try oslo(2026, 8, 10, 9, 0),
            date: monday
        )

        var days: [ScheduleDay] = []
        for offset in 0..<7 {
            let date = W4Dates.adding(days: offset, to: monday)
            days.append(
                ScheduleDay(
                    date: date,
                    dayName: W4Dates.weekdayName(of: date),
                    events: offset == 0 ? [biology] : []
                )
            )
        }
        let base = ScheduleWeek(year: 2026, week: 33, source: .academics, days: days)

        let merged = SchoolCalendar.overlay(base, with: extra)
        XCTAssertEqual(merged.days.count, 7)

        XCTAssertEqual(
            merged.days[0].events.map(\.title),
            ["Staff Intro week, campus", "Biology HL", "Advisor check in"],
            "all-day first, then by start time"
        )

        XCTAssertEqual(
            merged.days[4].events.map(\.title),
            ["Year 1 arrival in Bergen", "Year 2 Red Cross Day", "Partial eclipse visible in Norway"],
            "Friday 14 Aug carries the middle slice of the multi-day event"
        )

        XCTAssertTrue(merged.days[5].events.contains { $0.title == "Year 2 Red Cross Day" },
                      "Saturday 15 Aug is the last covered day")
        XCTAssertTrue(merged.days[6].events.isEmpty, "Sunday 16 Aug is NOT covered")
    }

    /// [I] synthesized fixture — a weekday-only grid must not swallow a weekend
    /// college event; the missing day is appended instead.
    func testOverlayAppendsDaysTheGridNeverRendered() throws {
        let ics = try fixture("school-calendar")
        let monday = try oslo(2026, 8, 10)
        let range = week(from: monday)
        let extra = schoolCalendarEvents(ics, from: range.from, toExclusive: range.toExclusive)

        let weekdays = (0..<5).map { offset -> ScheduleDay in
            let date = W4Dates.adding(days: offset, to: monday)
            return ScheduleDay(date: date, dayName: W4Dates.weekdayName(of: date))
        }
        let base = ScheduleWeek(year: 2026, week: 33, source: .academics, days: weekdays)

        let merged = SchoolCalendar.overlay(base, with: extra)
        XCTAssertEqual(merged.days.count, 6, "Saturday 15 Aug was appended, Sunday was not")
        XCTAssertEqual(merged.days.last?.date, try oslo(2026, 8, 15))
        XCTAssertEqual(merged.days.last?.events.map(\.title), ["Year 2 Red Cross Day"])
    }

    /// Overlaying nothing is the identity.
    func testOverlayWithNoExtraEventsIsIdentity() throws {
        let monday = try oslo(2026, 8, 10)
        let base = ScheduleWeek(
            year: 2026,
            week: 33,
            source: .academics,
            days: [ScheduleDay(date: monday, dayName: "Monday")]
        )
        XCTAssertEqual(SchoolCalendar.overlay(base, with: []), base)
    }

    /// The week convenience anchors on the ISO Monday, in Oslo.
    func testSchoolCalendarWeekConvenienceMatchesTheExplicitRange() throws {
        let ics = try fixture("school-calendar")
        let range = week(from: try oslo(2026, 8, 10))

        XCTAssertEqual(
            SchoolCalendar.events(ics: ics, year: 2026, week: 33).map(\.id),
            schoolCalendarEvents(ics, from: range.from, toExclusive: range.toExclusive).map(\.id)
        )
    }

    // MARK: - Line unfolding

    /// [I] synthesized markup.
    func testUnfoldJoinsContinuationLinesAndDropsBlankOnes() {
        let raw = "A:1\r\n B\r\n\tC\r\n\r\nD:2\r\n"
        XCTAssertEqual(ICSCalendarParser.unfold(raw), ["A:1BC", "D:2"])
    }

    /// [I] synthesized markup — a tab continuation inside a real VEVENT.
    func testTabFoldedSummaryIsJoined() throws {
        let ics = """
        BEGIN:VCALENDAR\r
        BEGIN:VEVENT\r
        UID:tab-fold\r
        DTSTART;VALUE=DATE:20260812\r
        SUMMARY:Duty week\r
        \t handover\r
        END:VEVENT\r
        END:VCALENDAR\r
        """
        let events = schoolCalendarEvents(
            ics,
            from: try oslo(2026, 8, 10),
            toExclusive: try oslo(2026, 8, 17)
        )
        XCTAssertEqual(events.map(\.title), ["Duty week handover"])
    }

    // MARK: - Escaping

    /// [I] synthesized input.
    func testUnescapeHandlesEveryRFC5545Sequence() {
        XCTAssertEqual(ICSCalendarParser.unescape(#"a\,b\;c\\d\ne\Nf"#), "a,b;c\\d\ne\nf")
        XCTAssertEqual(ICSCalendarParser.unescape("nothing to do"), "nothing to do")
        XCTAssertEqual(ICSCalendarParser.unescape(#"trailing\"#), #"trailing\"#)
    }

    // MARK: - DURATION

    /// [I] synthesized markup — `DURATION` as an alternative to `DTEND`.
    func testDurationIsUsedWhenDTENDIsAbsent() throws {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:duration-timed
        DTSTART;TZID=Europe/Oslo:20260812T100000
        DURATION:PT1H30M
        SUMMARY:Duration timed
        END:VEVENT
        BEGIN:VEVENT
        UID:duration-allday
        DTSTART;VALUE=DATE:20260811
        DURATION:P2D
        SUMMARY:Duration all day
        END:VEVENT
        END:VCALENDAR
        """
        let events = schoolCalendarEvents(
            ics,
            from: try oslo(2026, 8, 10),
            toExclusive: try oslo(2026, 8, 17)
        )

        let timed = try XCTUnwrap(events.first { $0.title == "Duration timed" })
        XCTAssertEqual(timed.start, try oslo(2026, 8, 12, 10, 0))
        XCTAssertEqual(timed.end, try oslo(2026, 8, 12, 11, 30))
        XCTAssertFalse(timed.isAllDay)

        let allDay = try XCTUnwrap(events.first { $0.title == "Duration all day" })
        XCTAssertTrue(allDay.isAllDay)
        XCTAssertEqual(allDay.start, try oslo(2026, 8, 11))
        XCTAssertEqual(allDay.end, try oslo(2026, 8, 13))
        XCTAssertEqual(
            SchoolCalendar.expandAcrossDays(allDay).map(\.date),
            [try oslo(2026, 8, 11), try oslo(2026, 8, 12)],
            "P2D from the 11th covers the 11th and 12th"
        )
    }

    /// [I] synthesized markup — a missing end falls back to one hour / one day.
    func testMissingEndFallsBackToTheRFCDefaults() throws {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:no-end-timed
        DTSTART;TZID=Europe/Oslo:20260812T100000
        SUMMARY:No end timed
        END:VEVENT
        BEGIN:VEVENT
        UID:no-end-allday
        DTSTART;VALUE=DATE:20260812
        SUMMARY:No end all day
        END:VEVENT
        END:VCALENDAR
        """
        let events = schoolCalendarEvents(
            ics,
            from: try oslo(2026, 8, 10),
            toExclusive: try oslo(2026, 8, 17)
        )

        let timed = try XCTUnwrap(events.first { $0.title == "No end timed" })
        XCTAssertEqual(timed.end, try oslo(2026, 8, 12, 11, 0))

        let allDay = try XCTUnwrap(events.first { $0.title == "No end all day" })
        XCTAssertEqual(allDay.end, try oslo(2026, 8, 13))
        XCTAssertEqual(SchoolCalendar.expandAcrossDays(allDay).count, 1)
    }

    /// [I] synthesized markup — a `VALARM`'s own `DURATION` must never be
    /// mistaken for the event's, even when it appears first.
    func testNestedVALARMPropertiesAreIgnored() throws {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:alarmed
        DTSTART;TZID=Europe/Oslo:20260812T100000
        SUMMARY:With alarm
        BEGIN:VALARM
        TRIGGER:-PT10M
        DURATION:PT99H
        ACTION:DISPLAY
        END:VALARM
        DURATION:PT45M
        END:VEVENT
        END:VCALENDAR
        """
        let events = schoolCalendarEvents(
            ics,
            from: try oslo(2026, 8, 10),
            toExclusive: try oslo(2026, 8, 17)
        )
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.end, try oslo(2026, 8, 12, 10, 45))
    }

    // MARK: - EXDATE

    /// [I] synthesized markup — `EXDATE` removes instances from a counted rule.
    func testEXDATERemovesTheNamedInstances() throws {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:daily-standup
        DTSTART;TZID=Europe/Oslo:20260810T090000
        DTEND;TZID=Europe/Oslo:20260810T100000
        RRULE:FREQ=DAILY;COUNT=5
        EXDATE;TZID=Europe/Oslo:20260811T090000,20260813T090000
        SUMMARY:Daily standup
        END:VEVENT
        END:VCALENDAR
        """
        let events = schoolCalendarEvents(
            ics,
            from: try oslo(2026, 8, 10),
            toExclusive: try oslo(2026, 8, 17)
        )

        XCTAssertEqual(
            events.map(\.date),
            [try oslo(2026, 8, 10), try oslo(2026, 8, 12), try oslo(2026, 8, 14)],
            "COUNT=5 generates 10–14 August; the 11th and 13th are excluded"
        )
    }

    /// [I] synthesized markup — a date-only `EXDATE` matches an all-day instance.
    func testDateOnlyEXDATEMatchesAnAllDayInstance() throws {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:allday-series
        DTSTART;VALUE=DATE:20260810
        DTEND;VALUE=DATE:20260811
        RRULE:FREQ=DAILY;COUNT=3
        EXDATE;VALUE=DATE:20260811
        SUMMARY:All day series
        END:VEVENT
        END:VCALENDAR
        """
        let events = schoolCalendarEvents(
            ics,
            from: try oslo(2026, 8, 10),
            toExclusive: try oslo(2026, 8, 17)
        )
        XCTAssertEqual(events.map(\.date), [try oslo(2026, 8, 10), try oslo(2026, 8, 12)])
    }

    // MARK: - Recurrence caps

    /// [I] synthesized markup — an unbounded `FREQ=DAILY` over a ten-year window
    /// is capped, so a runaway rule cannot hang the app.
    func testUnboundedDailyRuleIsCapped() throws {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:runaway-daily
        DTSTART;TZID=Europe/Oslo:20260810T070000
        DTEND;TZID=Europe/Oslo:20260810T073000
        RRULE:FREQ=DAILY
        SUMMARY:Runaway daily
        END:VEVENT
        END:VCALENDAR
        """
        let capped = schoolCalendarEvents(
            ics,
            from: try oslo(2026, 8, 10),
            toExclusive: try oslo(2036, 8, 10)
        )
        XCTAssertEqual(capped.count, ICSCalendarParser.Limits.dailyIterations)

        // Inside a normal week the cap is invisible: seven days, seven lessons.
        let oneWeek = schoolCalendarEvents(
            ics,
            from: try oslo(2026, 8, 10),
            toExclusive: try oslo(2026, 8, 17)
        )
        XCTAssertEqual(oneWeek.count, 7)
        XCTAssertEqual(oneWeek.first?.start, try oslo(2026, 8, 10, 7, 0))
        XCTAssertEqual(oneWeek.last?.start, try oslo(2026, 8, 16, 7, 0))
    }

    /// [I] synthesized markup — an absurd `COUNT` is truncated rather than obeyed.
    func testAbsurdCountIsCapped() throws {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:absurd-count
        DTSTART;TZID=Europe/Oslo:20260810T070000
        DTEND;TZID=Europe/Oslo:20260810T073000
        RRULE:FREQ=DAILY;COUNT=100000
        SUMMARY:Absurd count
        END:VEVENT
        END:VCALENDAR
        """
        let events = schoolCalendarEvents(
            ics,
            from: try oslo(2026, 8, 10),
            toExclusive: try oslo(2036, 8, 10)
        )
        XCTAssertEqual(events.count, ICSCalendarParser.Limits.countedOccurrences)
    }

    /// [I] synthesized markup — `INTERVAL=0` is clamped to 1 and still terminates.
    func testZeroIntervalIsClampedAndTerminates() throws {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:zero-interval
        DTSTART;TZID=Europe/Oslo:20260810T070000
        DTEND;TZID=Europe/Oslo:20260810T073000
        RRULE:FREQ=WEEKLY;INTERVAL=0;BYDAY=MO
        SUMMARY:Zero interval
        END:VEVENT
        END:VCALENDAR
        """
        let events = schoolCalendarEvents(
            ics,
            from: try oslo(2026, 8, 10),
            toExclusive: try oslo(2026, 8, 24)
        )
        XCTAssertEqual(events.map(\.date), [try oslo(2026, 8, 10), try oslo(2026, 8, 17)])
    }

    /// [I] synthesized markup — `UNTIL` ends the series inclusively.
    func testUntilBoundsTheSeries() throws {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:until-daily
        DTSTART;TZID=Europe/Oslo:20260810T070000
        DTEND;TZID=Europe/Oslo:20260810T073000
        RRULE:FREQ=DAILY;UNTIL=20260812T050000Z
        SUMMARY:Until daily
        END:VEVENT
        END:VCALENDAR
        """
        // 05:00 UTC is 07:00 Oslo, so the 12 August occurrence is included.
        let events = schoolCalendarEvents(
            ics,
            from: try oslo(2026, 8, 10),
            toExclusive: try oslo(2026, 8, 17)
        )
        XCTAssertEqual(
            events.map(\.date),
            [try oslo(2026, 8, 10), try oslo(2026, 8, 11), try oslo(2026, 8, 12)]
        )
    }

    /// [I] synthesized markup — an unsupported `FREQ` renders once, not never
    /// and not forever.
    func testUnsupportedFrequencyDegradesToASingleOccurrence() throws {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:hourly
        DTSTART;TZID=Europe/Oslo:20260812T100000
        DTEND;TZID=Europe/Oslo:20260812T110000
        RRULE:FREQ=HOURLY;INTERVAL=2
        SUMMARY:Hourly thing
        END:VEVENT
        END:VCALENDAR
        """
        let events = schoolCalendarEvents(
            ics,
            from: try oslo(2026, 8, 10),
            toExclusive: try oslo(2026, 8, 17)
        )
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.start, try oslo(2026, 8, 12, 10, 0))
    }

    /// [I] synthesized markup — a `RECURRENCE-ID` override replaces exactly one
    /// instance instead of duplicating it.
    func testRecurrenceIDOverrideReplacesOneInstance() throws {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:series
        DTSTART;TZID=Europe/Oslo:20260810T090000
        DTEND;TZID=Europe/Oslo:20260810T100000
        RRULE:FREQ=DAILY;COUNT=3
        SUMMARY:Series
        END:VEVENT
        BEGIN:VEVENT
        UID:series
        RECURRENCE-ID;TZID=Europe/Oslo:20260811T090000
        DTSTART;TZID=Europe/Oslo:20260811T140000
        DTEND;TZID=Europe/Oslo:20260811T150000
        SUMMARY:Series moved
        END:VEVENT
        END:VCALENDAR
        """
        let events = schoolCalendarEvents(
            ics,
            from: try oslo(2026, 8, 10),
            toExclusive: try oslo(2026, 8, 17)
        )

        XCTAssertEqual(events.map(\.title), ["Series", "Series moved", "Series"])
        XCTAssertEqual(events[1].start, try oslo(2026, 8, 11, 14, 0))

        let overriddenSlot = try oslo(2026, 8, 11, 9, 0)
        XCTAssertFalse(
            events.contains { $0.start == overriddenSlot },
            "the overridden 11 August 09:00 instance is gone"
        )
    }

    // MARK: - Timezone threading (bug B21)

    /// [I] synthesized markup — a floating `DTSTART` is read as `zone`'s wall
    /// clock, and the zone is a parameter rather than a hardcoded Oslo.
    func testFloatingTimeFollowsTheRequestedZone() throws {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:floating
        DTSTART:20260812T090000
        DTEND:20260812T100000
        SUMMARY:Floating
        END:VEVENT
        END:VCALENDAR
        """
        let from = try oslo(2026, 8, 10)
        let toExclusive = try oslo(2026, 8, 17)

        let inOslo = schoolCalendarEvents(ics, from: from, toExclusive: toExclusive)
        XCTAssertEqual(inOslo.first?.start, try oslo(2026, 8, 12, 9, 0))

        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let inUTC = schoolCalendarEvents(ics, from: from, toExclusive: toExclusive, zone: utc)
        let osloStart = try XCTUnwrap(inOslo.first?.start)
        let utcStart = try XCTUnwrap(inUTC.first?.start)
        XCTAssertEqual(
            utcStart.timeIntervalSince(osloStart), 7_200,
            "09:00 UTC is two hours after 09:00 CEST — the zone really is threaded through (B21)"
        )
    }

    /// [I] synthesized fixture — a `Z` timestamp names an absolute instant, so
    /// it is identical whichever zone the caller asks for.
    func testUTCInstantsAreZoneIndependent() throws {
        let ics = try fixture("school-calendar")
        let from = try oslo(2026, 8, 17)
        let toExclusive = try oslo(2026, 8, 24)

        let inOslo = schoolCalendarEvents(ics, from: from, toExclusive: toExclusive)
            .first { $0.title == "First College Meeting" }
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let inUTC = schoolCalendarEvents(ics, from: from, toExclusive: toExclusive, zone: utc)
            .first { $0.title == "First College Meeting" }

        XCTAssertEqual(try XCTUnwrap(inOslo?.start), try XCTUnwrap(inUTC?.start))
    }

    /// [I] synthesized markup — a weekly rule keeps its wall-clock time across
    /// the October DST change (Oslo falls back on 25 October 2026).
    func testWeeklyRuleKeepsWallClockTimeAcrossDST() throws {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:dst-weekly
        DTSTART;TZID=Europe/Oslo:20261019T083000
        DTEND;TZID=Europe/Oslo:20261019T093000
        RRULE:FREQ=WEEKLY;BYDAY=MO
        SUMMARY:After the clocks change
        END:VEVENT
        END:VCALENDAR
        """
        let events = schoolCalendarEvents(
            ics,
            from: try oslo(2026, 10, 26),
            toExclusive: try oslo(2026, 11, 2)
        )
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.start, try oslo(2026, 10, 26, 8, 30))
        XCTAssertEqual(events.first?.end, try oslo(2026, 10, 26, 9, 30))
    }

    /// [I] synthesized markup — an unknown `TZID` degrades to the requested zone
    /// instead of throwing or silently producing UTC.
    func testUnknownTZIDFallsBackToTheRequestedZone() throws {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:bad-tzid
        DTSTART;TZID=Customized Time Zone:20260812T090000
        DTEND;TZID=Customized Time Zone:20260812T100000
        SUMMARY:Bad tzid
        END:VEVENT
        END:VCALENDAR
        """
        let events = schoolCalendarEvents(
            ics,
            from: try oslo(2026, 8, 10),
            toExclusive: try oslo(2026, 8, 17)
        )
        XCTAssertEqual(events.first?.start, try oslo(2026, 8, 12, 9, 0))
    }

    // MARK: - Degradation

    /// Unreadable input yields nothing and never throws.
    func testUnreadableInputDegradesToEmpty() throws {
        let from = try oslo(2026, 8, 10)
        let toExclusive = try oslo(2026, 8, 17)

        XCTAssertTrue(schoolCalendarEvents("", from: from, toExclusive: toExclusive).isEmpty)
        XCTAssertTrue(
            schoolCalendarEvents("<html>login page</html>", from: from, toExclusive: toExclusive).isEmpty
        )
        XCTAssertTrue(
            schoolCalendarEvents(
                "BEGIN:VCALENDAR\nBEGIN:VEVENT\nSUMMARY:No start\nEND:VEVENT\nEND:VCALENDAR",
                from: from,
                toExclusive: toExclusive
            ).isEmpty,
            "a VEVENT without DTSTART is dropped, not guessed at"
        )
        XCTAssertTrue(
            schoolCalendarEvents(
                "BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:x\nDTSTART;VALUE=DATE:20260812\nEND:VEVENT",
                from: from,
                toExclusive: toExclusive
            ).isEmpty,
            "a VEVENT without SUMMARY has nothing to render"
        )
    }

    /// An empty or inverted range yields nothing.
    func testEmptyAndInvertedRangesYieldNothing() throws {
        let ics = try fixture("school-calendar")
        let monday = try oslo(2026, 8, 10)

        XCTAssertTrue(schoolCalendarEvents(ics, from: monday, toExclusive: monday).isEmpty)
        XCTAssertTrue(
            schoolCalendarEvents(ics, from: try oslo(2026, 8, 17), toExclusive: monday).isEmpty
        )
    }

    /// Real feeds are CRLF-lined, and **Swift treats CRLF as a single
    /// `Character`** — splitting on `"\n"` silently returns the whole calendar
    /// as one line and yields zero events. Parsing the fixture both ways must
    /// give byte-identical results.
    func testCRLFAndLFLineEndingsParseIdentically() throws {
        let lf = try fixture("school-calendar")
        let crlf = lf
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: "\r\n")
        let range = week(from: try oslo(2026, 8, 10))

        let fromLF = schoolCalendarEvents(lf, from: range.from, toExclusive: range.toExclusive)
        let fromCRLF = schoolCalendarEvents(crlf, from: range.from, toExclusive: range.toExclusive)

        XCTAssertFalse(fromCRLF.isEmpty)
        XCTAssertEqual(fromCRLF.map(\.id), fromLF.map(\.id))
        XCTAssertEqual(fromCRLF.map(\.title), fromLF.map(\.title))
        XCTAssertEqual(fromCRLF.map(\.start), fromLF.map(\.start))
    }

    // MARK: - Personal feed hygiene

    /// The `token=` value is password-equivalent: it must not survive into any
    /// string a human or a log can see. The token below is a placeholder — no
    /// real one may ever appear in this file.
    func testPersonalFeedNeverPrintsItsToken() throws {
        let placeholder = "PLACEHOLDER-NOT-A-REAL-TOKEN-0000"
        let url = try XCTUnwrap(
            URL(string: "https://w4.uwcrcn.no/index.php?r=academics/feeds/acttical&token=\(placeholder)")
        )
        let feed = PersonalFeed(kind: .acTimetableICS, url: url)

        XCTAssertFalse(feed.redactedURLText.contains(placeholder))
        XCTAssertFalse("\(feed)".contains(placeholder))
        XCTAssertFalse(String(describing: feed).contains(placeholder))
        XCTAssertFalse(String(reflecting: feed).contains(placeholder))
        XCTAssertTrue(feed.redactedURLText.contains("acttical"), "the route stays legible")
        XCTAssertTrue(feed.redactedURLText.contains(PersonalFeed.redactionMarker))
        XCTAssertEqual(feed.url.absoluteString, url.absoluteString, "the real URL is still usable")
    }

    /// Google's `/private-<key>/` path form and embedded credentials are
    /// redacted too.
    func testRedactionCoversPathSecretsAndCredentials() throws {
        let url = try XCTUnwrap(
            URL(string: "https://user:pw@calendar.google.com/calendar/ical/x/private-SECRETKEY/basic.ics")
        )
        let redacted = PersonalFeed.redacted(url)
        XCTAssertFalse(redacted.contains("SECRETKEY"))
        XCTAssertFalse(redacted.contains("pw@"))
        XCTAssertTrue(redacted.contains("basic.ics"))
    }

    func testPersonalFeedRoutesMatchTheREADME() {
        XCTAssertEqual(PersonalFeedKind.acTimetableICS.route, "academics/feeds/acttical")
        XCTAssertEqual(PersonalFeedKind.eaTimetableICS.route, "academics/feeds/eattical")
        XCTAssertEqual(PersonalFeedKind.combinedICS.route, "academics/feeds/combottical")
        XCTAssertEqual(PersonalFeedKind.assessmentsICS.route, "academics/feeds/sassttical")
        XCTAssertEqual(PersonalFeedKind.acTimetableRSS.route, "academics/feeds/acttrss")

        XCTAssertEqual(PersonalFeedKind.allCases.count, 8)
        XCTAssertEqual(PersonalFeedKind.allCases.filter(\.isCalendar).count, 4)
    }

    /// The overlay ships on by default, matching Android.
    func testSchoolCalendarConstants() {
        XCTAssertTrue(SchoolCalendar.isEnabledByDefault)
        XCTAssertEqual(SchoolCalendar.idPrefix, "gcal-")
        XCTAssertEqual(SchoolCalendar.cacheTTL, 6 * 60 * 60)
        XCTAssertNotNil(SchoolCalendar.icsURL)
    }

    func testVisibleEventsHidesSchoolCalendarWhenToggledOff() throws {
        let range = week(from: try oslo(2026, 8, 10))
        let calendar = try XCTUnwrap(
            schoolCalendarEvents(try fixture("school-calendar"), from: range.from, toExclusive: range.toExclusive)
                .first { $0.title == "Year 1 arrival in Bergen" }
        )
        let lesson = TimetableEvent(
            id: "ac-1",
            title: "Biology HL",
            subject: "Biology HL",
            source: .academics,
            start: calendar.start,
            end: calendar.end,
            date: calendar.date,
            room: nil,
            teacher: nil,
            teacherUwcId: nil,
            status: .normal,
            attendance: nil,
            isAllDay: false,
            href: nil,
            notes: nil,
            rawTooltip: nil
        )
        let events = [lesson, calendar]
        XCTAssertEqual(
            SchoolCalendar.visibleEvents(events, showSchoolCalendar: true).map(\.id),
            events.map(\.id)
        )
        let hidden = SchoolCalendar.visibleEvents(events, showSchoolCalendar: false)
        XCTAssertEqual(hidden.map(\.id), [lesson.id])
        XCTAssertFalse(hidden.contains(where: SchoolCalendar.isSchoolCalendarEvent))
    }

    /// Overlay events keep the calendar's own title and stay out of the
    /// subject-mapping catalogue. A W4 lesson with the same wording still maps.
    func testSchoolCalendarEventsSkipSubjectMapping() throws {
        SubjectMapper.mappingProvider = nil
        SubjectMapper.subjectInfoProvider = nil

        let monday = try oslo(2026, 8, 10)
        let calendar = TimetableEvent(
            id: "gcal-tok",
            title: "TOK",
            source: .schoolCalendar,
            date: monday
        )
        let lesson = TimetableEvent(
            id: "ac-tok",
            title: "TOK",
            source: .academics,
            date: monday
        )

        XCTAssertEqual(lesson.displayTitle, "Theory of Knowledge")
        XCTAssertEqual(calendar.displayTitle, "TOK")
        XCTAssertEqual(calendar.iconName, "calendar")
        XCTAssertNotEqual(lesson.iconName, "calendar")

        let keys = SchoolCalendar.subjectMappingKeys(from: [lesson, calendar])
        XCTAssertEqual(Set(keys), ["TOK"])
    }

    func testSubjectMappingKeysIgnoreOverlayTitles() throws {
        let range = week(from: try oslo(2026, 8, 10))
        let overlay = schoolCalendarEvents(
            try fixture("school-calendar"),
            from: range.from,
            toExclusive: range.toExclusive
        )
        let lesson = TimetableEvent(
            id: "ac-1",
            title: "Biology HL",
            source: .academics,
            date: try oslo(2026, 8, 10)
        )
        let keys = Set(SchoolCalendar.subjectMappingKeys(from: overlay + [lesson]))
        XCTAssertEqual(keys, ["Biology HL"])
        XCTAssertFalse(keys.contains("Year 1 arrival in Bergen"))
        XCTAssertFalse(keys.contains("Advisor check in"))
    }
}
