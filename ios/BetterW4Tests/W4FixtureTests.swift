//
//  W4FixtureTests.swift
//  BetterW4Tests
//
//  Fixture tests for the sanitized W4 captures in `Fixtures/W4/`.
//
//  These lock down the markup we have actually seen from https://w4.uwcrcn.no
//  (Yii 1, "W4 v. 25.9.1"). They are written against SwiftSoup directly rather
//  than against app parsers on purpose: the W4 parsers are still being written,
//  and the job of this file is to pin the captured HTML down now so that
//  whatever parser lands has a fixed, honest target.
//
//  Nothing here asserts anything the captures do not actually contain. In
//  particular the captured week is a *holiday* week with zero lesson blocks —
//  see the REVISIT comment on `testHomeTimetableCapturedWeekHasNoLessons`.
//
//  Fixture hygiene (docs/spec/reviewer-notes.md section 8): the names and UWC
//  ids in these captures are placeholders and the image binaries were dropped.
//

import Foundation
import XCTest
import SwiftSoup
@testable import BetterW4

final class W4FixtureTests: XCTestCase {

    // MARK: - Fixtures

    private static let homeFixture = "home"
    private static let academicsMenuFixture = "academics-menu"
    private static let extraAcademicsMenuFixture = "extraacademics-menu"
    private static let schoolMenuFixture = "school-menu"
    private static let documentsFixture = "documents"

    private static let allFixtures = [
        homeFixture,
        academicsMenuFixture,
        extraAcademicsMenuFixture,
        schoolMenuFixture,
        documentsFixture
    ]

    /// Resolves a fixture from the test bundle. Xcode's file-system
    /// synchronized group copies `Fixtures/W4/*.html` into the bundle, but
    /// whether the folder structure survives depends on how the resource is
    /// synchronized, so every plausible bundle location is tried first. The
    /// last resort is the checked-in source file, which keeps the suite honest
    /// if the resources ever stop being copied.
    private func fixtureURL(_ name: String) throws -> URL {
        let bundle = Bundle(for: Self.self)
        let bundled = [
            bundle.url(forResource: name, withExtension: "html", subdirectory: "Fixtures/W4"),
            bundle.url(forResource: name, withExtension: "html", subdirectory: "W4"),
            bundle.url(forResource: name, withExtension: "html")
        ].compactMap { $0 }.first
        if let bundled {
            return bundled
        }

        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/W4/\(name).html")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: source.path),
            "W4 fixture \(name).html is missing from both the test bundle and the source tree"
        )
        return source
    }

    private func html(_ name: String) throws -> String {
        try String(contentsOf: try fixtureURL(name), encoding: .utf8)
    }

    private func document(_ name: String) throws -> Document {
        try SwiftSoup.parse(try html(name))
    }

    // MARK: - Helpers

    /// `https://w4.uwcrcn.no/index.php?r=academics/timetable/mytimetable`
    /// -> `academics/timetable/mytimetable`
    private func route(of href: String) -> String? {
        URLComponents(string: href)?
            .queryItems?
            .first(where: { $0.name == "r" })?
            .value
    }

    private func queryValue(_ name: String, in href: String) -> String? {
        URLComponents(string: href)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }

    private func routes(in element: Element) throws -> [String] {
        try element.select("a[href]").array().compactMap { try route(of: $0.attr("href")) }
    }

    private func matchGroups(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        var groups: [String] = []
        for index in 1..<match.numberOfRanges {
            guard let groupRange = Range(match.range(at: index), in: text) else { return nil }
            groups.append(String(text[groupRange]))
        }
        return groups
    }

    private func firstMatch(_ pattern: String, in text: String) -> String? {
        matchGroups(pattern, in: text)?.first
    }

    /// The UWC id pattern from the reviewer notes section 6: `nc` + 2-digit
    /// entry year + letters.
    private func uwcID(inHref href: String) -> String? {
        firstMatch(#"uwc_id=(nc\d{2}[a-z]+)"#, in: href)
    }

    private static let w4DateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Oslo") ?? TimeZone(secondsFromGMT: 0)!
        formatter.dateFormat = "dd-MMM-yyyy"
        return formatter
    }()

    private static let osloCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo") ?? TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    // MARK: - Identity chrome (home.html)

    func testHomeWelcomeNameLivesInUserPanel() throws {
        let doc = try document(Self.homeFixture)
        let panel = try XCTUnwrap(doc.select("#user-panel .right").first())

        // The display name is the first text node of `#user-panel .right`,
        // before the <br> and the Logout / Profile / Password links.
        let welcomeLine = panel.getChildNodes()
            .compactMap { ($0 as? TextNode)?.getWholeText() }
            .first(where: { $0.contains("Welcome,") })
        let line = try XCTUnwrap(welcomeLine).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(line, "Welcome, Alex Andersen")
        XCTAssertEqual(firstMatch(#"^Welcome,\s*(.+)$"#, in: line), "Alex Andersen")

        XCTAssertEqual(try routes(in: panel), ["site/logout", "site/profile", "site/password"])
    }

    func testHomeUWCIDComesFromTheOwnPublicProfileLink() throws {
        let doc = try document(Self.homeFixture)

        // Reviewer notes section 6: the signed-in student's own id comes from
        // the `#hello` block.
        let hello = try XCTUnwrap(doc.select("#hello").first())
        XCTAssertTrue(try hello.text().contains("Hello Alex Andersen"))

        let profileLink = try XCTUnwrap(hello.select("a[href]").first())
        let href = try profileLink.attr("href")
        XCTAssertEqual(route(of: href), "people/students/student")
        XCTAssertEqual(uwcID(inHref: href), "nc26abcd")
        XCTAssertEqual(try profileLink.text(), "W4 public profile")

        // The same selector unscoped also matches birthday thumbnails, so
        // identity extraction has to stay scoped to `#hello`.
        let studentLinks = try doc.select("a[href]").array().filter { element in
            let href = try element.attr("href")
            return route(of: href) == "people/students/student" && uwcID(inHref: href) != nil
        }
        XCTAssertEqual(studentLinks.count, 3)
    }

    func testHomeReportsW4Version() throws {
        let doc = try document(Self.homeFixture)
        let version = try XCTUnwrap(doc.select("#version").first())
        XCTAssertEqual(try version.text(), "W4 v. 25.9.1")

        let relnotes = try XCTUnwrap(version.select("a[href]").first())
        XCTAssertEqual(try relnotes.text(), "25.9.1")
        XCTAssertEqual(route(of: try relnotes.attr("href")), "site/relnotes")
    }

    // MARK: - Campus status control

    func testCampusStatusDropdownReadsOnCampus() throws {
        let doc = try document(Self.homeFixture)
        let status = try XCTUnwrap(doc.select(".status-dropdown .status").first())
        XCTAssertTrue(try status.hasClass("oncampus"))

        let value = try XCTUnwrap(status.select(".status-value").first())
        XCTAssertEqual(try value.text(), "on campus")

        // `.location` is present but empty while on campus.
        let location = try XCTUnwrap(status.select(".location").first())
        XCTAssertTrue(try location.text().isEmpty)
    }

    func testCampusStatusLocationOptions() throws {
        let doc = try document(Self.homeFixture)
        let radios = try doc.select("#location input[type=radio]").array()
        let values = try radios.map { try $0.attr("value") }

        // The radio values are the literal location labels W4 expects back in
        // the `location` field of `r=site/setstatus`.
        XCTAssertEqual(values, [
            "oncampus",
            "On a walk",
            "At Raudbua",
            "On Jarstadheia",
            "On the island",
            "In Flekke",
            "In Dale",
            "In A building (after 10:30pm)",
            "In K building (after 10:30pm)",
            "In Library/Study room (after 10:30pm)",
            "other"
        ])
        XCTAssertTrue(values.contains("On a walk"))
        XCTAssertTrue(values.contains("At Raudbua"))

        // Radio ids and their labels line up one to one (`location_0` … `location_10`).
        for (index, radio) in radios.enumerated() {
            let id = try radio.attr("id")
            XCTAssertEqual(id, "location_\(index)")
            let label = try XCTUnwrap(doc.select("label[for=\(id)]").first())
            XCTAssertFalse(try label.text().isEmpty)
        }
        let labels = try doc.select("#location label").array().map { try $0.text() }
        XCTAssertEqual(labels.first, "On campus")
        XCTAssertEqual(labels.last, "Other")

        // Exactly one option is pre-selected, and it is the on-campus one.
        let checked = try doc.select("#location input[checked]").array()
        XCTAssertEqual(checked.count, 1)
        XCTAssertEqual(try checked.first?.attr("value"), "oncampus")

        // Free-text field for `other`, capped at 20 characters (README 5.3).
        let other = try XCTUnwrap(doc.select("#other").first())
        XCTAssertEqual(try other.attr("name"), "other")
        XCTAssertEqual(try other.attr("maxlength"), "20")

        // The submit control is a plain Yii button name/value pair.
        let submit = try XCTUnwrap(doc.select("#submit-campus-status").first())
        XCTAssertEqual(try submit.attr("name"), "yt0")
        XCTAssertEqual(try submit.attr("value"), "Set status")

        // The POST target is published by the page script, not by the markup.
        XCTAssertTrue(try html(Self.homeFixture).contains("site\\x2Fsetstatus"))
    }

    // MARK: - Timetable header

    func testHomeTimetableHeaderSpansMondayToSunday() throws {
        let doc = try document(Self.homeFixture)

        let heading = try XCTUnwrap(doc.select("#timetable h3").first())
        XCTAssertEqual(try heading.text(), "August 2026, week 33")

        let headerCells = try doc.select("#timetable-header .header-row .header-cell").array()
        XCTAssertEqual(headerCells.count, 8, "one empty gutter header plus seven days")
        XCTAssertTrue(try headerCells[0].hasClass("first"))

        let dayCells = Array(headerCells.dropFirst())
        XCTAssertEqual(dayCells.count, 7)

        let dayNames = try dayCells.map { try $0.select(".day-name").first()?.text() ?? "" }
        XCTAssertEqual(dayNames, [
            "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"
        ])

        let dates = try dayCells.compactMap { cell -> String? in
            firstMatch(#"(\d{1,2}-[A-Za-z]{3}-\d{4})"#, in: try cell.text())
        }
        XCTAssertEqual(dates, [
            "10-Aug-2026", "11-Aug-2026", "12-Aug-2026",
            "13-Aug-2026", "14-Aug-2026", "15-Aug-2026", "16-Aug-2026"
        ])

        // The `dd-MMM-yyyy` line really does parse, and really is Mon…Sun.
        let parsed = dates.compactMap { Self.w4DateFormatter.date(from: $0) }
        XCTAssertEqual(parsed.count, 7)
        XCTAssertEqual(
            Self.osloCalendar.component(.weekday, from: try XCTUnwrap(parsed.first)),
            2,
            "10-Aug-2026 is a Monday"
        )
        XCTAssertEqual(
            Self.osloCalendar.component(.weekday, from: try XCTUnwrap(parsed.last)),
            1,
            "16-Aug-2026 is a Sunday"
        )

        let rotationDays = try dayCells.map { try $0.select(".rotation-day").first()?.text() ?? "" }
        XCTAssertEqual(rotationDays, [
            "Day 1", "Day 2", "Day 3", "Day 4", "Day 5", "Weekend", "Weekend"
        ])

        // Weekends carry `.no-classes`; weekdays do not.
        for (index, cell) in dayCells.enumerated() {
            let rotation = try XCTUnwrap(cell.select(".rotation-day").first())
            XCTAssertEqual(try rotation.hasClass("no-classes"), index >= 5, "day index \(index)")
        }

        // Every day in this capture carries the empty Extra Academics line.
        for cell in dayCells {
            XCTAssertTrue(try cell.text().contains("No EA"))
        }
    }

    // MARK: - Timetable grid

    func testHomeTimetableGridGeometry() throws {
        let doc = try document(Self.homeFixture)

        // Quirk worth knowing: `id="timetable"` appears twice — once on the
        // whole widget (heading + header + grid) and once on the grid itself.
        // A `getElementById`-style lookup returns the outer one.
        XCTAssertEqual(try doc.select("#timetable").array().count, 2)

        let columns = try doc.select("#timetable .column").array()
        XCTAssertEqual(columns.count, 8, "one hour gutter plus seven day columns")
        for column in columns {
            XCTAssertEqual(try column.attr("style"), "height: 900px")
        }

        // Column 0 is the hour gutter: 15 labels, 7:00 through 22:00.
        let gutterCells = try columns[0].select(".cell").array()
        XCTAssertEqual(gutterCells.count, 15)
        let labels = try gutterCells.map { try $0.text() }
        XCTAssertEqual(labels.first, "7:00 \u{2014} 8:00")
        XCTAssertEqual(labels.last, "21:00 \u{2014} 22:00")
        // The separator is an em dash (U+2014), not a hyphen; any time-range
        // regex has to accept it.
        XCTAssertTrue(labels.allSatisfy { $0.contains("\u{2014}") })
        let starts = labels.compactMap { firstMatch(#"^(\d{1,2}):00"#, in: $0) }
        XCTAssertEqual(starts, (7...21).map { String($0) })

        // 15 hours over 900 px is 1 px per minute, offset from 07:00. The page
        // script publishes the same bounds.
        let height = try XCTUnwrap(
            firstMatch(#"height:\s*(\d+)px"#, in: try columns[0].attr("style")).flatMap { Int($0) }
        )
        XCTAssertEqual(height, 900)
        XCTAssertEqual(height / gutterCells.count, 60, "60 px per hour, i.e. 1 px per minute")

        let source = try html(Self.homeFixture)
        XCTAssertTrue(source.contains("tt_start_hour = 7"))
        XCTAssertTrue(source.contains("tt_end_hour = 22"))

        // The seven day columns hold no hour labels of their own.
        let dayColumns = Array(columns.dropFirst())
        XCTAssertEqual(dayColumns.count, 7)
        for column in dayColumns {
            XCTAssertTrue(try column.select(".cell").array().isEmpty)
        }
    }

    func testHomeTimetableMarksTodayWithTheCurrentTimeLine() throws {
        let doc = try document(Self.homeFixture)

        let currentColumns = try doc.select("#timetable .column.current").array()
        XCTAssertEqual(currentColumns.count, 1, "exactly one day column is 'today'")

        let dayColumns = Array(try doc.select("#timetable .column").array().dropFirst())
        let currentIndex = try dayColumns.firstIndex { try $0.hasClass("current") }
        XCTAssertEqual(currentIndex, 4, "the capture was taken on Friday 14-Aug-2026")

        let marker = try XCTUnwrap(currentColumns[0].select("#current_time").first())
        let minutesFromSeven = try XCTUnwrap(
            firstMatch(#"top:\s*(\d+)px"#, in: try marker.attr("style")).flatMap { Int($0) }
        )
        XCTAssertEqual(minutesFromSeven, 394)
        // 1 px == 1 minute from 07:00, so this capture is stamped 13:34.
        XCTAssertEqual(7 + minutesFromSeven / 60, 13)
        XCTAssertEqual(minutesFromSeven % 60, 34)

        // The marker only ever appears inside the current column.
        XCTAssertEqual(try doc.select("#current_time").array().count, 1)
    }

    /// REVISIT WHEN A TERM-TIME CAPTURE EXISTS.
    ///
    /// August 2026 week 33 is a holiday week: the captured grid contains zero
    /// lesson blocks. `.period` — and everything the Android parser expects
    /// inside it (`.inner`, `.datetime`, `.room`, the absence markers) — has
    /// never been seen in a real capture. This test asserts the *absence* so
    /// that nobody mistakes an empty parse for a verified one. Do not "fix" it
    /// by inventing lesson markup; capture a real term-time
    /// `r=academics/timetable/mytimetable` page instead.
    func testHomeTimetableCapturedWeekHasNoLessons() throws {
        let doc = try document(Self.homeFixture)

        XCTAssertTrue(
            try doc.select(".period").array().isEmpty,
            "the captured week is a holiday week and has no lesson blocks"
        )

        let dayColumns = Array(try doc.select("#timetable .column").array().dropFirst())
        XCTAssertEqual(dayColumns.count, 7, "seven days, Monday through Sunday")

        for (index, column) in dayColumns.enumerated() {
            let unexpected = try column.children().array().filter { try $0.attr("id") != "current_time" }
            XCTAssertTrue(
                unexpected.isEmpty,
                "day column \(index) should contain nothing but the optional time marker"
            )
            XCTAssertTrue(
                try column.text().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "day column \(index) should carry no lesson text"
            )
        }
    }

    // MARK: - Attendance meters

    func testHomeAttendanceMeters() throws {
        let doc = try document(Self.homeFixture)
        let meterPattern = #"You have (\d+) absences? and (\d+) latenesses? so far"#

        let academic = try XCTUnwrap(doc.select("#academic-absences").first())
        XCTAssertEqual(try academic.select("h3").first()?.text(), "Academics Attendance Meter")
        XCTAssertEqual(try XCTUnwrap(matchGroups(meterPattern, in: try academic.text())), ["0", "0"])
        XCTAssertEqual(try routes(in: academic), ["people/students/absences"])

        let ea = try XCTUnwrap(doc.select("#ea-absences").first())
        XCTAssertEqual(try ea.select("h3").first()?.text(), "EA Attendance Meter")
        XCTAssertEqual(try XCTUnwrap(matchGroups(meterPattern, in: try ea.text())), ["0", "0"])
        XCTAssertEqual(try routes(in: ea), ["people/students/eaabsences"])
    }

    // MARK: - Birthdays

    func testHomeBirthdaysToday() throws {
        let doc = try document(Self.homeFixture)
        let items = try doc.select("#birthdays-today li").array()
        XCTAssertEqual(items.count, 3)

        var ids: [String] = []
        for item in items {
            let link = try XCTUnwrap(item.select("a[href]").first())
            let href = try link.attr("href")
            ids.append(try XCTUnwrap(uwcID(inHref: href), "birthday entry links no uwc_id: \(href)"))

            let personRoute = try XCTUnwrap(route(of: href))
            XCTAssertTrue(
                personRoute == "people/students/student" || personRoute == "people/staff/staff",
                "unexpected birthday route \(personRoute)"
            )

            let photo = try XCTUnwrap(item.select("img.photo").first())
            XCTAssertEqual(try photo.attr("width"), "40")
            XCTAssertTrue(try photo.attr("src").hasSuffix("_thumb.jpg"))
        }
        XCTAssertEqual(ids, ["nc16efgh", "nc19ijkl", "nc25mnop"])
    }

    func testHomeBirthdaysTomorrow() throws {
        let doc = try document(Self.homeFixture)
        let items = try doc.select("#birthdays-tomorrow li").array()
        XCTAssertGreaterThanOrEqual(items.count, 1)

        let link = try XCTUnwrap(items[0].select("a[href]").first())
        let href = try link.attr("href")
        XCTAssertEqual(route(of: href), "people/students/student")
        XCTAssertEqual(uwcID(inHref: href), "nc25qrst")
    }

    // MARK: - sdmenu pages

    func testAcademicsSideMenuRoutes() throws {
        let doc = try document(Self.academicsMenuFixture)
        let menu = try XCTUnwrap(doc.select("#dynamic_menu_academics").first())
        XCTAssertTrue(try menu.hasClass("sdmenu"))

        let sections = try menu.children().array().map { try $0.select("span").first()?.text() ?? "" }
        XCTAssertEqual(sections, ["My Academics", "Academics", "Trips", "Resources"])

        let menuRoutes = Set(try routes(in: menu))
        for expected in [
            "academics/deadlines",
            "academics/timetable/mytimetable",
            "people/students/absences",
            "people/students/absences/register",
            "academics/classes/myclasses",
            "academics/grades/grades",
            "academics/feeds",
            "academics/trips",
            "academics/resources/resources"
        ] {
            XCTAssertTrue(menuRoutes.contains(expected), "missing route \(expected)")
        }
    }

    func testExtraAcademicsSideMenuRoutes() throws {
        let doc = try document(Self.extraAcademicsMenuFixture)
        let menu = try XCTUnwrap(doc.select("#dynamic_menu_extraacademics").first())
        XCTAssertTrue(try menu.hasClass("sdmenu"))

        let sections = try menu.children().array().map { try $0.select("span").first()?.text() ?? "" }
        XCTAssertEqual(sections, ["My Extra Academics", "Extra Academics"])

        let menuRoutes = Set(try routes(in: menu))
        for expected in [
            "extraacademics/timetable/mytimetable",
            "extraacademics/activities/myactivities",
            "extraacademics/activities/myactivities/diary",
            "extraacademics/activities/myportfolio",
            "extraacademics/safetynet/mysafetynet",
            "extraacademics/activities/ea",
            "people/students/eaabsences"
        ] {
            XCTAssertTrue(menuRoutes.contains(expected), "missing route \(expected)")
        }
    }

    func testSchoolSideMenuRoutes() throws {
        let doc = try document(Self.schoolMenuFixture)
        // The School tab's side menu is keyed on `people`, not `school`.
        let menu = try XCTUnwrap(doc.select("#dynamic_menu_people").first())
        XCTAssertTrue(try menu.hasClass("sdmenu"))

        let sections = try menu.children().array().map { try $0.select("span").first()?.text() ?? "" }
        XCTAssertEqual(sections, [
            "My School", "Students", "Staff", "Visitors", "Birthdays", "Rooms", "On duty", "Mailer"
        ])

        let menuRoutes = Set(try routes(in: menu))
        for expected in [
            "people/students/staff",
            "people/students/all",
            "people/students/byname",
            "people/staff/current",
            "people/birthdays",
            "people/onduty",
            "mailer/inbox",
            "mailer/archive",
            "mailer/send"
        ] {
            XCTAssertTrue(menuRoutes.contains(expected), "missing route \(expected)")
        }

        // The freeform mailer link carries its type in a second query item.
        let freeform = try menu.select("a[href]").array().first { element in
            let href = try element.attr("href")
            return route(of: href) == "mailer/send" && queryValue("type", in: href) == "freeform"
        }
        XCTAssertNotNil(freeform)
    }

    func testDocumentsPageListsFoldersAndHasNoSideMenu() throws {
        let doc = try document(Self.documentsFixture)
        XCTAssertTrue(try doc.select(".sdmenu").array().isEmpty)

        let folders = try doc.select("ul.folder-list li a.folder").array()
        XCTAssertEqual(
            try folders.map { try $0.text() },
            ["Internal Information", "Outdoor Department"]
        )
        let folderIDs = try folders.compactMap { try queryValue("folder_id", in: $0.attr("href")) }
        XCTAssertEqual(folderIDs, ["27", "34"])
        for folder in folders {
            XCTAssertEqual(route(of: try folder.attr("href")), "documents/index")
        }
    }

    // MARK: - Shared chrome (every logged-in page, README 5.6)

    func testEveryFixtureCarriesTheSameLoggedInChrome() throws {
        for name in Self.allFixtures {
            let doc = try document(name)

            XCTAssertNotNil(try doc.select("#header").first(), "\(name): #header")
            XCTAssertNotNil(try doc.select("#footer").first(), "\(name): #footer")
            XCTAssertNotNil(try doc.select(".status-dropdown").first(), "\(name): campus dropdown")
            XCTAssertEqual(try doc.select("#version").first()?.text(), "W4 v. 25.9.1", "\(name): version")

            let panel = try XCTUnwrap(doc.select("#user-panel .right").first(), "\(name): #user-panel")
            XCTAssertTrue(try panel.text().contains("Welcome, Alex Andersen"), "\(name): welcome line")

            let menuLinks = try doc.select("#main_menu a[href]").array()
            XCTAssertEqual(try menuLinks.map { try $0.text() }, [
                "Home", "Academics", "Extra Academics", "School", "Admissions", "Documents"
            ], "\(name): main menu labels")
            XCTAssertEqual(try menuLinks.compactMap { try route(of: $0.attr("href")) }, [
                "site/index", "academics", "extraacademics", "people",
                "admissions/browse/admissions", "documents"
            ], "\(name): main menu routes")

            XCTAssertEqual(try doc.select("#main_menu a.active").array().count, 1, "\(name): active tab")
        }
    }

    func testActiveMainMenuTabMatchesThePage() throws {
        let expected: [(fixture: String, route: String)] = [
            (Self.homeFixture, "site/index"),
            (Self.academicsMenuFixture, "academics"),
            (Self.extraAcademicsMenuFixture, "extraacademics"),
            (Self.schoolMenuFixture, "people"),
            (Self.documentsFixture, "documents")
        ]
        for (name, expectedRoute) in expected {
            let doc = try document(name)
            let active = try XCTUnwrap(doc.select("#main_menu a.active").first(), name)
            XCTAssertEqual(route(of: try active.attr("href")), expectedRoute, name)
        }
    }

    // MARK: - No Lectio leftovers in the captures

    func testCapturesContainNoASPNETPostbackMachinery() throws {
        for name in Self.allFixtures {
            let source = try html(name)
            XCTAssertFalse(source.contains("__VIEWSTATE"), "\(name): W4 is Yii 1, not ASP.NET")
            XCTAssertFalse(source.contains("__EVENTVALIDATION"), "\(name)")
            XCTAssertFalse(source.contains("__doPostBack"), "\(name)")
            XCTAssertFalse(source.contains("lectio.dk"), "\(name)")
        }
    }
}
