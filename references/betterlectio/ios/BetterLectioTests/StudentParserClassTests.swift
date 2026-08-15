import XCTest
@testable import BetterLectio

final class StudentParserClassTests: XCTestCase {
    func testParseStudentClassFromTitleNamedClass() {
        let html = #"<div id="s_m_HeaderContent_MainTitle">Eleven Thor Sakuragi Frigaard(k), BShannon - Skema</div>"#
        XCTAssertEqual(StudentParser.parseStudentClassFromTitle(from: html), "BShannon")
        XCTAssertEqual(StudentParser.parseStudentNameFromTitle(from: html), "Thor Sakuragi Frigaard")
    }

    func testParseStudentClassFromTitleDottedAndHyphenated() {
        let dotted = #"<div id="s_m_HeaderContent_MainTitle">Eleven Ada Lovelace, 10.st.kl.2 - Skema</div>"#
        XCTAssertEqual(StudentParser.parseStudentClassFromTitle(from: dotted), "10.st.kl.2")

        let hyphenated = #"<div id="s_m_HeaderContent_MainTitle">Eleven Ada Lovelace(k), 3hx-u - Forside</div>"#
        XCTAssertEqual(StudentParser.parseStudentClassFromTitle(from: hyphenated), "3hx-u")
    }

    func testParseCurrentStudentClassNamedClass() {
        let html = #"<div id="s_m_Content_Content_subHeaderDiv">Elev: Thor Sakuragi Frigaard (BShannon 17)</div>"#
        XCTAssertEqual(StudentParser.parseCurrentStudentClass(from: html), "BShannon")
    }
}
