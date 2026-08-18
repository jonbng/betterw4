//
//  W4NotificationParserTests.swift
//  BetterW4Tests
//
//  Tests for W4NotificationParser + NotificationModels (Wave 4 item 4.5).
//
//  EVIDENCE MAP — read this before adding an assertion.
//
//    [V] `#header div.notifications` exists on every authenticated page, and in
//        BOTH real captures we have (home.html, documents.html) it is EMPTY:
//
//            <div class="notifications">
//            </div>
//
//        Zero notifications is the NORMAL state at this school. That is the
//        whole of bug B8: the empty bell is a success, not a parse failure, and
//        it is the only notification markup anyone has ever seen from W4.
//
//    [I] Every populated shape in this file — the fixture
//        `notifications-populated.html` and every inline snippet — is
//        SYNTHESIZED from the class and attribute names that the server's own
//        `notifications.js` / `notifications.css` use. Those NAMES are real;
//        their ARRANGEMENT is invented. So every populated assertion verifies
//        THE PARSER, not W4, and says so.
//
//  Nothing in this file may be read as evidence that W4 renders a populated
//  bell in the shape assumed here.
//

import XCTest
@testable import BetterW4

final class W4NotificationParserTests: XCTestCase {

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

    // MARK: - [V] The real captures: an EMPTY bell (bug B8)

    /// The captured Home page ships `<div class="notifications">\n</div>`.
    /// The parser must report that as an empty snapshot — explicitly, not by
    /// falling through to the document body and happening to count zero
    /// anchors, which is how the Kotlin port survives this page.
    func testCapturedHomePageHasAnExplicitlyEmptyBell() throws {
        let snapshot = W4NotificationParser.parse(try fixture("home"))

        XCTAssertEqual(snapshot, .empty)
        XCTAssertTrue(snapshot.isEmpty)
        XCTAssertEqual(snapshot.count, 0)
        XCTAssertEqual(snapshot.severity, .normal)
        XCTAssertTrue(snapshot.taskGroups.isEmpty)
        XCTAssertTrue(snapshot.emailGroups.isEmpty)
        XCTAssertTrue(snapshot.items.isEmpty)
    }

    /// The bell is chrome, so the same empty result has to come off any
    /// authenticated page. `documents.html` is a real capture of `?r=documents`.
    func testCapturedDocumentsPageHasAnExplicitlyEmptyBell() throws {
        let snapshot = W4NotificationParser.parse(try fixture("documents"))
        XCTAssertEqual(snapshot, .empty)
    }

    func testEmptyBellAndMissingBellBothDegradeToTheSameSnapshot() throws {
        // Both are `.empty`, deliberately: the UI has nothing to show either
        // way, and inventing a distinction the transport layer cannot act on
        // would be dishonest. Session death is detected by the HTTP layer, not
        // here (reviewer-notes.md §3).
        XCTAssertEqual(W4NotificationParser.parse(try fixture("home")), .empty)
        XCTAssertEqual(W4NotificationParser.parse("<html><body><p>no bell here</p></body></html>"), .empty)
    }

    func testRefreshRouteIsTheOneThePagePublishes() {
        // `var notification_urls = {…'refresh':'/index.php?r=notifications/refresh'…}` [V].
        XCTAssertEqual(W4NotificationParser.refreshRoute, "notifications/refresh")
        XCTAssertEqual(W4NotificationParser.refreshRoute, W4Routes.R.notificationsRefresh)
    }

    // MARK: - [I] SYNTHESIZED fixture — verifies the parser, not W4

    /// **[I]** `notifications-populated.html` is SYNTHESIZED. See the comment
    /// at the top of that file: no populated W4 bell has ever been captured.
    func testSynthesizedPopulatedBellCountsAndGroups() throws {
        let snapshot = W4NotificationParser.parse(try fixture("notifications-populated"))

        XCTAssertFalse(snapshot.isEmpty)
        XCTAssertEqual(snapshot.count, 3, "the div.alert badge text")
        XCTAssertEqual(snapshot.taskGroups.count, 1)
        XCTAssertEqual(snapshot.emailGroups.count, 1)
        XCTAssertEqual(snapshot.items.count, 3, "two tasks plus one email")
    }

    /// **[I]** Synthesized markup.
    func testSynthesizedTaskGroupKeepsItsTypeTitleAndSeverity() throws {
        let snapshot = W4NotificationParser.parse(try fixture("notifications-populated"))
        let group = try XCTUnwrap(snapshot.taskGroups.first)

        XCTAssertEqual(group.type, "assessment", "data-notification-type off the <dt>'s a.read")
        // The <dt> also holds the "read" action anchor. Its text must NOT be
        // regex-stripped out of the title (parsers.md §3) — the anchor is
        // dropped as an element instead.
        XCTAssertEqual(group.title, "Assessments")
        XCTAssertEqual(group.severity, .overdue)
        XCTAssertEqual(group.id, "assessment")
        XCTAssertEqual(group.items.count, 2)
    }

    /// **[I]** Synthesized markup.
    func testSynthesizedTaskRowSplitsTitleFromDeadlineAndKeepsBothHrefAndRoute() throws {
        let snapshot = W4NotificationParser.parse(try fixture("notifications-populated"))
        let group = try XCTUnwrap(snapshot.taskGroups.first)
        let item = try XCTUnwrap(group.items.first)

        XCTAssertEqual(item.id, "12", "data-notification-id — the id read/clear expect")
        XCTAssertEqual(item.title, "Biology IA draft", "span.deadline must not leak into the title")
        XCTAssertEqual(item.subtitle, "Due 12-Aug-2026")
        XCTAssertEqual(item.route, "academics/deadlines")
        XCTAssertEqual(item.href, "/index.php?r=academics/deadlines&id=12")
        XCTAssertEqual(item.section, .task)
        XCTAssertEqual(item.severity, .overdue)
        // The row inherits the group's type when it carries none of its own.
        XCTAssertEqual(item.type, "assessment")

        // `route` alone loses the sibling id, which is why `href` is kept too.
        let url = try XCTUnwrap(item.url)
        XCTAssertEqual(url.host, "w4.uwcrcn.no")
        XCTAssertTrue(url.absoluteString.contains("id=12"), "the sibling id survives the round trip")
    }

    /// **[I]** Synthesized markup.
    func testSynthesizedEmailGroupIsReadFromTheEmailList() throws {
        let snapshot = W4NotificationParser.parse(try fixture("notifications-populated"))
        let group = try XCTUnwrap(snapshot.emailGroups.first)

        XCTAssertEqual(group.title, "Inbox")
        XCTAssertEqual(group.type, "email")
        XCTAssertEqual(group.severity, .normal, "the <dt> carries no severity class")

        let item = try XCTUnwrap(group.items.first)
        XCTAssertEqual(item.id, "88", "read from a.clear when there is no a.read")
        XCTAssertEqual(item.title, "Kayaking trip briefing")
        XCTAssertEqual(item.subtitle, "2 days ago", "span.duration")
        XCTAssertEqual(item.route, "mailer/view")
        XCTAssertEqual(item.section, .email)
        XCTAssertEqual(item.severity, .new)
    }

    /// **[I]** Synthesized markup. The Tasks heading must not swallow the
    /// Emails list: `definitionList(after:)` stops at the next `<h3>`.
    func testSynthesizedTasksAndEmailsDoNotShareADefinitionList() throws {
        let snapshot = W4NotificationParser.parse(try fixture("notifications-populated"))

        XCTAssertEqual(snapshot.taskGroups.flatMap(\.items).map(\.id), ["12", "13"])
        XCTAssertEqual(snapshot.emailGroups.flatMap(\.items).map(\.id), ["88"])
        XCTAssertTrue(snapshot.taskGroups.flatMap(\.items).allSatisfy { $0.section == .task })
        XCTAssertTrue(snapshot.emailGroups.flatMap(\.items).allSatisfy { $0.section == .email })
    }

    /// **[I]** Synthesized markup. The badge's own class wins over the most
    /// severe row — the fixture deliberately puts an `overdue` row under a
    /// `new` badge so this cannot pass by accident.
    func testSynthesizedBadgeClassWinsOverRowSeverity() throws {
        let snapshot = W4NotificationParser.parse(try fixture("notifications-populated"))

        XCTAssertEqual(snapshot.severity, .new, "div.alert.new")
        XCTAssertTrue(
            snapshot.items.contains { $0.severity == .overdue },
            "…even though an overdue row is present"
        )
    }

    // MARK: - [I] SYNTHESIZED inline shapes

    /// **[I]** `notifications.js:65` does
    /// `$('#header div.notifications').html($(data).children())`, so the
    /// refresh payload is a WRAPPER whose CHILDREN are the new content — there
    /// is no `div.notifications` in it. The exact payload has never been seen.
    func testSynthesizedRefreshFragmentWithoutTheOuterContainerStillParses() throws {
        let fragment = """
            <div><div class="btn-group">
              <div class="alert overdue">1</div>
              <div class="dropdown-menu">
                <h3 class="tasks">Tasks</h3>
                <dl>
                  <dt class="overdue">Assessments<a class="read" data-notification-type="assessment">read</a></dt>
                  <dd><ul><li class="overdue">
                    <a href="/index.php?r=academics/deadlines&amp;id=7">Physics IA <span class="deadline">Overdue</span></a>
                    <a class="read" data-notification-id="7">read</a>
                  </li></ul></dd>
                </dl>
              </div>
            </div></div>
            """
        let snapshot = W4NotificationParser.parse(fragment)

        XCTAssertEqual(snapshot.count, 1)
        XCTAssertEqual(snapshot.severity, .overdue)
        XCTAssertEqual(snapshot.taskGroups.count, 1)
        XCTAssertEqual(snapshot.taskGroups.first?.items.first?.id, "7")
        XCTAssertTrue(snapshot.emailGroups.isEmpty)
    }

    /// **[I]** A row with no `data-notification-id` cannot be marked read or
    /// cleared, and inventing an id would post garbage back to the server. The
    /// parser drops it — loudly — rather than shipping an unactionable row.
    func testSynthesizedRowWithoutANotificationIDIsDropped() {
        let fragment = """
            <div class="notifications"><div class="btn-group"><div class="dropdown-menu">
              <h3 class="tasks">Tasks</h3>
              <dl>
                <dt>Assessments</dt>
                <dd><ul>
                  <li><a href="/index.php?r=academics/deadlines&amp;id=1">No id here</a></li>
                  <li><a href="/index.php?r=academics/deadlines&amp;id=2">Has an id</a>
                      <a class="read" data-notification-id="2">read</a></li>
                </ul></dd>
              </dl>
            </div></div></div>
            """
        let snapshot = W4NotificationParser.parse(fragment)

        XCTAssertEqual(snapshot.items.map(\.id), ["2"])
        XCTAssertEqual(snapshot.count, 1, "no badge, so the count is the distinct parsed ids")
    }

    /// **[I]** `9+` and similar badge texts are unverified. When the badge is
    /// not an integer the parser reports the honest number of parsed rows
    /// instead of guessing.
    func testSynthesizedNonNumericBadgeFallsBackToTheParsedCount() {
        let fragment = """
            <div class="notifications"><div class="btn-group">
              <div class="alert new">9+</div>
              <div class="dropdown-menu">
                <dl>
                  <dt>Assessments</dt>
                  <dd><ul>
                    <li><a href="#">A</a><a class="read" data-notification-id="1">read</a></li>
                    <li><a href="#">B</a><a class="read" data-notification-id="2">read</a></li>
                  </ul></dd>
                </dl>
              </div>
            </div></div>
            """
        let snapshot = W4NotificationParser.parse(fragment)

        XCTAssertEqual(snapshot.count, 2)
        XCTAssertEqual(snapshot.severity, .new, "the badge class is still readable")
        XCTAssertEqual(snapshot.items.map(\.id), ["1", "2"])
    }

    /// **[I]** With no badge at all the snapshot severity is the most severe
    /// thing parsed.
    func testSynthesizedSeverityWithoutABadgeIsTheMostSevereRow() {
        let fragment = """
            <div class="notifications"><div class="btn-group"><div class="dropdown-menu">
              <dl>
                <dt>Assessments</dt>
                <dd><ul>
                  <li class="normal"><a href="#">A</a><a class="read" data-notification-id="1">read</a></li>
                  <li class="overdue"><a href="#">B</a><a class="read" data-notification-id="2">read</a></li>
                </ul></dd>
              </dl>
            </div></div></div>
            """
        XCTAssertEqual(W4NotificationParser.parse(fragment).severity, .overdue)
    }

    /// **[I]** A group heading whose own words contain "read" or "clear" must
    /// survive. parsers.md §3 warns against the Kotlin approach of regex
    /// -stripping those literals out of the finished string.
    func testSynthesizedGroupTitleContainingTheWordReadIsNotMangled() throws {
        let fragment = """
            <div class="notifications"><div class="btn-group"><div class="dropdown-menu">
              <dl>
                <dt>Reading and Clearance<a class="read" data-notification-type="reading">read</a></dt>
                <dd><ul><li><a href="#">Row</a><a class="clear" data-notification-id="5">clear</a></li></ul></dd>
              </dl>
            </div></div></div>
            """
        let snapshot = W4NotificationParser.parse(fragment)
        let group = try XCTUnwrap(snapshot.taskGroups.first)

        XCTAssertEqual(group.title, "Reading and Clearance")
        XCTAssertEqual(group.type, "reading")
    }

    // MARK: - Degradation

    func testEmptyAndGarbageInputDegradeToAnEmptySnapshot() {
        XCTAssertEqual(W4NotificationParser.parse(""), .empty)
        XCTAssertEqual(W4NotificationParser.parse("   "), .empty)
        XCTAssertEqual(W4NotificationParser.parse("not html at all <<<>>>"), .empty)
        XCTAssertEqual(W4NotificationParser.parse("<div class=\"notifications\"></div>"), .empty)
    }

    // MARK: - Action bodies (W4NotificationAction)

    func testActionRoutesMatchTheEightPublishedEndpoints() {
        XCTAssertEqual(W4NotificationAction.allCases.count, 8)
        XCTAssertEqual(W4NotificationAction.read.route, "notifications/read")
        XCTAssertEqual(W4NotificationAction.readGroup.route, "notifications/readgroup")
        XCTAssertEqual(W4NotificationAction.readAll.route, "notifications/readall")
        XCTAssertEqual(W4NotificationAction.readAllEmails.route, "notifications/readallemails")
        XCTAssertEqual(W4NotificationAction.clear.route, "notifications/clear")
        XCTAssertEqual(W4NotificationAction.clearGroup.route, "notifications/cleargroup")
        XCTAssertEqual(W4NotificationAction.clearAll.route, "notifications/clearall")
        XCTAssertEqual(W4NotificationAction.refresh.route, "notifications/refresh")
    }

    /// OQ-9: never post `notifications/read` without a real server id.
    func testPerItemActionsRefuseToBuildABodyWithoutAnIdentifier() {
        XCTAssertNil(W4NotificationAction.read.body(nil))
        XCTAssertNil(W4NotificationAction.read.body(""))
        XCTAssertNil(W4NotificationAction.read.body("   "))
        XCTAssertNil(W4NotificationAction.clear.body(nil))
        XCTAssertNil(W4NotificationAction.readGroup.body(nil))
        XCTAssertNil(W4NotificationAction.clearGroup.body(nil))
    }

    func testActionBodiesUseTheRightFieldName() throws {
        // The identifier is trimmed, never guessed.
        XCTAssertEqual(try XCTUnwrap(W4NotificationAction.read.body(" 12 ")), ["notification_id": "12"])
        XCTAssertEqual(try XCTUnwrap(W4NotificationAction.clear.body("88")), ["notification_id": "88"])
        XCTAssertEqual(
            try XCTUnwrap(W4NotificationAction.readGroup.body("assessment")),
            ["notification_type": "assessment"]
        )
        XCTAssertEqual(
            try XCTUnwrap(W4NotificationAction.clearGroup.body("email")),
            ["notification_type": "email"]
        )
    }

    func testBulkActionsPostAnEmptyBody() throws {
        for action in [
            W4NotificationAction.readAll,
            .readAllEmails,
            .clearAll,
            .refresh
        ] {
            XCTAssertNil(action.requiredField, action.rawValue)
            let body = try XCTUnwrap(action.body(), action.rawValue)
            XCTAssertTrue(body.isEmpty, action.rawValue)
        }
    }

    /// **[I]** End to end on synthesized markup: a parsed row's `id` and
    /// `type` are exactly what the read/readGroup bodies need, so the UI never
    /// has to invent either.
    func testSynthesizedParsedRowFeedsTheActionBodiesDirectly() throws {
        let snapshot = W4NotificationParser.parse(try fixture("notifications-populated"))
        let item = try XCTUnwrap(snapshot.items.first)

        XCTAssertEqual(
            try XCTUnwrap(W4NotificationAction.read.body(item.id)),
            ["notification_id": item.id]
        )
        XCTAssertEqual(
            try XCTUnwrap(W4NotificationAction.readGroup.body(item.type)),
            ["notification_type": "assessment"]
        )
    }
}
