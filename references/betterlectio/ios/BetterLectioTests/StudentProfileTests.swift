import XCTest
@testable import BetterLectio

final class StudentProfileTests: XCTestCase {
    func testHiddenBirthdayIsNeverFormatted() throws {
        let profile = try decodeProfile(birthdate: "2008-05-12", showBirthday: false)
        XCTAssertNil(profile.formattedBirthday)
    }

    func testVisibleBirthdayUsesDanishFormat() throws {
        let profile = try decodeProfile(birthdate: "2008-05-12", showBirthday: true)
        XCTAssertEqual(profile.formattedBirthday, "12. maj 2008")
    }

    func testInstagramAllowsHandleAndInstagramURL() {
        XCTAssertEqual(InstagramProfileLink.handle(from: "@betterlectio"), "betterlectio")
        XCTAssertEqual(
            InstagramProfileLink.handle(from: "https://www.instagram.com/betterlectio/"),
            "betterlectio"
        )
    }

    func testInstagramRejectsNonInstagramAndMalformedURLs() {
        XCTAssertNil(InstagramProfileLink.url(for: "https://instagram.com.evil.example/betterlectio"))
        XCTAssertNil(InstagramProfileLink.url(for: "instagram.com/betterlectio/extra"))
        XCTAssertNil(InstagramProfileLink.url(for: "person?redirect=evil"))
    }

    func testMembershipUsesRecentHeartbeat() throws {
        let profile = try decodeProfile(
            extraJSON: #""last_seen_at": "2026-08-01T12:00:00Z""#
        )
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-02T12:00:00Z"))
        XCTAssertTrue(profile.hasBetterLectio(at: now))
    }

    func testMembershipExpiresAfterFourteenDays() throws {
        let profile = try decodeProfile(
            extraJSON: #""last_seen_at": "2026-07-01T12:00:00Z""#
        )
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-02T12:00:00Z"))
        XCTAssertFalse(profile.hasBetterLectio(at: now))
    }

    func testUninstalledExtensionIsInactive() throws {
        let profile = try decodeProfile(
            extraJSON: """
            "last_seen_at": "2026-08-02T11:00:00Z",
            "extension_uninstalled_at": "2026-08-02T11:30:00Z"
            """
        )
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-02T12:00:00Z"))
        XCTAssertFalse(profile.hasBetterLectio(at: now))
    }

    func testAppInstallationKeepsMembershipActive() throws {
        let profile = try decodeProfile(
            extraJSON: #""app_installed_at": "2025-01-01T12:00:00Z""#
        )
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-02T12:00:00Z"))
        XCTAssertTrue(profile.hasBetterLectio(at: now))
    }

    func testPublicImageURLsRequireHTTPSWithoutEmbeddedCredentials() {
        XCTAssertTrue(PublicProfileImageLoader.isAllowed(URL(string: "https://cdn.example/avatar.jpg")!))
        XCTAssertFalse(PublicProfileImageLoader.isAllowed(URL(string: "http://cdn.example/avatar.jpg")!))
        XCTAssertFalse(PublicProfileImageLoader.isAllowed(URL(string: "https://user:pass@cdn.example/avatar.jpg")!))
    }

    func testLectioLoaderOnlyAcceptsLectioHosts() {
        XCTAssertTrue(LectioImageLoader.isLectioURL(URL(string: "https://www.lectio.dk/lectio/94/GetImage.aspx")!))
        XCTAssertFalse(LectioImageLoader.isLectioURL(URL(string: "https://lectio.dk.evil.example/avatar.jpg")!))
        XCTAssertFalse(LectioImageLoader.isLectioURL(URL(string: "https://cdn.example/avatar.jpg")!))
    }

    private func decodeProfile(birthdate: String, showBirthday: Bool) throws -> StudentProfile {
        let json = """
        {
          "id": "123",
          "birthdate": "\(birthdate)",
          "show_birthday": \(showBirthday),
          "app_installed_at": "2026-08-01T12:00:00Z"
        }
        """.data(using: .utf8)!
        return try JSONDecoder().decode(StudentProfile.self, from: json)
    }

    private func decodeProfile(extraJSON: String) throws -> StudentProfile {
        let json = """
        {
          "id": "123",
          \(extraJSON)
        }
        """.data(using: .utf8)!
        return try JSONDecoder().decode(StudentProfile.self, from: json)
    }
}
