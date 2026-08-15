import XCTest
@testable import BetterLectio

final class GradeParserTests: XCTestCase {
    func testParsesColumnsFromLiveHeaderInServerOrder() throws {
        let report = try GradeParser.parseGradesReport(from: gradeTable(
            headers: ["Eksamenskarakter", "1. standpunkt", "Projektkarakter"],
            values: ["12", "7", "10"]
        ))

        XCTAssertEqual(report.columns.map(\.key), [
            "eksamenskarakter",
            "1.standpunkt",
            "projektkarakter"
        ])
        XCTAssertEqual(report.columns.map(\.label), [
            "Eksamenskarakter",
            "1. standpunkt",
            "Projektkarakter"
        ])

        let entry = try XCTUnwrap(report.grades.first)
        XCTAssertEqual(entry.cell(for: "eksamenskarakter")?.value, "12")
        XCTAssertEqual(entry.cell(for: "1.standpunkt")?.value, "7")
        XCTAssertEqual(entry.cell(for: "projektkarakter")?.value, "10")
    }

    func testMissingKnownColumnsDoNotShiftValues() throws {
        let report = try GradeParser.parseGradesReport(from: gradeTable(
            headers: ["2. standpunkt", "Årskarakter"],
            values: ["4", "10"]
        ))

        XCTAssertEqual(report.columns.map(\.key), ["2.standpunkt", "årskarakter"])
        let entry = try XCTUnwrap(report.grades.first)
        XCTAssertEqual(entry.cell(for: "2.standpunkt")?.value, "4")
        XCTAssertEqual(entry.cell(for: "årskarakter")?.value, "10")
        XCTAssertNil(entry.cell(for: "1.standpunkt"))
    }

    func testPreservesCellMetadataForDynamicColumn() throws {
        let report = try GradeParser.parseGradesReport(from: """
        <table id="s_m_Content_Content_karakterView_KarakterGV">
          <tr>
            <th class="OnlyDesktop">Hold</th>
            <th class="OnlyDesktop">Fag</th>
            <th class="OnlyDesktop">3. standpunkt</th>
          </tr>
          <tr>
            <td class="OnlyDesktop"><span data-lectiocontextcard="HE123">3x MA</span></td>
            <td class="OnlyDesktop">Matematik A</td>
            <td class="OnlyDesktop"><div title="XPRSFag: 4682C Matematik\nKilde: Karakter\nVægt: 1,5">10</div></td>
          </tr>
        </table>
        """)

        let cell = try XCTUnwrap(report.grades.first?.cell(for: "3.standpunkt"))
        XCTAssertEqual(cell.value, "10")
        XCTAssertEqual(cell.weight, 1.5)
        XCTAssertEqual(cell.source, "Karakter")
        XCTAssertEqual(cell.xprsSubject, "4682C Matematik")
    }

    func testDuplicateCanonicalHeadersReceiveUniqueKeys() throws {
        let report = try GradeParser.parseGradesReport(from: gradeTable(
            headers: ["Intern prøve", "Intern karakter"],
            values: ["7", "10"]
        ))

        XCTAssertEqual(report.columns.map(\.key), ["intern prøve", "intern prøve-2"])
        let entry = try XCTUnwrap(report.grades.first)
        XCTAssertEqual(entry.cell(for: "intern prøve")?.value, "7")
        XCTAssertEqual(entry.cell(for: "intern prøve-2")?.value, "10")
    }

    private func gradeTable(headers: [String], values: [String]) -> String {
        let headerCells = headers.map { #"<th class="OnlyDesktop">\#($0)</th>"# }.joined()
        let valueCells = values.map { #"<td class="OnlyDesktop">\#($0)</td>"# }.joined()
        return """
        <table id="s_m_Content_Content_karakterView_KarakterGV">
          <tr>
            <th class="OnlyDesktop">Hold</th>
            <th class="OnlyDesktop">Fag</th>
            \(headerCells)
          </tr>
          <tr>
            <td class="OnlyDesktop"><span data-lectiocontextcard="HE123">1x MA</span></td>
            <td class="OnlyDesktop">Matematik A</td>
            \(valueCells)
          </tr>
        </table>
        """
    }
}
