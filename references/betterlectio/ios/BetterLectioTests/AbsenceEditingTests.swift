import Foundation
import XCTest
@testable import BetterLectio

final class AbsenceEditingTests: XCTestCase {
    func testParsesRegistrationIdSeparatelyFromActivityId() throws {
        let html = try fixture("registrations")

        let report = try StudentParser.parseAbsenceReport(from: html)
        let entry = try XCTUnwrap(report.missingReasons.first)
        XCTAssertEqual(entry.id, "999")
        XCTAssertEqual(entry.registrationId, "999")
        XCTAssertEqual(entry.activityId, "111")
    }

    func testParsesReasonOptionsAndConstructsPostback() throws {
        let html = try fixture("edit_form")

        let form = try AbsenceEditFormParser.parse(html)
        XCTAssertEqual(form.reasons.count, 5)
        XCTAssertEqual(form.selectedReasonValue, "Sygdom")
        XCTAssertEqual(form.note, "Gammel note")

        let body = try XCTUnwrap(AbsenceEditFormParser.postBody(
            form: form,
            reasonValue: "Private forhold",
            note: "Familie & læge"
        ))
        let encoded = try XCTUnwrap(String(data: body, encoding: .utf8))
        XCTAssertTrue(encoded.contains("__VIEWSTATE=state%2B%2F%3D"))
        XCTAssertTrue(encoded.contains("StudentReasonDD%24dd=Private%20forhold"))
        XCTAssertTrue(encoded.contains("cancelStudentNote%24tb=Familie%20%26%20l%C3%A6ge"))
        XCTAssertTrue(encoded.contains("__EVENTTARGET=s%24m%24Content%24Content%24savecancelapplyBtn%24svbtn"))
    }

    func testPreservesExistingReasonAndNote() throws {
        let html = try fixture("registrations")

        let entry = try XCTUnwrap(StudentParser.parseAbsenceReport(from: html).registrations.first)
        XCTAssertEqual(entry.reason, "Sygdom")
        XCTAssertEqual(entry.note, "Feber siden i går")
    }

    func testExtractsLectioValidationMessage() throws {
        let html = try fixture("update_rejected")
        XCTAssertEqual(try AbsenceEditFormParser.validationMessage(in: html), "Vælg en årsag")
    }

    func testAcceptsSuccessfulUpdateResponse() throws {
        try AbsenceEditFormParser.validateUpdateResponse(
            html: fixture("update_success"),
            finalURL: try XCTUnwrap(URL(string: "https://www.lectio.dk/lectio/94/subnav/fravaerelev_fravaersaarsager.aspx"))
        )
    }

    func testRejectsValidationResponse() throws {
        XCTAssertThrowsError(try AbsenceEditFormParser.validateUpdateResponse(
            html: fixture("update_rejected"),
            finalURL: try XCTUnwrap(URL(string: "https://www.lectio.dk/lectio/94/fravaer_aarsag.aspx?id=999"))
        )) { error in
            guard case LectioError.parsingError(let message) = error else {
                return XCTFail("Expected Lectio validation error, got \(error)")
            }
            XCTAssertEqual(message, "Vælg en årsag")
        }
    }

    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: Self.self)
        let url = bundle.url(forResource: name, withExtension: "html", subdirectory: "Fixtures/Absence")
            ?? bundle.url(forResource: name, withExtension: "html")
        return try String(contentsOf: XCTUnwrap(url), encoding: .utf8)
    }
}
