//
//  W4PeopleParserTests.swift
//  BetterW4Tests
//
//  Fixture provenance — read this before adding an assertion:
//
//    people-empty.html — the `#content_inner` body is copied VERBATIM from
//        `references/pages/Current applicants at UWCRCN.html:80-82`, a real
//        signed-in capture. `<div class="note">No users found</div>` is therefore
//        **[V]**; the surrounding skeleton is not.
//    people-list.html — **[I] SYNTHESIZED.** No W4 people list page has ever been
//        captured. Every assertion made against it verifies `W4PeopleParser`, not
//        W4's markup.
//    student-profile.html — live `people/students/student` markup shape captured
//        21 Aug 2026 (`dl/dt/dd`, `Birth date` as `28-Jan`, `{name}'s classes`).
//        Identities in the fixture are invented.
//    home.html — **[V]** real capture of the Home page, used here only to prove
//        that the people parser refuses to read Home's birthday block as a
//        directory. The markup is real; the "should be empty" part is this port's
//        policy, not a fact about W4.
//
//  Every synthesized-markup test below is marked **[I]** and says so. Nothing in
//  this file may be read as evidence that W4 emits `ul.user-list`, a `CGridView`
//  people row, a Yii pager or a `table.detail-view` profile — only `css/main.css`
//  (`td.student-name`, `td.entry-name`, `tr.online td.status`) and the Home
//  birthdays block (`a[href*=uwc_id] > img.photo`, `alt="Photo of {uwc_id}"`,
//  `{uwc_id}_thumb.jpg`, staff and student hrefs side by side) are verified.
//

import XCTest
@testable import BetterW4

final class W4PeopleParserTests: XCTestCase {

    // MARK: - Fixtures

    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: "html", subdirectory: "Fixtures/W4")
            ?? bundle.url(forResource: name, withExtension: "html") else {
            throw XCTSkip("Fixture \(name).html is not in the test bundle")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func person(_ page: DirectoryPeoplePage, _ uwcId: String) throws -> DirectoryPerson {
        try XCTUnwrap(page.people.first { $0.uwcId == uwcId }, "no row for \(uwcId)")
    }

    // MARK: - The real empty state

    /// **[V]** — `div.note` "No users found" is the real body of a people-style
    /// page that has nothing to list. The wave's "Done" criterion for item 4.7.
    func testEmptyStateYieldsNoPeopleAndCarriesTheNotice() throws {
        let page = W4PeopleParser.parseList(try fixture("people-empty"))

        XCTAssertTrue(page.people.isEmpty, "an empty list must never produce a phantom row")
        XCTAssertTrue(page.isEmpty)
        XCTAssertEqual(page.notice, "No users found")
        XCTAssertEqual(page.heading, "Current applicants at UWCRCN")
        XCTAssertFalse(page.hasMorePages)
    }

    /// **[V] markup, policy assertion.** Home's `#birthdays` and `#hello` blocks
    /// live inside `#content_inner` and carry four `people/...&uwc_id=` links.
    /// They are page chrome, parsed by `W4HomeParser` (item 4.6) — a people list
    /// parser that swept them up would report classmates as a directory page.
    func testHomeChromeIsNotReadAsADirectory() throws {
        let page = W4PeopleParser.parseList(try fixture("home"))

        XCTAssertTrue(
            page.people.isEmpty,
            "Home's birthday photos and the #hello profile link are chrome, not a people list"
        )
    }

    // MARK: - [I] SYNTHESIZED FIXTURE — verifies the parser, not W4

    /// **[I]** `ul.user-list` has never been captured; this asserts the parser's
    /// behaviour on the Android port's shape.
    func testUserListYieldsThreePeopleInDocumentOrder() throws {
        let page = W4PeopleParser.parseList(try fixture("people-list"))

        XCTAssertEqual(page.people.count, 3)
        XCTAssertEqual(page.people.map(\.uwcId), ["nc00aaa", "nc00bbb", "nc00ccc"])
        XCTAssertEqual(page.heading, "All students")
        XCTAssertNil(page.notice)
        XCTAssertFalse(page.hasMorePages)
    }

    /// **[I]** The rule that matters: the kind is read from *each row's* href.
    /// The fixture lists students and staff on one page, exactly as Home's
    /// birthday block does (**[V]**), so a document-wide `people/staff` substring
    /// sniff — what the Kotlin port does — would label all three staff.
    func testKindComesFromEachRowHrefOnAMixedPage() throws {
        let page = W4PeopleParser.parseList(try fixture("people-list"))

        XCTAssertEqual(try person(page, "nc00aaa").kind, .student)
        XCTAssertEqual(try person(page, "nc00bbb").kind, .student)
        XCTAssertEqual(try person(page, "nc00ccc").kind, .staff)

        XCTAssertEqual(page.people.filter { $0.kind == .student }.count, 2)
        XCTAssertEqual(page.people.filter { $0.kind == .staff }.count, 1)

        XCTAssertEqual(
            try person(page, "nc00aaa").profileRoute,
            "people/students/student&uwc_id=nc00aaa"
        )
        XCTAssertEqual(
            try person(page, "nc00ccc").profileRoute,
            "people/staff/staff&uwc_id=nc00ccc"
        )
    }

    /// **[I]** for the list row; the `/images/user.png` placeholder itself and the
    /// `{uwc_id}_thumb.jpg` list-page convention are **[V]** (parsers.md §11).
    /// We upgrade thumbs to the matching full `{uwc_id}_photo.jpg` portrait.
    func testPlaceholderPhotoIsNilAndThumbnailResolves() throws {
        let page = W4PeopleParser.parseList(try fixture("people-list"))

        XCTAssertNil(
            try person(page, "nc00aaa").photoURL,
            "/images/user.png means 'no photo' — rendering it as a portrait is a bug"
        )
        XCTAssertEqual(
            try person(page, "nc00bbb").photoURL?.absoluteString,
            "https://w4.uwcrcn.no/files/user_photos/nc00bbb_photo.jpg"
        )
        XCTAssertEqual(
            try person(page, "nc00ccc").photoURL?.absoluteString,
            "https://w4.uwcrcn.no/files/user_photos/nc00ccc_photo.jpg"
        )
    }

    /// **[I]** Each `<li>` holds two anchors for the same person (photo + name).
    /// They must merge: one entity, the real name from the text anchor, the real
    /// portrait from the photo anchor.
    func testEachPersonAppearsOnceDespiteTwoAnchors() throws {
        let page = W4PeopleParser.parseList(try fixture("people-list"))

        XCTAssertEqual(Set(page.people.map(\.uwcId)).count, page.people.count)
        XCTAssertEqual(try person(page, "nc00bbb").name, "Bea Beltran")
        XCTAssertEqual(
            try person(page, "nc00bbb").photoURL?.absoluteString,
            "https://w4.uwcrcn.no/files/user_photos/nc00bbb_photo.jpg",
            "the name-only anchor must not clobber the photo anchor's portrait"
        )
        XCTAssertTrue(try person(page, "nc00bbb").hasResolvedName)
    }

    /// **[I]** `1<sup>st</sup> year` renders as `1st year` through `text()`, and
    /// the lines below the name are joined verbatim — nothing is promoted into
    /// `country` or `house` on a guess, because W4 never labels them here.
    func testSubtitleAndYearComeFromTheRowText() throws {
        let page = W4PeopleParser.parseList(try fixture("people-list"))

        let alex = try person(page, "nc00aaa")
        XCTAssertEqual(alex.name, "Alex Andersen")
        XCTAssertEqual(alex.subtitle, "Denmark · 1st year")
        XCTAssertEqual(alex.year, "1")
        XCTAssertNil(alex.country, "an unlabelled line is free text, not a country field")

        let bea = try person(page, "nc00bbb")
        XCTAssertEqual(bea.subtitle, "Italy · 2nd year")
        XCTAssertEqual(bea.year, "2")

        let chris = try person(page, "nc00ccc")
        XCTAssertEqual(chris.subtitle, "Advisor, Teacher")
        XCTAssertNil(chris.year)
    }

    /// The address is derived from the id (README §6), never scraped from a row.
    func testEmailIsDerivedFromTheUWCId() throws {
        let page = W4PeopleParser.parseList(try fixture("people-list"))
        XCTAssertEqual(try person(page, "nc00aaa").email, "nc00aaa@uwcrcn.no")
        XCTAssertEqual(try person(page, "nc00ccc").email, "nc00ccc@uwcrcn.no")
    }

    // MARK: - [I] SYNTHESIZED MARKUP — the CGridView variant

    /// **[I]** `td.student-name`, `td.entry-name`, `td.status`, `tr.online` and
    /// `tr.offline` are **[V]** only in the sense that `css/main.css` styles them.
    /// No grid row has ever been captured, so this test verifies the parser's
    /// handling of that shape and nothing more.
    func testGridVariantReadsNamedCellsAndRowState() {
        let page = W4PeopleParser.parseList(Self.grid())

        XCTAssertEqual(page.people.count, 2)

        guard let alex = page.people.first, let chris = page.people.last else {
            return XCTFail("expected two grid rows")
        }

        XCTAssertEqual(alex.uwcId, "nc00aaa")
        XCTAssertEqual(alex.name, "Alex Andersen")
        XCTAssertEqual(alex.kind, .student)
        XCTAssertEqual(alex.status, "Online")
        XCTAssertEqual(alex.isOnline, true)
        XCTAssertEqual(alex.country, "Denmark")
        XCTAssertEqual(alex.house, "Haugland")
        XCTAssertEqual(alex.subtitle, "Denmark · Haugland")

        // `td.entry-name` is the other name cell W4's stylesheet knows about.
        XCTAssertEqual(chris.uwcId, "nc00ccc")
        XCTAssertEqual(chris.name, "Chris Chen")
        XCTAssertEqual(chris.kind, .staff, "the staff row's own href decides, not the page")
        XCTAssertEqual(chris.status, "Offline")
        XCTAssertEqual(chris.isOnline, false)
    }

    /// **[I]** Columns are read through their `th` header, never by position, so
    /// swapping two columns must not swap two fields.
    func testGridColumnsAreReadFromHeadersNotPositions() {
        let page = W4PeopleParser.parseList(Self.grid(headers: ["Name", "House", "Country", "Status"],
                                                      firstRowCells: ["Haugland", "Denmark"]))

        guard let alex = page.people.first else { return XCTFail("expected a grid row") }
        XCTAssertEqual(alex.house, "Haugland")
        XCTAssertEqual(alex.country, "Denmark")
    }

    /// **[I]** A grid with no header row: nothing may be promoted into a typed
    /// field, but the row still reaches the UI as free text.
    func testGridWithoutHeadersStillRendersASubtitle() {
        let html = """
            <div id="content_inner">
              <table class="items">
                <tr class="odd online">
                  <td class="student-name"><a href="/index.php?r=people/students/student&amp;uwc_id=nc00aaa">Alex Andersen</a></td>
                  <td>Denmark</td>
                  <td class="status">Online</td>
                </tr>
              </table>
            </div>
            """
        let page = W4PeopleParser.parseList(html)

        guard let alex = page.people.first else { return XCTFail("expected a grid row") }
        XCTAssertEqual(alex.name, "Alex Andersen")
        XCTAssertNil(alex.country, "an unlabelled column must not become a country")
        XCTAssertEqual(alex.subtitle, "Denmark")
        XCTAssertEqual(alex.status, "Online")
    }

    /// **[I]** The Yii pager has never been captured. Reporting it is what lets
    /// the UI say "more on w4.uwcrcn.no" rather than silently truncating a
    /// 200-student directory.
    func testPagerReportsMorePages() {
        XCTAssertTrue(W4PeopleParser.parseList(Self.grid()).hasMorePages)
    }

    /// **[I]** Same claim, from the `CGridView` summary line alone.
    func testSummaryReportsMorePagesWithoutAPager() {
        let html = """
            <div id="content_inner">
              <div class="grid-view">
                <div class="summary">Displaying 1-20 of 187 results.</div>
                <table class="items">
                  <tr><td class="student-name"><a href="/index.php?r=people/students/student&amp;uwc_id=nc00aaa">Alex Andersen</a></td></tr>
                </table>
              </div>
            </div>
            """
        XCTAssertTrue(W4PeopleParser.parseList(html).hasMorePages)
    }

    func testSinglePageListReportsNoMorePages() throws {
        XCTAssertFalse(W4PeopleParser.parseList(try fixture("people-list")).hasMorePages)
    }

    // MARK: - [I] SYNTHESIZED MARKUP — identity hygiene

    /// `alt="Photo of nc00aaa"` is **[V]** on Home. It is an id with a prefix, not
    /// a display name; a row that carries only a photo must fall back to the id
    /// and say so through `hasResolvedName`.
    func testPhotoAltIsNeverADisplayName() {
        let html = """
            <div id="content_inner">
              <ul class="user-list">
                <li><a href="/index.php?r=people/students/student&amp;uwc_id=nc00ddd"><img class="photo" src="/files/user_photos/nc00ddd_thumb.jpg" alt="Photo of nc00ddd"></a></li>
                <li><a href="/index.php?r=people/students/student&amp;uwc_id=nc00eee">Photo of nc00eee</a></li>
              </ul>
            </div>
            """
        let page = W4PeopleParser.parseList(html)

        XCTAssertEqual(page.people.count, 2)
        guard let first = page.people.first, let second = page.people.last else {
            return XCTFail("expected two rows")
        }

        XCTAssertEqual(first.name, "nc00ddd")
        XCTAssertFalse(first.hasResolvedName, "the UI must be able to tell there is no real name")
        XCTAssertEqual(first.photoURL?.absoluteString,
                       "https://w4.uwcrcn.no/files/user_photos/nc00ddd_photo.jpg")

        XCTAssertEqual(second.name, "nc00eee")
        XCTAssertFalse(second.hasResolvedName)
    }

    /// **[V]** rule, **[I]** input: `/images/user.png` is W4's missing-photo
    /// placeholder and must never become a portrait URL.
    func testMissingPhotoPlaceholderResolvesToNil() {
        XCTAssertNil(W4PeopleParser.photoURL(fromSource: "/images/user.png", uwcId: "nc00aaa"))
        XCTAssertNil(W4PeopleParser.photoURL(fromSource: "", uwcId: "nc00aaa"))
        XCTAssertNil(W4PeopleParser.photoURL(fromSource: "data:image/png;base64,AAAA", uwcId: "nc00aaa"))
    }

    /// Every capture we hold was saved by a browser, which rewrote photo sources
    /// to `./UWCRCN W4_files/{uwc_id}_thumb.jpg`. Restore the live full-size
    /// convention rather than dropping the portrait.
    func testSavedPageThumbnailPathIsRestoredToTheLiveConvention() {
        XCTAssertEqual(
            W4PeopleParser.photoURL(fromSource: "./UWCRCN W4_files/nc00aaa_thumb.jpg", uwcId: "nc00aaa")?
                .absoluteString,
            "https://w4.uwcrcn.no/files/user_photos/nc00aaa_photo.jpg"
        )
        XCTAssertEqual(
            W4PeopleParser.photoURL(forUWCId: "NC00AAA")?.absoluteString,
            "https://w4.uwcrcn.no/files/user_photos/nc00aaa_photo.jpg"
        )
        XCTAssertEqual(
            W4PeopleParser.photoURL(
                fromSource: "/files/user_photos/nc00aaa_thumb.jpg",
                uwcId: "nc00aaa"
            )?.absoluteString,
            "https://w4.uwcrcn.no/files/user_photos/nc00aaa_photo.jpg"
        )
        XCTAssertEqual(
            W4PeopleParser.photoURL(
                fromSource: "/files/user_photos/nc00aaa.jpg",
                uwcId: "nc00aaa"
            )?.absoluteString,
            "https://w4.uwcrcn.no/files/user_photos/nc00aaa_photo.jpg"
        )
        XCTAssertEqual(
            W4PeopleParser.photoURL(
                fromSource: "/files/user_photos/nc00aaa_photo.jpg",
                uwcId: "nc00aaa"
            )?.absoluteString,
            "https://w4.uwcrcn.no/files/user_photos/nc00aaa_photo.jpg"
        )
    }

    /// The kind never comes from a document-wide substring: an href that names no
    /// people route yields `nil` and the caller decides.
    func testKindFromHref() {
        XCTAssertEqual(
            W4PeopleParser.kind(fromHref: "/index.php?r=people/staff/staff&uwc_id=nc00ccc"),
            .staff
        )
        XCTAssertEqual(
            W4PeopleParser.kind(fromHref: "/index.php?r=people/students/student&uwc_id=nc00aaa"),
            .student
        )
        // `people/students/staff` is the "my teachers" list — a staff route that
        // lives under the students module.
        XCTAssertEqual(
            W4PeopleParser.kind(fromHref: "/index.php?r=people/students/staff&type=teachers"),
            .staff
        )
        XCTAssertNil(W4PeopleParser.kind(fromHref: "/index.php?r=site/index"))
        XCTAssertNil(W4PeopleParser.kind(fromHref: ""))
    }

    func testUWCIdFromHref() {
        XCTAssertEqual(
            W4PeopleParser.uwcId(fromHref: "/index.php?r=people/students/student&uwc_id=NC00AAA"),
            "nc00aaa"
        )
        XCTAssertEqual(
            W4PeopleParser.uwcId(fromHref: "https://w4.uwcrcn.no/index.php?r=people%2Fstaff%2Fstaff&uwc_id=nc00ccc"),
            "nc00ccc"
        )
        XCTAssertNil(W4PeopleParser.uwcId(fromHref: "/index.php?r=site/logout"))
    }

    // MARK: - Malformed input

    func testEmptyAndGarbageInputDoNotThrow() {
        let empty = W4PeopleParser.parseList("")
        XCTAssertTrue(empty.people.isEmpty)
        XCTAssertNil(empty.heading)
        XCTAssertNil(empty.notice)

        let garbage = W4PeopleParser.parseList("<html><body><p>nope</p><ul><li>no ids here</li></ul></body></html>")
        XCTAssertTrue(garbage.people.isEmpty)

        XCTAssertTrue(W4PeopleParser.parsePeople("<div id=\"content_inner\"></div>").isEmpty)
        XCTAssertNil(W4PeopleParser.parseProfile(""))
        XCTAssertNil(W4PeopleParser.parseProfile("<html><body>nothing</body></html>"))
    }

    // MARK: - [I] SYNTHESIZED MARKUP — profiles

    /// **[I]** No profile page has ever been captured. `table.detail-view` is the
    /// Yii 1 `CDetailView` convention and the labels come from README §6.
    func testProfileParsesLabelledFields() throws {
        let profile = try XCTUnwrap(W4PeopleParser.parseProfile(Self.studentProfile()))

        XCTAssertEqual(profile.uwcId, "nc00aaa")
        XCTAssertEqual(profile.person.name, "Alex Andersen")
        XCTAssertEqual(profile.person.preferredName, "Al")
        XCTAssertEqual(profile.person.displayName, "Al")
        XCTAssertEqual(profile.person.year, "1", "`1st year` normalizes to `1`")
        XCTAssertEqual(profile.person.house, "Haugland")
        XCTAssertEqual(profile.person.country, "Denmark")
        XCTAssertEqual(profile.person.pronouns, "he/him")
        XCTAssertEqual(profile.person.subtitle, "Year 1 · Haugland · Denmark")
        XCTAssertEqual(profile.birthday, "3 March")
        XCTAssertEqual(profile.lastLogin, "15-Aug-2026 09:14")
        XCTAssertEqual(
            profile.person.photoURL?.absoluteString,
            "https://w4.uwcrcn.no/files/user_photos/nc00aaa_photo.jpg"
        )
    }

    /// README §6: every account's address is `{uwc_id}@uwcrcn.no`. Whatever the
    /// page printed is kept separately so the UI can show it, but it never
    /// becomes the address the app uses.
    func testProfileEmailIsDerivedNotScraped() throws {
        let profile = try XCTUnwrap(W4PeopleParser.parseProfile(Self.studentProfile()))

        XCTAssertEqual(profile.person.email, "nc00aaa@uwcrcn.no")
        XCTAssertEqual(profile.scrapedEmail, "alex.andersen@uwcrcn.no")
        XCTAssertNotEqual(profile.person.email, profile.scrapedEmail)
    }

    /// **[I] markup, [V] rule.** The page links a *staff* profile (the student's
    /// advisor). A document-wide `people/staff` sniff — `W4PeopleParser.kt:67-73` —
    /// would label this student as staff. The kind is taken from the anchor whose
    /// `uwc_id` matches the profile's own id.
    func testProfileKindIgnoresOtherPeoplesLinks() throws {
        let profile = try XCTUnwrap(W4PeopleParser.parseProfile(Self.studentProfile()))
        XCTAssertEqual(profile.person.kind, .student)
        XCTAssertEqual(profile.person.profileRoute, "people/students/student&uwc_id=nc00aaa")
    }

    /// **[I]** The mirror image: a staff profile that links a student.
    func testStaffProfileKindComesFromItsOwnLink() throws {
        let html = """
            <div id="content_inner">
              <h2>Chris Chen</h2>
              <a href="/index.php?r=people/staff/staff&amp;uwc_id=nc00ccc"><img class="photo" src="/files/user_photos/nc00ccc_thumb.jpg" alt="Photo of nc00ccc"></a>
              <table class="detail-view">
                <tr><th>UWC id</th><td>nc00ccc</td></tr>
                <tr><th>First name</th><td>Chris</td></tr>
                <tr><th>Last name</th><td>Chen</td></tr>
              </table>
              <p>Tutor group: <a href="/index.php?r=people/students/student&amp;uwc_id=nc00aaa">Alex Andersen</a></p>
            </div>
            """
        let profile = try XCTUnwrap(W4PeopleParser.parseProfile(html))

        XCTAssertEqual(profile.uwcId, "nc00ccc")
        XCTAssertEqual(profile.person.kind, .staff)
        XCTAssertEqual(profile.person.name, "Chris Chen")
    }

    /// The caller knows which route it fetched; that beats anything on the page.
    func testProfileKindParameterWins() throws {
        let html = """
            <div id="content_inner">
              <table class="detail-view">
                <tr><th>UWC id</th><td>nc00fff</td></tr>
                <tr><th>First name</th><td>Fran</td></tr>
              </table>
            </div>
            """
        XCTAssertEqual(try XCTUnwrap(W4PeopleParser.parseProfile(html)).person.kind, .student,
                       "no evidence on the page: the honest default")
        XCTAssertEqual(
            try XCTUnwrap(W4PeopleParser.parseProfile(html, kind: .staff)).person.kind,
            .staff
        )
    }

    /// A profile with no id is not addressable, and inventing one would be worse
    /// than returning nothing.
    func testProfileWithoutAUWCIdReturnsNil() {
        let html = """
            <div id="content_inner">
              <h2>Nobody</h2>
              <table class="detail-view"><tr><th>First name</th><td>Nobody</td></tr></table>
            </div>
            """
        XCTAssertNil(W4PeopleParser.parseProfile(html))
    }

    /// **[I]** Fields this parser has never heard of still reach the UI verbatim,
    /// in document order, and are searchable by label.
    func testProfileKeepsUnknownFieldsVerbatim() throws {
        let profile = try XCTUnwrap(W4PeopleParser.parseProfile(Self.studentProfile()))

        XCTAssertEqual(profile.fields.first?.label, "UWC id")
        XCTAssertEqual(profile.value(forLabel: "Preferred name"), "Al")
        XCTAssertEqual(profile.value(forLabel: "NC/SO"), "NC")
        XCTAssertEqual(profile.value(forLabel: "uwc_id"), "nc00aaa",
                       "label lookup is case- and punctuation-insensitive")
        XCTAssertNil(profile.value(forLabel: "Shoe size"))
    }

    /// **[V]** Live staff pages (`people/staff/staff`) use `dl/dt/dd`, not
    /// `table.detail-view`. Students want role, contact, taught classes and EA
    /// activities — not house/year.
    func testStaffProfileParsesRolesContactClassesAndEA() throws {
        let profile = try XCTUnwrap(W4PeopleParser.parseProfile(try fixture("staff-profile"), kind: .staff))

        XCTAssertEqual(profile.uwcId, "nc00ccc")
        XCTAssertEqual(profile.person.name, "Chris Chen")
        XCTAssertEqual(profile.person.kind, .staff)
        XCTAssertEqual(profile.person.country, "China")
        XCTAssertEqual(profile.scrapedEmail, "chris.chen@uwcrcn.no")
        XCTAssertEqual(profile.officeTel, "7022")
        XCTAssertEqual(profile.mobile, "40432379")
        XCTAssertEqual(profile.birthday, "17-Nov")
        XCTAssertEqual(profile.positions, ["Advisor", "EA Leader", "Economics", "Mathematics", "Teacher"])
        XCTAssertEqual(
            profile.person.photoURL?.absoluteString,
            "https://w4.uwcrcn.no/files/user_photos/nc00ccc_photo.jpg"
        )
        XCTAssertEqual(profile.taughtClasses.count, 3)
        let econ = try XCTUnwrap(profile.taughtClasses.first { $0.classId == "1EA16CECOX" })
        XCTAssertEqual(econ.name, "Economics")
        XCTAssertEqual(econ.year, "1")
        XCTAssertEqual(econ.levelLabel, "HL/SL")
        XCTAssertEqual(econ.room, "A 1.6")
        let advisor = try XCTUnwrap(profile.taughtClasses.first { $0.classId == "Chris" })
        XCTAssertEqual(advisor.name, "Advisor group")
        XCTAssertEqual(advisor.room, "Leif Høegh")
        XCTAssertEqual(profile.activities.count, 2)
        XCTAssertEqual(profile.activities[0].name, "Campus responsibility Peer tutoring Economics")
        XCTAssertEqual(profile.activities[0].dates, "01-Apr-2026 to 31-Mar-2027")
        XCTAssertEqual(profile.activities[0].category, "service")
    }

    func testKitchenStaffProfileHasRoleAndNoClasses() throws {
        let profile = try XCTUnwrap(W4PeopleParser.parseProfile(try fixture("staff-kitchen")))
        XCTAssertEqual(profile.uwcId, "nc00ddd")
        XCTAssertEqual(profile.person.kind, .staff)
        XCTAssertEqual(profile.positions, ["Kitchen"])
        XCTAssertEqual(profile.scrapedEmail, "dana.dahl@uwcrcn.no")
        XCTAssertNil(profile.officeTel)
        XCTAssertNil(profile.mobile)
        XCTAssertTrue(profile.taughtClasses.isEmpty)
        XCTAssertTrue(profile.activities.isEmpty)
        XCTAssertEqual(profile.person.country, "Norway")
    }

    /// Live `people/students/student` shape captured 21 Aug 2026: `dl/dt/dd`,
    /// `Birth date` as `28-Jan`, and `{name}'s classes` with `class_id` captions.
    /// Identities in the fixture are invented; the markup is not.
    func testStudentProfileParsesClassesBirthdayAdvisorAndDoesNotLookLikeStaff() throws {
        let profile = try XCTUnwrap(W4PeopleParser.parseProfile(try fixture("student-profile")))

        XCTAssertEqual(profile.uwcId, "nc00aaa")
        XCTAssertEqual(profile.person.kind, .student)
        XCTAssertEqual(profile.person.preferredName, "Al")
        XCTAssertEqual(profile.person.year, "1")
        XCTAssertEqual(profile.person.house, "Sweden")
        XCTAssertEqual(profile.houseId, "sweden")
        XCTAssertEqual(profile.room, "103")
        XCTAssertEqual(profile.person.pronouns, "he/him/his")
        XCTAssertEqual(profile.birthday, "28-Jan")
        XCTAssertEqual(profile.graduationYear, "2028")
        XCTAssertEqual(profile.mobile, "+45 12 34 56 78")
        XCTAssertEqual(profile.advisor?.uwcId, "nc00ccc")
        XCTAssertEqual(profile.advisor?.name, "Chris Chen")
        XCTAssertEqual(profile.taughtClasses.count, 5)
        let econ = try XCTUnwrap(profile.taughtClasses.first { $0.classId == "1EA16CECOX" })
        XCTAssertEqual(econ.name, "Economics")
        XCTAssertEqual(econ.year, "1")
        XCTAssertEqual(econ.levelLabel, "HL/SL")
        XCTAssertEqual(econ.teacher, "Mona Eide Onstad")
        XCTAssertEqual(econ.room, "A 1.6")
        let math = try XCTUnwrap(profile.taughtClasses.first { $0.classId == "1DA13HMTAA" })
        XCTAssertEqual(math.levelLabel, "HL")
        let spanish = try XCTUnwrap(profile.taughtClasses.first { $0.classId == "1YK12SSPAB" })
        XCTAssertEqual(spanish.levelLabel, "SL")
        let advisorGroup = try XCTUnwrap(profile.taughtClasses.first { $0.classId == "Julius" })
        XCTAssertEqual(advisorGroup.name, "Advisor group")
        XCTAssertNil(advisorGroup.levelLabel)
        XCTAssertEqual(profile.activities.count, 0)
    }

    // MARK: - Synthesized markup builders ([I] — invented, never captured)

    /// A Yii `CGridView` people list. `firstRowCells` are the two middle columns,
    /// so a test can shuffle the header and the cells together.
    private static func grid(
        headers: [String] = ["Name", "Country", "House", "Status"],
        firstRowCells: [String] = ["Denmark", "Haugland"]
    ) -> String {
        let headerHTML = headers.map { "<th><a href=\"#\">\($0)</a></th>" }.joined()
        let middle = firstRowCells.map { "<td>\($0)</td>" }.joined()
        return """
            <div id="content_inner">
              <h2>All students</h2>
              <div class="grid-view" id="students-grid">
                <div class="summary">Displaying 1-2 of 187 results.</div>
                <table class="items">
                  <thead><tr>\(headerHTML)</tr></thead>
                  <tbody>
                    <tr class="odd online">
                      <td class="student-name"><a href="/index.php?r=people/students/student&amp;uwc_id=nc00aaa">Alex Andersen</a></td>
                      \(middle)
                      <td class="status">Online</td>
                    </tr>
                    <tr class="even offline">
                      <td class="entry-name"><a href="/index.php?r=people/staff/staff&amp;uwc_id=nc00ccc">Chris Chen</a></td>
                      <td>Norway</td>
                      <td>Fjord</td>
                      <td class="status">Offline</td>
                    </tr>
                  </tbody>
                </table>
                <div class="pager">
                  <ul class="yiiPager">
                    <li class="previous hidden"><a href="#">&lt; Previous</a></li>
                    <li class="page selected"><a href="#">1</a></li>
                    <li class="next"><a href="/index.php?r=people/students/all&amp;page=2">Next &gt;</a></li>
                  </ul>
                </div>
              </div>
            </div>
            """
    }

    /// A Yii `CDetailView` student profile that also links somebody else's staff
    /// profile — the shape that breaks a document-wide kind sniff.
    private static func studentProfile() -> String {
        """
        <div id="content_inner">
          <h2>Alex Andersen</h2>
          <img class="photo" src="/files/user_photos/nc00aaa_thumb.jpg" alt="Photo of nc00aaa">
          <table class="detail-view">
            <tr><th>UWC id</th><td>nc00aaa</td></tr>
            <tr><th>First name</th><td>Alex</td></tr>
            <tr><th>Last name</th><td>Andersen</td></tr>
            <tr><th>Preferred name</th><td>Al</td></tr>
            <tr><th>Pronouns</th><td>he/him</td></tr>
            <tr><th>Year</th><td>1st year</td></tr>
            <tr><th>House</th><td>Haugland</td></tr>
            <tr><th>Country</th><td>Denmark</td></tr>
            <tr><th>NC/SO</th><td>NC</td></tr>
            <tr><th>Email</th><td>alex.andersen@uwcrcn.no</td></tr>
            <tr><th>Last login</th><td>15-Aug-2026 09:14</td></tr>
            <tr><th>Birthday</th><td>3 March</td></tr>
          </table>
          <p>Advisor: <a href="/index.php?r=people/staff/staff&amp;uwc_id=nc00ccc">Chris Chen</a></p>
        </div>
        """
    }
}
