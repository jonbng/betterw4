//
//  W4HostGateTests.swift
//  BetterW4Tests
//
//  Large parts of the feature layer are still the BetterLectio originals and build lectio.dk
//  URLs. Until each one is ported, the HTTP client must refuse to send them: a stray request
//  would carry a W4 session cookie to an unrelated third party and hammer a server that cannot
//  answer it. These tests pin that guarantee down.
//

import XCTest
@testable import BetterW4

final class W4HostGateTests: XCTestCase {

    private let client = W4HTTPClient()

    func testW4HostIsAccepted() {
        XCTAssertTrue(W4Routes.isW4Host("w4.uwcrcn.no"))
        XCTAssertTrue(W4Routes.isW4Host("W4.UWCRCN.NO"), "Host matching must be case-insensitive")
    }

    func testForeignHostsAreRejected() {
        XCTAssertFalse(W4Routes.isW4Host("www.lectio.dk"))
        XCTAssertFalse(W4Routes.isW4Host("lectio.dk"))
        XCTAssertFalse(W4Routes.isW4Host("uwcrcn.no"), "The public site is not the SIS host")
        XCTAssertFalse(W4Routes.isW4Host(nil))
        XCTAssertFalse(W4Routes.isW4Host(""))
        // Suffix matching must not be fooled by a lookalike domain.
        XCTAssertFalse(W4Routes.isW4Host("w4.uwcrcn.no.evil.example"))
    }

    /// The important one: an un-ported Lectio URL must throw before any network call.
    func testRequestToLectioIsRefusedBeforeItLeavesTheDevice() async {
        let lectioURL = URL(string: "https://www.lectio.dk/lectio/0/SkemaNy.aspx?elevid=nc26abcd")!

        do {
            _ = try await client.performRequest(
                url: lectioURL,
                credentials: W4Credentials(sessionId: "session-that-must-not-be-sent"),
                studentId: nil,
                contextForLogging: "schedule (not ported)"
            )
            XCTFail("A lectio.dk request was allowed through the host gate")
        } catch let error as W4Error {
            guard case .notPortedToW4(let host, _) = error else {
                return XCTFail("Expected .notPortedToW4, got \(error)")
            }
            XCTAssertEqual(host, "www.lectio.dk")
        } catch {
            XCTFail("Expected W4Error.notPortedToW4, got \(error)")
        }
    }

    func testHostGateHelperAcceptsW4URLs() {
        XCTAssertNoThrow(
            try W4HTTPClient.requireW4Host(W4Routes.url(W4Routes.R.home), context: "home")
        )
    }
}
