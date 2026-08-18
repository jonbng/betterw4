//
//  W4CampusStatusParserTests.swift
//  BetterW4Tests
//
//  Tests for W4CampusStatusParser + CampusModels (Wave 4 item 4.5).
//
//  EVIDENCE MAP — read this before adding an assertion.
//
//    [V] home.html and documents.html are REAL captures of https://w4.uwcrcn.no
//        (sanitized: identities replaced). The campus control is part of the
//        chrome of EVERY authenticated page, so both captures carry the whole
//        widget: `div.status-dropdown > div.status.oncampus > .status-value`
//        reading "on campus", an empty `div.location`, the eleven
//        `span#location input[type=radio]` options with their `label[for=…]`
//        texts, and `input#other[maxlength=20]`.
//
//    [I] Every OFF-campus state, every "no radios" page and every free-text
//        POST in this file is SYNTHESIZED. Nobody has ever captured this
//        student off campus, so those tests verify THE PARSER, not W4.
//        They are marked [I] individually.
//
//  The load-bearing test in this file is
//  `testOnCampusPostsStatusOnAndNoLocationKey` — plan D-12 / bug B6.
//

import XCTest
@testable import BetterW4

final class W4CampusStatusParserTests: XCTestCase {

    // MARK: - Fixtures

    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: type(of: self))
        if let url = bundle.url(forResource: name, withExtension: "html", subdirectory: "Fixtures/W4")
            ?? bundle.url(forResource: name, withExtension: "html") {
            return try String(contentsOf: url, encoding: .utf8)
        }
        // Last resort: the checked-in source file, so a resource-copy hiccup
        // cannot quietly turn a real-capture assertion into a skip.
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/W4/\(name).html")
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw XCTSkip("Fixture \(name).html is not in the test bundle")
        }
        return try String(contentsOf: source, encoding: .utf8)
    }

    private func capturedStatus() throws -> CampusStatus {
        try XCTUnwrap(
            W4CampusStatusParser.parse(try fixture("home")),
            "the real Home capture carries the campus chrome"
        )
    }

    // MARK: - [V] The real capture

    func testCapturedHomePageReadsOnCampus() throws {
        let status = try capturedStatus()

        // `div.status.oncampus` + `.status-value` == "on campus".
        XCTAssertTrue(status.isOnCampus)
        // `div.location` is rendered EMPTY while on campus, so the model must
        // not carry a stale string.
        XCTAssertNil(status.location)
        XCTAssertEqual(status.label, "On campus")
    }

    func testCapturedHomePageYieldsElevenOptionsWithSeparateValueAndLabel() throws {
        let status = try capturedStatus()

        XCTAssertEqual(status.options.count, 11)
        XCTAssertEqual(status.options.map(\.id), (0...10).map { "location_\($0)" })

        // The POST values, verbatim from `span#location input[value=…]`.
        XCTAssertEqual(status.options.map(\.value), [
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

        // The human labels, verbatim from `label[for=location_n]`.
        XCTAssertEqual(status.options.first?.label, "On campus")
        XCTAssertEqual(status.options.last?.label, "Other")
        XCTAssertEqual(status.options.first { $0.id == "location_2" }?.label, "At Raudbua")

        // Bug B6 in one line: for two of the eleven options the value and the
        // label are DIFFERENT strings, so a parser that keeps only the label
        // (as the Kotlin port does) posts nonsense for both.
        let firstOption = try XCTUnwrap(status.options.first)
        let lastOption = try XCTUnwrap(status.options.last)
        XCTAssertNotEqual(firstOption.value, firstOption.label)
        XCTAssertNotEqual(lastOption.value, lastOption.label)
        // The other nine really are identical in the capture; that is why the
        // Kotlin bug went unnoticed for so long.
        for option in status.options.dropFirst().dropLast() {
            XCTAssertEqual(option.value, option.label, option.id)
        }
    }

    func testCapturedHomePageMarksTheOnCampusRadioAsChecked() throws {
        let status = try capturedStatus()

        XCTAssertEqual(status.selectedOptionID, "location_0")
        let selected = try XCTUnwrap(status.selectedOption)
        XCTAssertTrue(selected.isOnCampus)
        XCTAssertEqual(selected.value, CampusLocationOption.onCampusValue)

        let freeText = try XCTUnwrap(status.freeTextOption)
        XCTAssertTrue(freeText.isFreeText)
        XCTAssertEqual(freeText.id, "location_10")
    }

    /// The widget is page chrome, not a Home feature: it has to parse off any
    /// authenticated page. `documents.html` is a real capture of `?r=documents`.
    func testCapturedDocumentsPageCarriesTheSameWidget() throws {
        let status = try XCTUnwrap(W4CampusStatusParser.parse(try fixture("documents")))

        XCTAssertTrue(status.isOnCampus)
        XCTAssertNil(status.location)
        XCTAssertEqual(status.options.count, 11)
        XCTAssertEqual(status.selectedOptionID, "location_0")
    }

    func testParsedOptionsMatchTheHardcodedFallbackList() throws {
        // `CampusStatus.defaultOptions` claims to be the eleven captured
        // options verbatim. If the capture and the fallback ever drift apart,
        // that claim is a lie — so prove it here.
        let status = try capturedStatus()
        XCTAssertEqual(status.options, CampusStatus.defaultOptions)
    }

    // MARK: - [V] Writing: the setstatus body (plan D-12, bug B6)

    /// THE load-bearing assertion of item 4.5.
    ///
    /// `campusstatusdropdown.js` posts `status=on` and nothing else when the
    /// student is on campus. Sending `location=oncampus`, or `location=On
    /// campus` (the label — bug B6), is a different request.
    func testOnCampusPostsStatusOnAndNoLocationKey() throws {
        let status = try capturedStatus()
        let onCampus = try XCTUnwrap(status.onCampusOption)

        let body = try XCTUnwrap(W4CampusStatusParser.setStatusBody(option: onCampus))

        XCTAssertEqual(body, ["status": "on"])
        XCTAssertEqual(body.count, 1, "exactly one key")
        XCTAssertNil(body["location"], "bug B6 / plan D-12: On campus posts NO location key at all")
        XCTAssertNotEqual(body["location"], onCampus.label)
        XCTAssertNotEqual(body["location"], onCampus.value)
    }

    func testCapturedLocationOptionPostsItsValueNotItsLabel() throws {
        let status = try capturedStatus()
        let raudbua = try XCTUnwrap(status.options.first { $0.id == "location_2" })

        let body = try XCTUnwrap(W4CampusStatusParser.setStatusBody(option: raudbua))
        XCTAssertEqual(body, ["status": "off", "location": "At Raudbua"])
        XCTAssertEqual(body["location"], raudbua.value)
    }

    /// A captured value that is far longer than `input#other`'s 20-character
    /// cap. The cap belongs to the free-text field only, so it must not be
    /// applied to a radio value.
    func testLongCapturedOptionValueIsNotTruncated() throws {
        let status = try capturedStatus()
        let library = try XCTUnwrap(status.options.first { $0.id == "location_9" })
        XCTAssertGreaterThan(library.value.count, CampusStatus.freeTextMaxLength)

        let body = try XCTUnwrap(W4CampusStatusParser.setStatusBody(option: library))
        XCTAssertEqual(body["location"], "In Library/Study room (after 10:30pm)")
    }

    /// **[I]** No free-text status has ever been captured. This verifies the
    /// parser's contract (`#other` text is posted as `location`), which is
    /// what `campusstatusdropdown.js:12-15` reads off the DOM.
    func testFreeTextOptionPostsTheTypedText() throws {
        let status = try capturedStatus()
        let other = try XCTUnwrap(status.freeTextOption)

        let body = try XCTUnwrap(
            W4CampusStatusParser.setStatusBody(option: other, freeText: "  At the fjord  ")
        )
        XCTAssertEqual(body, ["status": "off", "location": "At the fjord"])
        XCTAssertNotEqual(body["location"], other.value, "'other' is a sentinel, never a location")
        XCTAssertNotEqual(body["location"], other.label)
    }

    /// **[I]** `input#other[maxlength=20]` is [V]; enforcing it before the POST
    /// is the parser's own rule.
    func testFreeTextIsCappedAtTwentyCharacters() throws {
        let status = try capturedStatus()
        let other = try XCTUnwrap(status.freeTextOption)
        let typed = "In the sauna behind the sports hall"
        XCTAssertGreaterThan(typed.count, CampusStatus.freeTextMaxLength)

        let body = try XCTUnwrap(W4CampusStatusParser.setStatusBody(option: other, freeText: typed))
        let location = try XCTUnwrap(body["location"])
        XCTAssertEqual(location.count, CampusStatus.freeTextMaxLength)
        XCTAssertEqual(location, String(typed.prefix(CampusStatus.freeTextMaxLength)))
    }

    /// **[I]** `campusstatusdropdown.js` refuses to post an empty free text.
    /// `nil` here means "ask the student", not "post an empty location".
    func testFreeTextOptionWithoutTextRefusesToBuildABody() throws {
        let status = try capturedStatus()
        let other = try XCTUnwrap(status.freeTextOption)

        XCTAssertNil(W4CampusStatusParser.setStatusBody(option: other))
        XCTAssertNil(W4CampusStatusParser.setStatusBody(option: other, freeText: ""))
        XCTAssertNil(W4CampusStatusParser.setStatusBody(option: other, freeText: "   \n "))
    }

    func testRawStateBodyMatchesTheOptionBody() {
        XCTAssertEqual(W4CampusStatusParser.setStatusBody(onCampus: true, location: nil), ["status": "on"])
        // On campus wins: a stale location must never leak into the body.
        XCTAssertEqual(
            W4CampusStatusParser.setStatusBody(onCampus: true, location: "At Raudbua"),
            ["status": "on"]
        )
        XCTAssertEqual(
            W4CampusStatusParser.setStatusBody(onCampus: false, location: "  In Dale  "),
            ["status": "off", "location": "In Dale"]
        )
        // Off campus with nowhere to say: still a valid body, just no location.
        XCTAssertEqual(W4CampusStatusParser.setStatusBody(onCampus: false, location: nil), ["status": "off"])
        XCTAssertEqual(W4CampusStatusParser.setStatusBody(onCampus: false, location: "  "), ["status": "off"])
    }

    func testSetStatusRouteIsTheOneThePagePublishes() {
        // `var status_urls = {'set':'/index.php?r=site/setstatus'}` [V].
        XCTAssertEqual(W4CampusStatusParser.setStatusRoute, "site/setstatus")
        XCTAssertEqual(W4CampusStatusParser.setStatusRoute, W4Routes.R.setStatus)
    }

    // MARK: - [V] Bug B7 — the parenthesised location

    /// `campusstatusdropdown.js:28` writes `'(' + location + ')'` into
    /// `div.location` after a successful POST, so a page rendered after a
    /// client-side update shows `(At Raudbua)`. Exactly one wrapping pair is
    /// stripped, and only when it really is a pair.
    func testNormalizedLocationStripsOneWrappingParenthesisPair() {
        XCTAssertEqual(W4CampusStatusParser.normalizedLocation("(At Raudbua)"), "At Raudbua")
        XCTAssertEqual(W4CampusStatusParser.normalizedLocation("  (In Dale)  "), "In Dale")
        XCTAssertEqual(W4CampusStatusParser.normalizedLocation("At Raudbua"), "At Raudbua")

        // A captured option value that legitimately ENDS in ')' must survive.
        XCTAssertEqual(
            W4CampusStatusParser.normalizedLocation("In A building (after 10:30pm)"),
            "In A building (after 10:30pm)"
        )
        // The leading '(' must actually be the partner of the trailing ')'.
        XCTAssertEqual(W4CampusStatusParser.normalizedLocation("(A) and (B)"), "(A) and (B)")
        XCTAssertEqual(W4CampusStatusParser.normalizedLocation("(unbalanced"), "(unbalanced")
        XCTAssertEqual(W4CampusStatusParser.normalizedLocation("((nested))"), "(nested)")

        XCTAssertNil(W4CampusStatusParser.normalizedLocation(nil))
        XCTAssertNil(W4CampusStatusParser.normalizedLocation(""))
        XCTAssertNil(W4CampusStatusParser.normalizedLocation("   "))
        XCTAssertNil(W4CampusStatusParser.normalizedLocation("()"))
    }

    // MARK: - [I] SYNTHESIZED — verifies the parser, not W4

    /// **[I]** Nobody has captured this student off campus. The markup below
    /// mirrors the captured on-campus shape with the state class flipped and
    /// the `div.location` filled the way `campusstatusdropdown.js` fills it.
    func testSynthesizedOffCampusStateReadsTheLocation() throws {
        let html = Self.chrome(
            statusClass: "offcampus",
            statusValue: "off campus",
            location: "(At Raudbua)",
            checkedIndex: 2
        )
        let status = try XCTUnwrap(W4CampusStatusParser.parse(html))

        XCTAssertFalse(status.isOnCampus)
        XCTAssertEqual(status.location, "At Raudbua", "bug B7: one wrapping pair stripped")
        XCTAssertEqual(status.label, "At Raudbua")
        XCTAssertEqual(status.selectedOptionID, "location_2")
        XCTAssertEqual(status.selectedOption?.value, "At Raudbua")
    }

    /// **[I]** With no state classes at all the checked radio is the only
    /// evidence left, and the parser must use it rather than defaulting.
    func testSynthesizedPageWithoutStateClassesFallsBackToTheCheckedRadio() throws {
        let html = """
            <html><body>
            <span id="location">
              <input value="oncampus" id="location_0" type="radio" name="location">
              <label for="location_0">On campus</label>
              <input value="In Flekke" id="location_5" checked="checked" type="radio" name="location">
              <label for="location_5">In Flekke</label>
            </span>
            </body></html>
            """
        let status = try XCTUnwrap(W4CampusStatusParser.parse(html))

        XCTAssertFalse(status.isOnCampus)
        XCTAssertEqual(status.options.count, 2)
        XCTAssertEqual(status.selectedOptionID, "location_5")
        XCTAssertNil(status.location, "there is no div.location on this page")
    }

    /// **[I]** `.status-value` text is the third rung of the state ladder,
    /// below the `oncampus` / `offcampus` classes.
    func testSynthesizedStatusValueTextIsUsedWhenTheClassIsMissing() throws {
        let html = """
            <html><body>
            <div class="status-dropdown">
              <div class="status">
                <div class="status-value">off campus</div>
                <div class="location">(On a walk)</div>
              </div>
            </div>
            </body></html>
            """
        let status = try XCTUnwrap(W4CampusStatusParser.parse(html))

        XCTAssertFalse(status.isOnCampus)
        XCTAssertEqual(status.location, "On a walk")
        // No radios on this page, so the eleven captured options stand in and
        // the selection is honestly reported as unknown.
        XCTAssertEqual(status.options, CampusStatus.defaultOptions)
        XCTAssertNil(status.selectedOptionID)
    }

    /// **[I]** A radio with no `value` cannot be posted, so it must not be
    /// offered to the student.
    func testSynthesizedValuelessRadioIsDropped() throws {
        let html = """
            <html><body>
            <span id="location">
              <input value="" id="location_0" type="radio" name="location">
              <label for="location_0">Nowhere</label>
              <input value="In Dale" id="location_1" checked="checked" type="radio" name="location">
              <label for="location_1">In Dale</label>
            </span>
            </body></html>
            """
        let status = try XCTUnwrap(W4CampusStatusParser.parse(html))

        XCTAssertEqual(status.options.count, 1)
        XCTAssertEqual(status.options.first?.value, "In Dale")
        XCTAssertEqual(status.selectedOptionID, "location_1")
    }

    /// **[I]** An unlabelled radio still has to be shown; the value is the
    /// honest fallback, and the two sentinels get their captured wording.
    func testSynthesizedUnlabelledRadiosFallBackToTheirValue() throws {
        let html = """
            <html><body>
            <span id="location">
              <input value="oncampus" id="location_0" checked="checked" type="radio" name="location">
              <input value="On a walk" id="location_1" type="radio" name="location">
              <input value="other" id="location_2" type="radio" name="location">
            </span>
            </body></html>
            """
        let status = try XCTUnwrap(W4CampusStatusParser.parse(html))

        XCTAssertEqual(status.options.map(\.label), ["On campus", "On a walk", "Other"])
        XCTAssertEqual(status.options.map(\.value), ["oncampus", "On a walk", "other"])
    }

    // MARK: - Degradation

    func testPagesWithoutTheCampusChromeReturnNil() {
        XCTAssertNil(W4CampusStatusParser.parse(""))
        XCTAssertNil(W4CampusStatusParser.parse("<html><body><p>nope</p></body></html>"))
        XCTAssertNil(W4CampusStatusParser.parse("not html at all <<<>>>"))
    }

    func testGarbageInputNeverCrashes() {
        // Truncated markup and a valueless option. The point is only that these
        // return at all: the parser never throws, force-unwraps or subscripts.
        _ = W4CampusStatusParser.parse("<div class=\"status-dropdown\">")
        _ = W4CampusStatusParser.parse("<span id=\"location\"><input type=\"radio\"></span>")
        _ = W4CampusStatusParser.setStatusBody(
            option: CampusLocationOption(id: "x", value: "", label: ""),
            freeText: nil
        )
    }

    /// A radio-less page still has to offer something to tap, so the eleven
    /// captured options stand in.
    func testWidgetWithoutRadiosFallsBackToTheCapturedOptionList() throws {
        let html = """
            <html><body>
            <div class="status-dropdown">
              <div class="status oncampus"><div class="status-value">on campus</div></div>
            </div>
            </body></html>
            """
        let status = try XCTUnwrap(W4CampusStatusParser.parse(html))

        XCTAssertTrue(status.isOnCampus)
        XCTAssertEqual(status.options.count, 11)
        XCTAssertEqual(status.options, CampusStatus.defaultOptions)
        XCTAssertNil(status.selectedOptionID, "nothing was parsed, so nothing is reported as selected")
    }

    // MARK: - Synthesized chrome builder

    /// **[I]** Mirrors the captured widget's structure with the state made
    /// variable. Only the eleven captured values are used, so the option list
    /// stays honest even though the STATE is invented.
    private static func chrome(
        statusClass: String,
        statusValue: String,
        location: String,
        checkedIndex: Int
    ) -> String {
        var radios = ""
        for (index, option) in CampusStatus.defaultOptions.enumerated() {
            let checked = index == checkedIndex ? " checked=\"checked\"" : ""
            radios += """
                <input value="\(option.value)" id="location_\(index)"\(checked) type="radio" name="location">
                <label for="location_\(index)">\(option.label)</label><br>
                """
        }
        return """
            <html><body>
            <div id="header">
              <div class="status-dropdown">
                <div class="status \(statusClass)">
                  <div class="status-value">\(statusValue)</div>
                  <div class="location">\(location)</div>
                </div>
              </div>
              <div class="selection-box">
                <p>I am currently:</p>
                <span id="location">\(radios)</span>
                <input maxlength="20" type="text" value="" name="other" id="other">
                <div class="buttons">
                  <input id="submit-campus-status" name="yt0" type="button" value="Set status">
                </div>
              </div>
            </div>
            </body></html>
            """
    }
}
