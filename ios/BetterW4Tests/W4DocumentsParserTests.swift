//
//  W4DocumentsParserTests.swift
//  BetterW4Tests
//
//  Tests for W4DocumentsParser + DocumentModels (Wave 4 item 4.8).
//
//  EVIDENCE MAP — read this before adding an assertion.
//
//    [V] `documents.html` is a REAL capture of
//        `https://w4.uwcrcn.no/index.php?r=documents` — the CMS root. It shows
//        `#content_inner > h2` == "Documents", a `ul.folder-list` with exactly
//        two `a.folder` entries (`folder_id=27` and `folder_id=34`), a
//        `#breadcrumb .crumbs` holding a single "Home" link to the site root,
//        and no `div.up` (the root has no parent).
//
//    [V] The CLASS NAMES `a.page`, `div.up`, `div.new`, `.page-title`,
//        `.page-details` and `.page-content` are real: the server's own
//        `Documents_files/cmsrenderer.css` styles them. `page_id=` deep links
//        are real too — the Home `#links` block emits three of them.
//
//    [I] `documents-folder.html`, `documents-page.html` and
//        `documents-empty-folder.html` are SYNTHESIZED (each one says so at the
//        top of the file). No folder containing pages, no rendered leaf page
//        and no empty folder has ever been captured, so every assertion made
//        against those three verifies THE PARSER, not W4.
//
//  The load-bearing test in this file is
//  `testSynthesizedEmptyFolderIsNotMistakenForAPage` — bug B16.
//

import XCTest
@testable import BetterW4

final class W4DocumentsParserTests: XCTestCase {

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

    private func parsed(_ name: String) throws -> DocumentListing {
        W4DocumentsParser.parse(try fixture(name))
    }

    // MARK: - [V] The real capture: the CMS root

    func testCapturedRootIsTitledDocuments() throws {
        let listing = try parsed("documents")
        XCTAssertEqual(listing.title, "Documents", "the h2 inside #content_inner, whitespace collapsed")
    }

    func testCapturedRootListsTheTwoFolders() throws {
        let listing = try parsed("documents")

        XCTAssertEqual(listing.items.count, 2)
        XCTAssertEqual(listing.items.map(\.title), ["Internal Information", "Outdoor Department"])
        XCTAssertEqual(listing.items.map(\.id), ["27", "34"])
        XCTAssertEqual(listing.items.map(\.numericID), [27, 34])
        XCTAssertEqual(listing.items.map(\.kind), [.folder, .folder])
        XCTAssertTrue(listing.items.allSatisfy(\.isFolder))
        XCTAssertEqual(listing.folders.count, 2)
        XCTAssertTrue(listing.pages.isEmpty)
    }

    /// The route is rebuilt in the `route&sibling=value` spelling that
    /// `W4Routes.url(_:)` takes back verbatim, and the raw `href` is kept
    /// alongside it for anything that would not survive that round trip.
    func testCapturedRootFolderRoutesKeepTheirFolderID() throws {
        let listing = try parsed("documents")
        let first = try XCTUnwrap(listing.items.first)

        XCTAssertEqual(first.route, "documents/index&folder_id=27")
        XCTAssertEqual(first.href, "https://w4.uwcrcn.no/index.php?r=documents/index&folder_id=27")

        let rebuilt = W4Routes.url(try XCTUnwrap(first.route))
        XCTAssertEqual(W4Routes.route(of: rebuilt), "documents/index")
        XCTAssertTrue(rebuilt.absoluteString.contains("folder_id=27"))
    }

    /// The CMS root is a folder, not a page. Deciding otherwise from
    /// `items.isEmpty` is bug B16; here the root has items, so the honest
    /// answer is obvious — but it still has to be `nil`, not an empty page.
    func testCapturedRootIsAFolderAndNotAPage() throws {
        let listing = try parsed("documents")

        XCTAssertNil(listing.page)
        XCTAssertFalse(listing.isPage)
        XCTAssertNil(listing.bodyHTML)
        XCTAssertFalse(listing.isEmpty)
    }

    /// `#breadcrumb` also contains the help widget (`a.help` and the anchors
    /// inside `#help_display`). Only `.crumbs` is navigation.
    func testCapturedRootBreadcrumbIsScopedToTheCrumbs() throws {
        let listing = try parsed("documents")

        XCTAssertEqual(listing.breadcrumb.count, 1, "the help widget must not become a crumb")
        let home = try XCTUnwrap(listing.breadcrumb.first)
        XCTAssertEqual(home.title, "Home")
        XCTAssertEqual(home.href, "https://w4.uwcrcn.no/")
        XCTAssertNil(home.route, "the site root carries no r=, so there is no route to invent")
        XCTAssertEqual(home.id, "https://w4.uwcrcn.no/")

        XCTAssertFalse(
            listing.breadcrumb.contains { $0.title == "Help" || $0.title == "Help index" },
            "help chrome leaked into the breadcrumb"
        )
    }

    /// The captured root has no `div.up` — it has no parent.
    func testCapturedRootHasNoParentLink() throws {
        XCTAssertNil(try parsed("documents").parentRoute)
    }

    // MARK: - [I] SYNTHESIZED — a folder holding folders and pages

    /// **[I]** `documents-folder.html` is SYNTHESIZED; see the comment at the
    /// top of that file. No W4 folder containing pages has ever been captured.
    func testSynthesizedFolderMixesFoldersAndPages() throws {
        let listing = try parsed("documents-folder")

        XCTAssertEqual(listing.title, "Internal Information")
        XCTAssertEqual(listing.items.count, 3)
        XCTAssertEqual(listing.items.map(\.title), ["Houses", "Bakehus", "Lavvo"])
        XCTAssertEqual(listing.items.map(\.kind), [.folder, .page, .page])
        XCTAssertEqual(listing.items.map(\.id), ["41", "870", "1004"])
        XCTAssertEqual(listing.folders.map(\.title), ["Houses"])
        XCTAssertEqual(listing.pages.map(\.title), ["Bakehus", "Lavvo"])
        XCTAssertNil(listing.page, "a folder is never a page, however many pages it holds")
    }

    /// **[I]** Synthesized. A relative `href` yields the same route as an
    /// absolute one — W4 emits both spellings across the captured pages.
    func testSynthesizedFolderRoutesSurviveRelativeHrefs() throws {
        let listing = try parsed("documents-folder")
        let lavvo = try XCTUnwrap(listing.items.first { $0.title == "Lavvo" })

        XCTAssertEqual(lavvo.href, "/index.php?r=documents/index&page_id=1004")
        XCTAssertEqual(lavvo.route, "documents/index&page_id=1004")
        XCTAssertTrue(lavvo.isPage)
    }

    /// **[I]** Synthesized. `div.up > a` is a real class name; its placement is
    /// not. `div.new` ("New page") is staff chrome and must never become a row.
    func testSynthesizedFolderReadsUpOneLevelAndIgnoresNewPage() throws {
        let listing = try parsed("documents-folder")

        XCTAssertEqual(listing.parentRoute, "documents")
        XCTAssertFalse(listing.items.contains { $0.title == "New page" }, "div.new is not a listing row")
        XCTAssertFalse(listing.items.contains { $0.title == "Up one level" })
    }

    /// **[I]** Synthesized.
    func testSynthesizedFolderBreadcrumb() throws {
        let listing = try parsed("documents-folder")

        XCTAssertEqual(listing.breadcrumb.map(\.title), ["Home", "Documents"])
        XCTAssertEqual(listing.breadcrumb.map(\.route), [nil, "documents"])
    }

    // MARK: - [I] SYNTHESIZED — a rendered leaf page

    /// **[I]** `documents-page.html` is SYNTHESIZED; see the comment at the top
    /// of that file. No rendered W4 CMS page has ever been captured.
    func testSynthesizedPageIsRecognisedByItsPageContentClass() throws {
        let listing = try parsed("documents-page")

        XCTAssertTrue(listing.isPage)
        XCTAssertTrue(listing.items.isEmpty)
        XCTAssertEqual(listing.title, "Fire Drill Procedure")

        let page = try XCTUnwrap(listing.page)
        XCTAssertEqual(page.title, "Fire Drill Procedure", ".page-title")
        XCTAssertEqual(page.details, "Last updated 04-Sep-2025 by Alex Andersen", ".page-details")
        XCTAssertEqual(listing.bodyHTML, page.contentHTML)
    }

    /// **[I]** Synthesized. The body is the raw inner HTML of `.page-content`
    /// and nothing else — no heading, no navigation chrome. It is untrusted
    /// TinyMCE output and is kept verbatim for a renderer to sanitise later.
    func testSynthesizedPageBodyIsTheRawPageContentOnly() throws {
        let page = try XCTUnwrap(try parsed("documents-page").page)

        XCTAssertTrue(page.contentHTML.contains("<strong>nearest exit</strong>"), page.contentHTML)
        XCTAssertTrue(page.contentHTML.contains("<li>Assemble at the flagpole.</li>"), page.contentHTML)
        XCTAssertTrue(page.contentHTML.contains("page_id=871"), "inline links are preserved")

        XCTAssertFalse(page.contentHTML.contains("page-title"), "the heading is not part of the body")
        XCTAssertFalse(page.contentHTML.contains("Up one level"), "navigation is not part of the body")
        XCTAssertFalse(page.contentHTML.contains("page-details"))
        XCTAssertFalse(page.contentHTML.contains("Welcome, Alex Andersen"), "chrome is not part of the body")
    }

    /// **[I]** Synthesized. An anchor inside the page body has no `a.page` or
    /// `a.folder` class, so it must not be promoted into a folder listing.
    func testSynthesizedPageBodyLinksDoNotBecomeListingRows() throws {
        let listing = try parsed("documents-page")

        XCTAssertTrue(listing.items.isEmpty)
        XCTAssertFalse(listing.items.contains { $0.title == "Learning support" })
    }

    /// **[I]** Synthesized.
    func testSynthesizedPageBreadcrumbAndParent() throws {
        let listing = try parsed("documents-page")

        XCTAssertEqual(listing.breadcrumb.map(\.title), ["Home", "Documents", "Internal Information"])
        XCTAssertEqual(
            listing.breadcrumb.map(\.route),
            [nil, "documents", "documents/index&folder_id=27"]
        )
        XCTAssertEqual(listing.parentRoute, "documents/index&folder_id=27")
    }

    // MARK: - [I] SYNTHESIZED — bug B16, the empty folder

    /// **[I]** THE load-bearing test of item 4.8, on synthesized markup
    /// (`documents-empty-folder.html`; no empty W4 folder has been captured).
    ///
    /// The Kotlin port decides "this is a page" from the ABSENCE of folder and
    /// page links and then dumps `#content_inner` as the body — which turns
    /// every empty folder into a bogus page whose content is the surrounding
    /// chrome. An empty `ul.folder-list` is an empty FOLDER.
    func testSynthesizedEmptyFolderIsNotMistakenForAPage() throws {
        let listing = try parsed("documents-empty-folder")

        XCTAssertTrue(listing.items.isEmpty)
        XCTAssertNil(listing.page, "bug B16: an empty folder is not a page")
        XCTAssertFalse(listing.isPage)
        XCTAssertNil(listing.bodyHTML)
        XCTAssertTrue(listing.isEmpty, "nothing to show — but it is an honest nothing")

        // The listing is still usable: title and navigation survive.
        XCTAssertEqual(listing.title, "Outdoor Department")
        XCTAssertEqual(listing.parentRoute, "documents")
        XCTAssertEqual(listing.breadcrumb.map(\.title), ["Home", "Documents"])
    }

    // MARK: - [I] SYNTHESIZED — the fenced B16 fallback

    /// **[I]** When `.page-content` is genuinely absent the parser falls back
    /// to the Kotlin heuristic, but only inside a real `#content_inner` with no
    /// `.folder-list` at all. This shape has never been captured either.
    func testSynthesizedPageWithoutPageContentUsesTheFencedFallback() throws {
        let html = """
            <html><body><div id="content_frame"><div id="content_main">
              <div id="content_inner">
                <h2>House Rules</h2>
                <div class="up"><a href="https://w4.uwcrcn.no/index.php?r=documents">Up one level</a></div>
                <p>Quiet hours start at 22:30.</p>
              </div>
            </div></div></body></html>
            """
        let listing = W4DocumentsParser.parse(html)
        let page = try XCTUnwrap(listing.page)

        XCTAssertEqual(page.title, "House Rules")
        XCTAssertNil(page.details)
        XCTAssertTrue(page.contentHTML.contains("Quiet hours start at 22:30."), page.contentHTML)
        XCTAssertFalse(page.contentHTML.contains("<h2>"), "the heading is dropped")
        XCTAssertFalse(page.contentHTML.contains("Up one level"), "div.up is CMS chrome, not body")
        XCTAssertEqual(listing.parentRoute, "documents")
    }

    /// **[I]** Without a `#content_inner` the fallback is refused outright:
    /// "the whole body" is not a page body. An AJAX fragment or a page whose
    /// shape changed must degrade, not invent a document out of chrome.
    func testFragmentWithoutContentInnerNeverBecomesAPage() {
        let listing = W4DocumentsParser.parse("""
            <html><body><div id="header">UWCRCN W4</div><p>Some stray text.</p></body></html>
            """)

        XCTAssertNil(listing.page)
        XCTAssertTrue(listing.items.isEmpty)
        XCTAssertEqual(listing, .empty)
    }

    /// **[I]** An empty `.page-content` is still a page: W4 said "here is a
    /// page", it just has no body. Reporting `nil` would lose that fact.
    func testSynthesizedEmptyPageContentIsStillAPage() throws {
        let listing = W4DocumentsParser.parse("""
            <html><body><div id="content_inner">
              <h1 class="page-title">Blank</h1>
              <div class="page-content"></div>
            </div></body></html>
            """)

        let page = try XCTUnwrap(listing.page)
        XCTAssertEqual(page.title, "Blank")
        XCTAssertTrue(page.contentHTML.isEmpty)
        XCTAssertTrue(listing.isPage)
    }

    // MARK: - [I] SYNTHESIZED — listing edge cases

    /// **[I]** A renderer that splits the icon and the label into two anchors
    /// with the same `href` must produce one row, not two, and the row must
    /// keep the label.
    func testSynthesizedDuplicateAnchorsForOneEntryCollapseToOneRow() throws {
        let listing = W4DocumentsParser.parse("""
            <html><body><div id="content_inner"><h2>Internal Information</h2>
            <ul class="folder-list"><li>
              <a class="folder" href="https://w4.uwcrcn.no/index.php?r=documents/index&amp;folder_id=41"></a>
              <a class="folder" href="https://w4.uwcrcn.no/index.php?r=documents/index&amp;folder_id=41">Houses</a>
            </li></ul>
            </div></body></html>
            """)

        XCTAssertEqual(listing.items.count, 1)
        XCTAssertEqual(listing.items.first?.title, "Houses")
        XCTAssertEqual(listing.items.first?.id, "41")
    }

    /// **[I]** An icon-only link is real in this renderer, so an empty title is
    /// tolerated rather than dropping the row; `title=` and the icon's `alt=`
    /// are tried first.
    func testSynthesizedIconOnlyAnchorFallsBackToTitleAttributeThenAlt() throws {
        let listing = W4DocumentsParser.parse("""
            <html><body><div id="content_inner"><h2>Docs</h2>
            <ul class="folder-list">
              <li><a class="folder" title="Houses"
                     href="https://w4.uwcrcn.no/index.php?r=documents/index&amp;folder_id=41"></a></li>
              <li><a class="page"
                     href="https://w4.uwcrcn.no/index.php?r=documents/index&amp;page_id=870"><img alt="Bakehus" src="i.png"></a></li>
              <li><a class="folder"
                     href="https://w4.uwcrcn.no/index.php?r=documents/index&amp;folder_id=99"></a></li>
            </ul>
            </div></body></html>
            """)

        XCTAssertEqual(listing.items.map(\.title), ["Houses", "Bakehus", ""])
        XCTAssertEqual(listing.items.map(\.id), ["41", "870", "99"])
    }

    /// **[I]** A CSS class beats the query parameters, and a documents link
    /// with neither is the CMS root, which is a folder. A row that carries no
    /// id at all is keyed by its `href` so it is still uniquely addressable.
    func testSynthesizedKindFallsBackToQueryParametersThenToFolder() throws {
        let listing = W4DocumentsParser.parse("""
            <html><body><div id="content_inner"><h2>Docs</h2>
            <ul class="folder-list">
              <li><a href="https://w4.uwcrcn.no/index.php?r=documents/index&amp;page_id=870">By page_id</a></li>
              <li><a href="https://w4.uwcrcn.no/index.php?r=documents/index&amp;folder_id=27">By folder_id</a></li>
              <li><a href="https://w4.uwcrcn.no/index.php?r=documents">No id at all</a></li>
            </ul>
            </div></body></html>
            """)

        XCTAssertEqual(listing.items.map(\.kind), [.page, .folder, .folder])
        XCTAssertEqual(listing.items.map(\.id), [
            "870",
            "27",
            "https://w4.uwcrcn.no/index.php?r=documents"
        ])
        XCTAssertNil(listing.items.last?.numericID)
    }

    /// **[I]** The second rung of the ladder: a renderer that drops the `ul`
    /// wrapper still yields rows, because both rungs are class-driven.
    func testSynthesizedFolderListWithoutTheULWrapperStillParses() {
        let listing = W4DocumentsParser.parse("""
            <html><body><div id="content_inner"><h2>Docs</h2>
              <a class="folder" href="https://w4.uwcrcn.no/index.php?r=documents/index&amp;folder_id=27">Internal Information</a>
              <a class="page" href="https://w4.uwcrcn.no/index.php?r=documents/index&amp;page_id=870">Bakehus</a>
            </div></body></html>
            """)

        XCTAssertEqual(listing.items.map(\.id), ["27", "870"])
        XCTAssertEqual(listing.items.map(\.kind), [.folder, .page])
        XCTAssertNil(listing.page, "folder/page links were found, so this is not a page")
    }

    // MARK: - Routes

    func testRouteFromHref() {
        XCTAssertEqual(
            W4DocumentsParser.route(fromHref: "https://w4.uwcrcn.no/index.php?r=documents/index&folder_id=27"),
            "documents/index&folder_id=27"
        )
        XCTAssertEqual(
            W4DocumentsParser.route(fromHref: "/index.php?r=documents/index&page_id=1004"),
            "documents/index&page_id=1004"
        )
        XCTAssertEqual(W4DocumentsParser.route(fromHref: "index.php?r=documents"), "documents")
        // Trailing slashes are stripped so routes compare equal.
        XCTAssertEqual(W4DocumentsParser.route(fromHref: "index.php?r=documents/"), "documents")
        // Percent-escapes are decoded and the route rebuilt, not re-encoded.
        XCTAssertEqual(
            W4DocumentsParser.route(fromHref: "index.php?r=documents%2Findex&folder_id=27"),
            "documents/index&folder_id=27"
        )
        // A fragment is not part of the route.
        XCTAssertEqual(W4DocumentsParser.route(fromHref: "index.php?r=documents#top"), "documents")

        XCTAssertNil(W4DocumentsParser.route(fromHref: "https://w4.uwcrcn.no/"))
        XCTAssertNil(W4DocumentsParser.route(fromHref: "https://uwcrcn.managebac.com/login"))
        XCTAssertNil(W4DocumentsParser.route(fromHref: ""))
        XCTAssertNil(W4DocumentsParser.route(fromHref: "index.php?r="))
    }

    // MARK: - Degradation

    func testEmptyAndGarbageInputDegradeToAnEmptyListing() {
        XCTAssertEqual(W4DocumentsParser.parse(""), .empty)
        XCTAssertEqual(W4DocumentsParser.parse("not html at all <<<>>>"), .empty)
        XCTAssertEqual(W4DocumentsParser.parse("<html><body></body></html>"), .empty)
    }

    func testTitleFallsBackToTheDocumentTitle() {
        // `#content_inner` with no heading at all: the <title> is the last
        // honest source of a navigation title.
        let listing = W4DocumentsParser.parse("""
            <html><head><title>Documents</title></head>
            <body><div id="content_inner"><ul class="folder-list"></ul></div></body></html>
            """)

        XCTAssertEqual(listing.title, "Documents")
        XCTAssertTrue(listing.items.isEmpty)
        XCTAssertNil(listing.page, "an empty folder-list is still a folder — bug B16")
    }
}
