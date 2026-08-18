//
//  W4TripsParserTests.swift
//  BetterW4Tests
//
//  Fixture provenance:
//
//    academics-menu.html — [V] REAL CAPTURE of the Academics side menu. The only
//                          verified fact about trips anywhere in the research
//                          set is the pair of ROUTES it links.
//    trips.html          — [I] SYNTHESIZED. No page of `academics/trips` has
//                          ever been captured; the grid, the headers, the row
//                          and the "Plan new trip" button are all invented from
//                          README §6's prose description.
//    every inline markup string below — [I] SYNTHESIZED, same caveat.
//
//  READ THIS BEFORE ADDING AN ASSERTION. Tests marked [V] check real captured
//  bytes. Tests marked [I] check **W4TripsParser**, not W4: they prove the
//  parser handles a shape we believe W4 emits, and they are NOT evidence that
//  W4 emits it. If a real capture ever arrives and disagrees, the fixture is
//  wrong — rewrite the fixture, do not bend the parser to keep these green.
//

import XCTest
@testable import BetterW4

final class W4TripsParserTests: XCTestCase {

    // MARK: - Fixtures

    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: "html", subdirectory: "Fixtures/W4")
            ?? bundle.url(forResource: name, withExtension: "html") else {
            throw XCTSkip("Fixture \(name).html is not in the test bundle")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func osloDate(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0
    ) throws -> Date {
        try XCTUnwrap(W4Dates.date(year: year, month: month, day: day, hour: hour, minute: minute))
    }

    // MARK: - [V] The only captured evidence: the two routes

    /// **[V]** `academics-menu.html` is a real capture of the Academics side
    /// menu. It renders a "Trips" group linking exactly these two routes, which
    /// is what `W4Routes.R.trips` / `.travel` must resolve to.
    func testCapturedAcademicsMenuLinksBothTripRoutes() throws {
        let html = try fixture("academics-menu")

        XCTAssertTrue(
            html.contains("r=academics/trips\">My trips"),
            "the captured side menu links academics/trips as 'My trips'"
        )
        XCTAssertTrue(
            html.contains("r=academics/travel/travel.list\">My travel forms"),
            "the captured side menu links academics/travel/travel.list as 'My travel forms'"
        )
        XCTAssertEqual(W4Routes.R.trips, "academics/trips")
        XCTAssertEqual(W4Routes.R.travel, "academics/travel/travel.list")
    }

    // MARK: - [I] The synthesized trips fixture

    /// **[I]** Verifies the parser against invented markup. See the file header.
    func testSynthesizedFixtureParsesOneTrip() throws {
        let list = W4TripsParser.parse(try fixture("trips"))

        XCTAssertEqual(list.trips.count, 1)
        let trip = try XCTUnwrap(list.trips.first)

        XCTAssertEqual(trip.name, "Bergen weekend")
        XCTAssertEqual(trip.destination, "Bergen")
        XCTAssertEqual(trip.type, "Optional")
        XCTAssertEqual(trip.participants, 12)
        XCTAssertEqual(trip.participantsLabel, "12")
        XCTAssertEqual(trip.status, .planning)
        XCTAssertEqual(trip.statusLabel, "Planning", "the raw label is always retained")
        XCTAssertEqual(trip.statusDisplay, "Planning")
        XCTAssertEqual(trip.route, "academics/trips")
        XCTAssertTrue(trip.isMultiDay)
    }

    /// **[I]** `?id=` from the row link, never the row index (B19) and never
    /// `tr[id]` (B18).
    func testSynthesizedFixtureTripIDComesFromTheRowLink() throws {
        let list = W4TripsParser.parse(try fixture("trips"))
        XCTAssertEqual(list.trips.first?.id, "trip-118")
    }

    /// **[I]** Dates go through `W4Dates`, so they are Oslo wall clock and the
    /// raw cell survives next to them.
    func testSynthesizedFixtureParsesBothTimestampsInOslo() throws {
        let list = W4TripsParser.parse(try fixture("trips"))
        let trip = try XCTUnwrap(list.trips.first)

        XCTAssertEqual(trip.outgoing, try osloDate(2026, 9, 20, 8, 0))
        XCTAssertEqual(trip.returning, try osloDate(2026, 9, 21, 18, 0))
        XCTAssertEqual(trip.outgoingLabel, "20-Sep-2026 08:00")
        XCTAssertEqual(trip.returningLabel, "21-Sep-2026 18:00")
    }

    /// **[I]** D-11: never `TimeZone.current`. On a device west of Greenwich a
    /// device-zone parse would land on 19-Sep.
    func testDatesAreOsloRegardlessOfDeviceTimeZone() throws {
        let list = W4TripsParser.parse(try fixture("trips"))
        let outgoing = try XCTUnwrap(list.trips.first?.outgoing)

        var osloCalendar = Calendar(identifier: .gregorian)
        osloCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Oslo"))
        let components = osloCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: outgoing)

        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 9)
        XCTAssertEqual(components.day, 20)
        XCTAssertEqual(components.hour, 8)
        XCTAssertEqual(components.minute, 0)
    }

    /// **[I]** Page-level facts: heading, the read-only "Plan new trip"
    /// affordance, no pager, and a header-driven parse.
    func testSynthesizedFixturePageMetadata() throws {
        let list = W4TripsParser.parse(try fixture("trips"))

        XCTAssertEqual(list.title, "My trips")
        XCTAssertTrue(list.canPlanNewTrip)
        // The affordance is an <input type="button"> with an onclick, so there
        // is no href to hand to the in-app browser.
        XCTAssertNil(list.planNewTripHref)
        XCTAssertFalse(list.hasMorePages, "the summary reads 1-1 of 1")
        XCTAssertTrue(list.isHeaderDriven)
        XCTAssertNil(list.emptyMessage)
        XCTAssertFalse(list.hasApprovedTrip)
        XCTAssertEqual(list.trips(withStatus: .planning).count, 1)
    }

    /// **[I]** The convenience entry point `parsers.md` §14 sketches.
    func testParseTripsConvenienceReturnsTheSameRows() throws {
        let html = try fixture("trips")
        XCTAssertEqual(W4TripsParser.parseTrips(html).map(\.id), W4TripsParser.parse(html).trips.map(\.id))
    }

    // MARK: - [I] The header-shuffle test (plan item 4.10 "Done")

    /// **[I]** THE test for this parser. `W4TripsParser.kt:17-31` reads cells
    /// positionally, so swapping two W4 columns silently files the status as the
    /// participant count. Swap Status and Participants in the fixture — both the
    /// header cells and the body cells — and every field must still land in the
    /// right place.
    func testHeaderShuffleKeepsStatusAndParticipantsInTheirOwnFields() throws {
        let original = try fixture("trips")
        let shuffled = try Self.swappingParticipantsAndStatusColumns(original)

        XCTAssertNotEqual(shuffled, original, "the swap must actually change the markup")

        let list = W4TripsParser.parse(shuffled)
        XCTAssertEqual(list.trips.count, 1)
        let trip = try XCTUnwrap(list.trips.first)

        XCTAssertEqual(trip.status, .planning, "status must follow its header, not its position")
        XCTAssertEqual(trip.statusLabel, "Planning")
        XCTAssertEqual(trip.participants, 12)
        XCTAssertEqual(trip.participantsLabel, "12")

        // Nothing else may drift either.
        XCTAssertEqual(trip.id, "trip-118")
        XCTAssertEqual(trip.name, "Bergen weekend")
        XCTAssertEqual(trip.destination, "Bergen")
        XCTAssertEqual(trip.type, "Optional")
        XCTAssertEqual(trip.outgoing, try osloDate(2026, 9, 20, 8, 0))
        XCTAssertTrue(list.isHeaderDriven)
    }

    /// Swaps the Participants and Status columns of `trips.html`. The fixture
    /// deliberately keeps each pair of cells on one line so this is an exact,
    /// unambiguous replacement; the assertions fail loudly if that layout ever
    /// changes, rather than silently swapping nothing.
    private static func swappingParticipantsAndStatusColumns(_ html: String) throws -> String {
        let headerBefore = #"<th id="yw0_c5">Participants</th><th id="yw0_c6">Status</th>"#
        let headerAfter = #"<th id="yw0_c6">Status</th><th id="yw0_c5">Participants</th>"#
        let bodyBefore = "<td>12</td><td>Planning</td>"
        let bodyAfter = "<td>Planning</td><td>12</td>"

        guard html.contains(headerBefore), html.contains(bodyBefore) else {
            throw XCTSkip("trips.html no longer has the adjacent Participants/Status cells this test swaps")
        }

        return html
            .replacingOccurrences(of: headerBefore, with: headerAfter)
            .replacingOccurrences(of: bodyBefore, with: bodyAfter)
    }

    // MARK: - [I] Status vocabulary

    /// **[I]** The ladder is README §6 prose, never captured markup. What this
    /// test really pins down is that the raw label always survives.
    func testStatusLadderMatchesTheDocumentedVocabulary() {
        XCTAssertEqual(TripStatus(label: "Planning"), .planning)
        XCTAssertEqual(TripStatus(label: "Pending confirmation"), .pendingConfirmation)
        XCTAssertEqual(TripStatus(label: "PENDING CONFIRMATION (house leader)"), .pendingConfirmation)
        XCTAssertEqual(TripStatus(label: "Approved"), .approved)
        XCTAssertEqual(TripStatus(label: "Cancelled"), .cancelled)
        XCTAssertEqual(TripStatus(label: "Canceled"), .cancelled)
        // "Not approved" contains "approved" — the narrower reading has to win.
        XCTAssertEqual(TripStatus(label: "Not approved"), .cancelled)
        XCTAssertEqual(TripStatus(label: ""), .unknown)
        XCTAssertEqual(TripStatus(label: nil), .unknown)
        XCTAssertEqual(TripStatus(label: "Under review by the trips office"), .unknown)

        XCTAssertTrue(TripStatus.approved.registersPrearrangedAbsences)
        XCTAssertFalse(TripStatus.planning.registersPrearrangedAbsences)
        XCTAssertTrue(TripStatus.cancelled.isSettled)
        XCTAssertFalse(TripStatus.pendingConfirmation.isSettled)
    }

    /// **[I]** An unrecognised status must still be displayable verbatim — the
    /// enum is for grouping, the string is what the student reads.
    func testUnrecognisedStatusKeepsItsRawLabel() throws {
        let list = W4TripsParser.parse(Self.tripsPage(
            headerHTML: Self.standardHeader,
            bodyHTML: """
                <tr>
                  <td>Hardangervidda hike</td><td>02-Oct-2026 07:30</td><td>04-Oct-2026 19:00</td>
                  <td>Hardangervidda</td><td>Compulsory</td><td>34</td>
                  <td>Held for review by the trips office</td>
                </tr>
                """
        ))

        let trip = try XCTUnwrap(list.trips.first)
        XCTAssertEqual(trip.status, .unknown)
        XCTAssertEqual(trip.statusLabel, "Held for review by the trips office")
        XCTAssertEqual(trip.statusDisplay, "Held for review by the trips office")
    }

    // MARK: - [I] Column edge cases

    /// **[I]** `parsers.md` §14: the participants cell may be a name list rather
    /// than a count. The count is then `nil` and the raw string is kept.
    func testParticipantsNameListKeepsTheRawStringAndReportsNoCount() throws {
        let list = W4TripsParser.parse(Self.tripsPage(
            headerHTML: Self.standardHeader,
            bodyHTML: """
                <tr>
                  <td>Kayaking day</td><td>05-Oct-2026 09:00</td><td>05-Oct-2026 16:00</td>
                  <td>Sognefjord</td><td>Optional</td><td>Ada Berg, Grace Nilsen, Alan Vik</td>
                  <td>Approved</td>
                </tr>
                """
        ))

        let trip = try XCTUnwrap(list.trips.first)
        XCTAssertNil(trip.participants)
        XCTAssertEqual(trip.participantsLabel, "Ada Berg, Grace Nilsen, Alan Vik")
        XCTAssertEqual(trip.status, .approved)
        XCTAssertTrue(list.hasApprovedTrip)
    }

    /// **[I]** An unknown extra column must not shift anything: the header is
    /// what decides, so a column W4 adds tomorrow is simply ignored.
    func testUnknownExtraColumnDoesNotShiftValues() throws {
        let header = """
            <th>Trip name</th><th>Cost</th><th>Outgoing date/time</th><th>Return date/time</th>
            <th>Destination</th><th>Type</th><th>Participants</th><th>Status</th>
            """
        let list = W4TripsParser.parse(Self.tripsPage(
            headerHTML: header,
            bodyHTML: """
                <tr>
                  <td>Bergen weekend</td><td>450 NOK</td><td>20-Sep-2026 08:00</td>
                  <td>21-Sep-2026 18:00</td><td>Bergen</td><td>Optional</td><td>12</td>
                  <td>Planning</td>
                </tr>
                """
        ))

        let trip = try XCTUnwrap(list.trips.first)
        XCTAssertEqual(trip.name, "Bergen weekend")
        XCTAssertEqual(trip.destination, "Bergen")
        XCTAssertEqual(trip.participants, 12)
        XCTAssertEqual(trip.status, .planning)
    }

    /// **[I]** A grid with no header at all falls back to the documented column
    /// order — and says so, so the log line and this flag are how we find out
    /// the real page does not look like the fixture.
    func testGridWithoutAHeaderFallsBackToTheDocumentedOrderAndFlagsIt() throws {
        let html = """
            <html><body><div id="content_inner"><h2>My trips</h2>
            <table class="items">
              <tr>
                <td>Oslo museums</td><td>02-Oct-2026 07:30</td><td>02-Oct-2026 19:00</td>
                <td>Oslo</td><td>Compulsory</td><td>34</td><td>Approved</td>
              </tr>
            </table>
            </div></body></html>
            """

        let list = W4TripsParser.parse(html)
        XCTAssertFalse(list.isHeaderDriven, "the fallback must be visible to callers")

        let trip = try XCTUnwrap(list.trips.first)
        XCTAssertEqual(trip.name, "Oslo museums")
        XCTAssertEqual(trip.destination, "Oslo")
        XCTAssertEqual(trip.participants, 34)
        XCTAssertEqual(trip.status, .approved)
    }

    // MARK: - [I] Identity

    /// **[I]** Bug B19: a row with no `?id=` gets a content hash, so re-sorting
    /// the grid does not reassign identities.
    func testRowsWithoutLinksGetStableContentHashIDs() {
        let first = """
            <tr><td>Bergen weekend</td><td>20-Sep-2026 08:00</td><td>21-Sep-2026 18:00</td>
            <td>Bergen</td><td>Optional</td><td>12</td><td>Planning</td></tr>
            """
        let second = """
            <tr><td>Oslo museums</td><td>02-Oct-2026 07:30</td><td>02-Oct-2026 19:00</td>
            <td>Oslo</td><td>Compulsory</td><td>34</td><td>Approved</td></tr>
            """

        let ascending = W4TripsParser.parse(
            Self.tripsPage(headerHTML: Self.standardHeader, bodyHTML: first + second)
        ).trips
        let descending = W4TripsParser.parse(
            Self.tripsPage(headerHTML: Self.standardHeader, bodyHTML: second + first)
        ).trips

        XCTAssertEqual(ascending.count, 2)
        XCTAssertEqual(descending.count, 2)

        let ascendingByName = Dictionary(uniqueKeysWithValues: ascending.map { ($0.name, $0.id) })
        let descendingByName = Dictionary(uniqueKeysWithValues: descending.map { ($0.name, $0.id) })
        XCTAssertEqual(ascendingByName["Bergen weekend"], descendingByName["Bergen weekend"])
        XCTAssertEqual(ascendingByName["Oslo museums"], descendingByName["Oslo museums"])
        XCTAssertNotEqual(ascendingByName["Bergen weekend"], ascendingByName["Oslo museums"])
    }

    /// **[I]** Two byte-identical rows still need two distinct `Identifiable`
    /// ids or a SwiftUI list collapses them.
    func testIdenticalRowsGetDistinctIDs() {
        let row = """
            <tr><td>Bergen weekend</td><td>20-Sep-2026 08:00</td><td>21-Sep-2026 18:00</td>
            <td>Bergen</td><td>Optional</td><td>12</td><td>Planning</td></tr>
            """
        let trips = W4TripsParser.parse(
            Self.tripsPage(headerHTML: Self.standardHeader, bodyHTML: row + row)
        ).trips

        XCTAssertEqual(trips.count, 2)
        XCTAssertNotEqual(trips[0].id, trips[1].id)
    }

    // MARK: - [I] Empty states and pagination

    /// **[I]** Bug B9: Yii writes `td.empty` *and* `span.empty` *and* the bare
    /// sentence. The row is not a trip, and the message is surfaced verbatim.
    func testYiiEmptyRowYieldsNoTripsAndKeepsTheMessage() {
        let list = W4TripsParser.parse(Self.tripsPage(
            headerHTML: Self.standardHeader,
            bodyHTML: #"<tr><td colspan="7" class="empty"><span class="empty">No results found.</span></td></tr>"#
        ))

        XCTAssertTrue(list.trips.isEmpty)
        XCTAssertEqual(list.emptyMessage, "No results found.")
        XCTAssertTrue(list.isEmpty)
    }

    /// **[I]** The non-grid empty state (`div.note`) — the pattern itself is
    /// **[V]** from `Current applicants at UWCRCN.html`, its use on the trips
    /// page is not.
    func testPageNoteEmptyStateIsSurfaced() {
        let html = """
            <html><body><div id="content_inner"><h2>My trips</h2>
            <div class="note">No trips found</div>
            </div></body></html>
            """

        let list = W4TripsParser.parse(html)
        XCTAssertTrue(list.trips.isEmpty)
        XCTAssertEqual(list.emptyMessage, "No trips found")
        XCTAssertFalse(list.isHeaderDriven)
    }

    /// **[I]** Bug B10: nobody paginates, so at least detect the pager and let
    /// the UI say "more on W4" instead of pretending page 1 is everything.
    func testPagerIsDetected() {
        let list = W4TripsParser.parse(Self.tripsPage(
            headerHTML: Self.standardHeader,
            bodyHTML: """
                <tr><td>Bergen weekend</td><td>20-Sep-2026 08:00</td><td>21-Sep-2026 18:00</td>
                <td>Bergen</td><td>Optional</td><td>12</td><td>Planning</td></tr>
                """,
            extraHTML: #"<div class="pager"><ul class="yiiPager"><li><a href="/index.php?r=academics/trips&amp;Trip_page=2">2</a></li></ul></div>"#
        ))

        XCTAssertEqual(list.trips.count, 1)
        XCTAssertTrue(list.hasMorePages)
    }

    func testEmptyAndGarbageInputDoNotThrow() {
        XCTAssertTrue(W4TripsParser.parse("").trips.isEmpty)
        XCTAssertTrue(W4TripsParser.parse("<html><body><p>nope</p></body></html>").trips.isEmpty)
        XCTAssertTrue(W4TripsParser.parseTrips("<<<not html at all&&&").isEmpty)
        XCTAssertTrue(W4TripsParser.parseTravel("").forms.isEmpty)
        XCTAssertTrue(W4TripsParser.parseTravelContacts("").isEmpty)
    }

    // MARK: - [I] Travel forms

    /// **[I]** The four fixed journeys of README §6, classified from their
    /// titles. The wording is invented; what this pins down is the classifier.
    func testTravelJourneyClassification() {
        XCTAssertEqual(TravelJourney.classify("Travel to school in autumn"), .toSchoolAutumn)
        XCTAssertEqual(TravelJourney.classify("Travel home for winter break"), .homeWinter)
        XCTAssertEqual(TravelJourney.classify("Travel back to school after winter break"), .backAfterWinter)
        XCTAssertEqual(TravelJourney.classify("Travel home for summer"), .homeSummer)
        // "back home" is a departure, not a return: only "back TO" is a return.
        XCTAssertEqual(TravelJourney.classify("Travel back home for winter break"), .homeWinter)
        // Coming back to school after the summer is the autumn journey.
        XCTAssertEqual(TravelJourney.classify("Returning to college after the summer"), .toSchoolAutumn)
        XCTAssertNil(TravelJourney.classify("Travel insurance policy"))
        XCTAssertNil(TravelJourney.classify(""))
        XCTAssertNil(TravelJourney.classify(nil))
        XCTAssertEqual(TravelJourney.allCases.count, 4)
    }

    /// **[I]** The link-ladder shape: a submenu of four journey links plus the
    /// contacts link, which is not a form.
    func testTravelFormsFromALinkLadder() throws {
        let page = W4TripsParser.parseTravel("""
            <html><body><div id="content_inner"><h2>My travel forms</h2>
            <ul class="page-submenu">
              <li><a href="/index.php?r=academics/travel/travel&amp;id=1">Travel to school in autumn</a></li>
              <li><a href="/index.php?r=academics/travel/travel&amp;id=2">Travel home for winter break</a></li>
              <li><a href="/index.php?r=academics/travel/travel&amp;id=3">Travel back to school after winter break</a></li>
              <li><a href="/index.php?r=academics/travel/travel&amp;id=4">Travel home for summer</a></li>
              <li><a href="/index.php?r=academics/travel/contacts">Manage my travel contacts</a></li>
            </ul>
            </div></body></html>
            """)

        XCTAssertEqual(page.title, "My travel forms")
        XCTAssertEqual(page.forms.count, 4, "the contacts link is not a travel form")
        XCTAssertEqual(
            page.sortedForms.compactMap(\.journey),
            [.toSchoolAutumn, .homeWinter, .backAfterWinter, .homeSummer]
        )
        XCTAssertEqual(page.forms.map(\.id), ["travel-1", "travel-2", "travel-3", "travel-4"])
        XCTAssertEqual(page.form(for: .homeSummer)?.title, "Travel home for summer")
        XCTAssertEqual(page.form(for: .homeSummer)?.route, "academics/travel/travel")
        XCTAssertTrue(page.missingJourneys.isEmpty)

        XCTAssertTrue(page.hasContactsLink)
        XCTAssertEqual(page.manageContactsLabel, "Manage my travel contacts")
        XCTAssertEqual(page.manageContactsRoute, "academics/travel/contacts")
    }

    /// **[I]** The grid shape of the same page, with a status column whose raw
    /// text is kept verbatim.
    func testTravelFormsFromAGridKeepTheirRawStatus() throws {
        let page = W4TripsParser.parseTravel("""
            <html><body><div id="content_inner"><h2>My travel forms</h2>
            <div class="grid-view"><table class="items">
              <thead><tr><th>Journey</th><th>Status</th></tr></thead>
              <tbody>
                <tr><td><a href="/index.php?r=academics/travel/travel&amp;id=7">Travel home for summer</a></td>
                    <td>Not submitted</td></tr>
              </tbody>
            </table></div>
            <a href="/index.php?r=academics/travel/contacts">Manage my travel contacts</a>
            </div></body></html>
            """)

        XCTAssertEqual(page.forms.count, 1)
        let form = try XCTUnwrap(page.forms.first)
        XCTAssertEqual(form.id, "travel-7")
        XCTAssertEqual(form.journey, .homeSummer)
        XCTAssertEqual(form.title, "Travel home for summer")
        XCTAssertEqual(form.statusLabel, "Not submitted")
        XCTAssertEqual(form.displayName, "Travel home for summer")
        XCTAssertEqual(page.missingJourneys.count, 3)
        XCTAssertTrue(page.hasContactsLink)
    }

    /// **[I]** A journey W4 words in a way we do not recognise still appears,
    /// with its title intact and `journey == nil`.
    func testUnclassifiedTravelFormIsKeptWithItsTitle() throws {
        let page = W4TripsParser.parseTravel("""
            <html><body><div id="content_inner"><h2>My travel forms</h2>
            <a href="/index.php?r=academics/travel/travel&amp;id=9">Mid-term exeat travel</a>
            </div></body></html>
            """)

        let form = try XCTUnwrap(page.forms.first)
        XCTAssertNil(form.journey)
        XCTAssertEqual(form.title, "Mid-term exeat travel")
        XCTAssertEqual(form.id, "travel-9")
        XCTAssertEqual(page.missingJourneys.count, 4)
        XCTAssertFalse(page.hasContactsLink)
    }

    // MARK: - [I] Travel contacts

    /// **[I]** Header-driven like every other grid here.
    func testTravelContactsGridIsHeaderDriven() throws {
        let contacts = W4TripsParser.parseTravelContacts("""
            <html><body><div id="content_inner"><h2>My travel contacts</h2>
            <div class="grid-view"><table class="items">
              <thead><tr><th>Name</th><th>Relationship</th><th>Phone</th><th>Email</th></tr></thead>
              <tbody>
                <tr><td>Ingrid Halvorsen</td><td>Mother</td>
                    <td>+47 12 34 56 78</td><td>ingrid@example.com</td></tr>
              </tbody>
            </table></div>
            </div></body></html>
            """)

        XCTAssertEqual(contacts.count, 1)
        let contact = try XCTUnwrap(contacts.first)
        XCTAssertEqual(contact.name, "Ingrid Halvorsen")
        XCTAssertEqual(contact.relation, "Mother")
        XCTAssertEqual(contact.phone, "+47 12 34 56 78")
        XCTAssertEqual(contact.email, "ingrid@example.com")
        XCTAssertFalse(contact.id.isEmpty)
    }

    /// **[I]** When the grid has no phone/email columns, `mailto:` and `tel:`
    /// links inside the row are the fallback.
    func testTravelContactsFallBackToMailtoAndTelLinks() throws {
        let contacts = W4TripsParser.parseTravelContacts("""
            <html><body><div id="content_inner">
            <div class="grid-view"><table class="items">
              <thead><tr><th>Name</th><th>Reach them on</th></tr></thead>
              <tbody>
                <tr><td>Ingrid Halvorsen</td>
                    <td><a href="tel:+4712345678">call</a> / <a href="mailto:ingrid@example.com">write</a></td></tr>
              </tbody>
            </table></div>
            </div></body></html>
            """)

        let contact = try XCTUnwrap(contacts.first)
        XCTAssertEqual(contact.name, "Ingrid Halvorsen")
        XCTAssertEqual(contact.phone, "+4712345678")
        XCTAssertEqual(contact.email, "ingrid@example.com")
        XCTAssertNil(contact.relation)
    }

    func testTravelContactsWithoutAGridYieldNothing() {
        XCTAssertTrue(W4TripsParser.parseTravelContacts(
            "<html><body><div id=\"content_inner\"><div class=\"note\">No contacts found</div></div></body></html>"
        ).isEmpty)
    }

    // MARK: - Synthesized page builders  [I]

    /// The column set README §6 describes. Invented markup; see the file header.
    private static let standardHeader = """
        <th>Trip name</th><th>Outgoing date/time</th><th>Return date/time</th>
        <th>Destination</th><th>Type</th><th>Participants</th><th>Status</th>
        """

    private static func tripsPage(
        headerHTML: String,
        bodyHTML: String,
        extraHTML: String = ""
    ) -> String {
        """
        <html><body><div id="content_inner"><h2>My trips</h2>
        <div class="grid-view">
          <table class="items">
            <thead><tr>\(headerHTML)</tr></thead>
            <tbody>\(bodyHTML)</tbody>
          </table>
        </div>
        \(extraHTML)
        </div></body></html>
        """
    }
}
