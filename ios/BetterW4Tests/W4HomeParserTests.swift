//
//  W4HomeParserTests.swift
//  BetterW4Tests
//
//  Tests for W4HomeParser + HomeModels (Wave 4 item 4.6).
//
//  EVIDENCE MAP — read this before adding an assertion.
//
//    [V] `home.html` is a REAL capture of `https://w4.uwcrcn.no/index.php?r=site/index`
//        (sanitized: names and UWC ids replaced, image binaries dropped). Almost
//        everything asserted here comes straight off it: the `#hello` greeting
//        and the signed-in student's own public-profile link, three birthdays
//        today and one tomorrow, the RSS link, the CAPTURED EMPTY announcements
//        state, the ten `#links` entries and `#version`.
//
//    [I] The capture's announcements block is EMPTY — `<p>No announcements...</p>`.
//        No populated announcement has ever been seen, so the populated-item
//        tests below run on SYNTHESIZED markup and verify THE PARSER, not W4.
//        They are marked [I] individually.
//
//  Two things the capture does NOT contain, and which therefore must never be
//  asserted here:
//    * birthday NAMES. `#birthdays-today li` is `a > img.photo` and nothing
//      else — a bare thumbnail wall. `HomeBirthday` has no `name` field on
//      purpose; names are resolved later through the directory cache.
//    * absolute birthday photo URLs. The saved page rewrote them to
//      `./UWCRCN W4_files/…`, which is an artefact of "Save page as", not of W4.
//
//  Deliberately not tested here (other Wave 4 items own them): `#timetable`
//  (4.1), `#absences` (4.4), `.status-dropdown` and `div.notifications` (4.5).
//

import XCTest
@testable import BetterW4

final class W4HomeParserTests: XCTestCase {

    // MARK: - Fixtures

    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: type(of: self))
        if let url = bundle.url(forResource: name, withExtension: "html", subdirectory: "Fixtures/W4")
            ?? bundle.url(forResource: name, withExtension: "html") {
            return try String(contentsOf: url, encoding: .utf8)
        }
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/W4/\(name).html")
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw XCTSkip("Fixture \(name).html is not in the test bundle")
        }
        return try String(contentsOf: source, encoding: .utf8)
    }

    private func home() throws -> HomePage {
        W4HomeParser.parse(try fixture("home"))
    }

    private func route(of url: URL?) -> String? {
        guard let url else { return nil }
        return W4Routes.route(of: url)
    }

    // MARK: - [V] #hello — greeting and identity

    func testCapturedGreeting() throws {
        let page = try home()

        XCTAssertEqual(page.greetingText, "Hello Alex Andersen")
        XCTAssertEqual(page.greetingName, "Alex Andersen")
        XCTAssertFalse(page.isEmpty)
    }

    /// Bug B17. A document-wide `nc\d{2}[a-z]+` sweep over the Home page hits a
    /// BIRTHDAY CLASSMATE first, not the signed-in student. The id must come
    /// from the `#hello` profile link, which is scoped to this student.
    func testCapturedUWCIDComesFromHelloAndNotFromABirthdayThumbnail() throws {
        let page = try home()

        XCTAssertEqual(page.uwcId, "nc26abcd")
        XCTAssertEqual(page.publicProfileRoute, "people/students/student&uwc_id=nc26abcd")

        let url = try XCTUnwrap(page.publicProfileURL)
        XCTAssertEqual(url.host, "w4.uwcrcn.no")
        XCTAssertEqual(route(of: url), "people/students/student")

        // The first UWC id that appears in the raw document belongs to someone
        // else entirely. If these ever match, the fixture changed, not the bug.
        let firstIDInDocument = try XCTUnwrap(page.birthdaysToday.first?.uwcId)
        XCTAssertEqual(firstIDInDocument, "nc16efgh")
        XCTAssertNotEqual(page.uwcId, firstIDInDocument, "bug B17")
    }

    /// The route round-trips: `W4Routes.url(_:)` accepts the spelling the
    /// parser produces and rebuilds the same link.
    func testCapturedProfileRouteRoundTripsThroughW4Routes() throws {
        let page = try home()
        let rebuilt = W4Routes.url(try XCTUnwrap(page.publicProfileRoute))

        XCTAssertEqual(W4Routes.route(of: rebuilt), "people/students/student")
        XCTAssertTrue(rebuilt.absoluteString.contains("uwc_id=nc26abcd"))
    }

    // MARK: - [V] #birthdays

    func testCapturedBirthdaysToday() throws {
        let page = try home()

        XCTAssertEqual(page.birthdaysToday.count, 3)
        XCTAssertEqual(page.birthdaysToday.map(\.uwcId), ["nc16efgh", "nc19ijkl", "nc25mnop"])
        // Staff birthdays share the list; the route tells them apart.
        XCTAssertEqual(page.birthdaysToday.map(\.isStaff), [true, true, false])
        XCTAssertEqual(
            page.birthdaysToday.map(\.profileRoute),
            [
                "people/staff/staff&uwc_id=nc16efgh",
                "people/staff/staff&uwc_id=nc19ijkl",
                "people/students/student&uwc_id=nc25mnop"
            ]
        )
        // `id` is the UWC id, so a SwiftUI ForEach over this list is stable.
        XCTAssertEqual(page.birthdaysToday.map(\.id), page.birthdaysToday.map(\.uwcId))
    }

    func testCapturedBirthdaysTomorrow() throws {
        let page = try home()

        XCTAssertGreaterThanOrEqual(page.birthdaysTomorrow.count, 1)
        XCTAssertEqual(page.birthdaysTomorrow.first?.uwcId, "nc25qrst")
        XCTAssertEqual(page.birthdaysTomorrow.first?.isStaff, false)
        XCTAssertEqual(
            page.allBirthdays.count,
            page.birthdaysToday.count + page.birthdaysTomorrow.count
        )
    }

    /// The capture's photo `src` is a saved-page relative path. Keeping it
    /// verbatim and refusing to fabricate an absolute URL from it is the
    /// honest behaviour — a made-up `https://w4.uwcrcn.no/UWCRCN W4_files/…`
    /// would 404 on the real server.
    func testCapturedBirthdayPhotoSourceIsKeptVerbatimAndNotResolved() throws {
        let page = try home()
        let entry = try XCTUnwrap(page.birthdaysToday.first)

        let source = try XCTUnwrap(entry.photoSource)
        XCTAssertTrue(source.hasSuffix("_thumb.jpg"), source)
        XCTAssertTrue(source.contains("nc16efgh"), source)
        XCTAssertNil(entry.photoURL, "a saved-page relative path is not an absolute URL")
    }

    func testCapturedBirthdaysCalendarLink() throws {
        let page = try home()
        XCTAssertEqual(route(of: page.birthdaysCalendarURL), "people/birthdays")
    }

    // MARK: - [V] #announcements — the captured state is EMPTY

    /// The one capture we have says "No announcements...". That is W4 telling
    /// us there is nothing, which is a different fact from "we could not find
    /// the block", and the model keeps the two apart.
    func testCapturedAnnouncementsAreConfirmedEmpty() throws {
        let page = try home()

        XCTAssertTrue(page.announcements.isEmpty)
        XCTAssertEqual(page.announcementsEmptyText, "No announcements...")
        XCTAssertTrue(page.announcementsAreConfirmedEmpty)
    }

    func testCapturedAnnouncementsRSSLink() throws {
        let page = try home()
        XCTAssertEqual(route(of: page.announcementsRSSURL), "site/rss")
    }

    // MARK: - [V] #links

    func testCapturedLinksBlockHasTenEntriesInDocumentOrder() throws {
        let page = try home()

        XCTAssertEqual(page.links.count, 10)
        XCTAssertEqual(page.links.map(\.title), [
            "UWCRCN Extra Academic Website",
            "RCN College Policies Drive",
            "Trip Form",
            "Høegh Kitchen Booking Form",
            "ManageBac",
            "Bakehus",
            "Haugland times",
            "Learning support",
            "6 Stiar (walks near campus)",
            "Lavvo Booking and Information"
        ])
    }

    /// `#links` is configuration, not code (README §6): four of the ten entries
    /// stay inside W4 and six leave it, and the parser has to say which is
    /// which without hardcoding either list.
    func testCapturedLinksSeparateInternalRoutesFromExternalDestinations() throws {
        let page = try home()

        let trips = try XCTUnwrap(page.links.first { $0.title == "Trip Form" })
        XCTAssertEqual(trips.route, "academics/trips")
        XCTAssertTrue(trips.isInternalRoute)
        XCTAssertEqual(trips.url.host, "w4.uwcrcn.no")

        // ManageBac is a third SIS: a link, never a scrape target (README §7).
        let manageBac = try XCTUnwrap(page.links.first { $0.title == "ManageBac" })
        XCTAssertFalse(manageBac.isInternalRoute)
        XCTAssertNil(manageBac.route)
        XCTAssertEqual(manageBac.url.host, "uwcrcn.managebac.com")

        // A CMS deep link keeps its sibling `page_id`, which is the only thing
        // that makes it addressable.
        let bakehus = try XCTUnwrap(page.links.first { $0.title == "Bakehus" })
        XCTAssertEqual(bakehus.route, "documents/index&page_id=870")
        XCTAssertTrue(bakehus.isInternalRoute)

        // The Extra Academics CMS is a second entry point into the same renderer.
        let haugland = try XCTUnwrap(page.links.first { $0.title == "Haugland times" })
        XCTAssertEqual(haugland.route, "extraacademics/documents/index&page_id=79")

        XCTAssertEqual(page.links.filter(\.isInternalRoute).count, 5)
        XCTAssertEqual(page.links.filter { !$0.isInternalRoute }.count, 5)
    }

    /// The page is UTF-8 and the fixture is read as UTF-8; a mojibake
    /// regression would show up here first.
    func testCapturedLinkTitleKeepsItsNonASCIICharacters() throws {
        let page = try home()
        let booking = try XCTUnwrap(page.links.first { $0.title.contains("Kitchen") })
        XCTAssertEqual(booking.title, "Høegh Kitchen Booking Form")
    }

    func testCapturedLinkIdentifiersAreUnique() throws {
        let page = try home()
        XCTAssertEqual(Set(page.links.map(\.id)).count, page.links.count)
    }

    // MARK: - [V] #version

    func testCapturedServerVersion() throws {
        let page = try home()

        XCTAssertEqual(page.serverVersion, "25.9.1")
        XCTAssertEqual(route(of: page.releaseNotesURL), "site/relnotes")
    }

    /// `#version` is chrome, so it parses off any authenticated page.
    func testVersionIsReadFromANonHomePageToo() throws {
        let page = W4HomeParser.parse(try fixture("documents"))
        XCTAssertEqual(page.serverVersion, "25.9.1")
    }

    // MARK: - [V] Non-Home pages degrade gracefully

    /// `documents.html` is a real capture with no `#hello`, no `#birthdays`,
    /// no `#announcements` and no `#links`. Those must come back empty rather
    /// than half-invented from the surrounding chrome.
    func testCapturedDocumentsPageYieldsNoHomeContent() throws {
        let page = W4HomeParser.parse(try fixture("documents"))

        XCTAssertNil(page.greetingText)
        XCTAssertNil(page.greetingName)
        XCTAssertNil(page.uwcId, "the Documents chrome carries no uwc id anywhere")
        XCTAssertNil(page.publicProfileRoute)
        XCTAssertTrue(page.birthdaysToday.isEmpty)
        XCTAssertTrue(page.birthdaysTomorrow.isEmpty)
        XCTAssertTrue(page.announcements.isEmpty)
        XCTAssertNil(page.announcementsEmptyText, "W4 did not say 'no announcements' on this page")
        XCTAssertFalse(page.announcementsAreConfirmedEmpty)
        XCTAssertTrue(page.links.isEmpty)
    }

    // MARK: - Degradation

    func testEmptyAndGarbageInputDegradeToAnEmptyPage() {
        XCTAssertEqual(W4HomeParser.parse(""), .empty)
        XCTAssertEqual(W4HomeParser.parse("   \n  "), .empty)

        let garbage = W4HomeParser.parse("<html><body><p>nope</p></body></html>")
        XCTAssertTrue(garbage.isEmpty)
        XCTAssertNil(garbage.greetingName)
        XCTAssertTrue(garbage.links.isEmpty)
    }

    /// A `#hello` that lost its profile link still yields the greeting.
    /// Partial is better than nothing, and much better than a crash.
    func testGreetingSurvivesAMissingProfileLink() {
        let page = W4HomeParser.parse("""
            <html><body><div id="hello"><p>Hello Alex Andersen</p></div></body></html>
            """)

        XCTAssertEqual(page.greetingName, "Alex Andersen")
        XCTAssertNil(page.uwcId)
        XCTAssertNil(page.publicProfileURL)
    }

    // MARK: - [I] SYNTHESIZED — verifies the parser, not W4

    /// **[I]** No populated announcement has EVER been captured. The markup
    /// below is built from the rules `homepage.css` ships
    /// (`#announcements-content ul li dl dt`, `… dl dd`, `… dl dt span`), so
    /// this test proves the parser handles that shape — it is NOT evidence
    /// that W4 emits it.
    func testSynthesizedAnnouncementSplitsTitleDateAndBody() throws {
        let page = W4HomeParser.parse(Self.announcementsHTML(items: [
            (title: "Fire drill on Friday", date: "12-Aug-2026",
             body: "<p>Assemble at the <strong>flagpole</strong>.</p>"),
            (title: "Library closed", date: "13-Aug-2026", body: "<p>All day.</p>")
        ]))

        XCTAssertEqual(page.announcements.count, 2)
        XCTAssertNil(page.announcementsEmptyText, "there is nothing empty about this page")
        XCTAssertFalse(page.announcementsAreConfirmedEmpty)

        let first = try XCTUnwrap(page.announcements.first)
        XCTAssertEqual(first.title, "Fire drill on Friday", "the date span must not leak into the title")
        XCTAssertEqual(first.date, "12-Aug-2026")
        // The body is kept as HTML for HTMLContentRenderer, not flattened to text.
        let body = try XCTUnwrap(first.bodyHTML)
        XCTAssertTrue(body.contains("<strong>"), body)
        XCTAssertTrue(body.contains("flagpole"), body)
    }

    /// **[I]** Bug B19: an announcement id must be derived from its content, so
    /// that re-fetching the same page produces the same id and inserting a new
    /// announcement at the top does not renumber every row beneath it.
    func testSynthesizedAnnouncementIDsAreContentDerivedAndStable() throws {
        let one = (title: "Fire drill on Friday", date: "12-Aug-2026", body: "<p>Assemble.</p>")
        let two = (title: "Library closed", date: "13-Aug-2026", body: "<p>All day.</p>")

        let firstParse = W4HomeParser.parse(Self.announcementsHTML(items: [one, two]))
        let secondParse = W4HomeParser.parse(Self.announcementsHTML(items: [one, two]))
        XCTAssertEqual(firstParse.announcements.map(\.id), secondParse.announcements.map(\.id))
        XCTAssertTrue(firstParse.announcements.allSatisfy { $0.id.hasPrefix("announcement-") })

        // Prepending a new item must not change the surviving item's id.
        let zero = (title: "Snow day", date: "14-Aug-2026", body: "<p>No classes.</p>")
        let prepended = W4HomeParser.parse(Self.announcementsHTML(items: [zero, one, two]))
        let original = try XCTUnwrap(firstParse.announcements.first?.id)
        XCTAssertTrue(prepended.announcements.map(\.id).contains(original), "bug B19: not a row index")

        // Different content, different id.
        XCTAssertEqual(Set(prepended.announcements.map(\.id)).count, 3)
    }

    /// **[I]** Two anchors pointing at the same destination are one link.
    func testSynthesizedLinksAreDeduplicatedByDestination() {
        let page = W4HomeParser.parse("""
            <html><body><div id="links"><h3>Links</h3><ul>
              <li><a href="https://w4.uwcrcn.no/index.php?r=academics/trips">Trip Form</a></li>
              <li><a href="https://w4.uwcrcn.no/index.php?r=academics/trips">Trip Form (again)</a></li>
              <li><a href="">Broken</a></li>
              <li><a href="./UWCRCN W4_files/local.html">Saved-page relative</a></li>
            </ul></div></body></html>
            """)

        XCTAssertEqual(page.links.count, 1)
        XCTAssertEqual(page.links.first?.title, "Trip Form")
    }

    // MARK: - URL and route helpers

    func testAbsoluteURLResolution() {
        XCTAssertEqual(
            W4HomeParser.absoluteURL(fromHref: "/index.php?r=site/index")?.absoluteString,
            "https://w4.uwcrcn.no/index.php?r=site/index"
        )
        XCTAssertEqual(
            W4HomeParser.absoluteURL(fromHref: "https://uwcrcn.managebac.com/login")?.host,
            "uwcrcn.managebac.com"
        )
        XCTAssertEqual(W4HomeParser.absoluteURL(fromHref: "mailto:alex@uwcrcn.no")?.scheme, "mailto")

        // A saved-page relative path is NOT resolvable against the live host,
        // so the parser refuses to invent one.
        XCTAssertNil(W4HomeParser.absoluteURL(fromHref: "./UWCRCN W4_files/nc16efgh_thumb.jpg"))
        XCTAssertNil(W4HomeParser.absoluteURL(fromHref: ""))
        XCTAssertNil(W4HomeParser.absoluteURL(fromHref: "   "))
    }

    func testW4RouteKeepsSiblingQueryKeysAndRejectsForeignHosts() {
        XCTAssertEqual(
            W4HomeParser.w4Route(from: URL(string: "https://w4.uwcrcn.no/index.php?r=documents/index&page_id=870")),
            "documents/index&page_id=870"
        )
        XCTAssertEqual(
            W4HomeParser.w4Route(from: URL(string: "https://w4.uwcrcn.no/index.php?r=academics/trips")),
            "academics/trips"
        )
        XCTAssertNil(W4HomeParser.w4Route(from: URL(string: "https://sites.google.com/uwcrcn.no/6stiar")))
        XCTAssertNil(W4HomeParser.w4Route(from: URL(string: "https://w4.uwcrcn.no/")), "no r= at all")
        XCTAssertNil(W4HomeParser.w4Route(from: nil))
    }

    // MARK: - Synthesized announcements builder

    /// **[I]** Mirrors the CSS selectors `homepage.css` styles, wrapped in the
    /// `#announcements > #announcements-content` shell that IS captured.
    private static func announcementsHTML(
        items: [(title: String, date: String, body: String)]
    ) -> String {
        var rows = ""
        for item in items {
            rows += """
                <li><dl>
                  <dt>\(item.title) <span>\(item.date)</span></dt>
                  <dd>\(item.body)</dd>
                </dl></li>
                """
        }
        return """
            <html><body>
            <div id="announcements"><div id="announcements-content">
              <h3>College Announcements</h3>
              <div class="rss">
                <a href="https://w4.uwcrcn.no/index.php?r=site/rss"><img src="rss.png" alt="RSS icon"></a>
              </div>
              <ul>\(rows)</ul>
            </div></div>
            </body></html>
            """
    }
}
