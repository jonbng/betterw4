import XCTest
@testable import BetterLectio

@MainActor
final class ReferralTests: XCTestCase {
    func testProgressClampsAndUnlocksAtThree() {
        XCTAssertEqual(ReferralProgress(conversions: -1).current, 0)
        XCTAssertEqual(ReferralProgress(conversions: 2).remaining, 1)
        XCTAssertTrue(ReferralProgress(conversions: 3).unlocked)
        XCTAssertEqual(ReferralProgress(conversions: 8).current, 3)
    }

    func testReferralURLOnlyAcceptsCanonicalHTTPSHost() throws {
        let token = UUID()
        let valid = try XCTUnwrap(URL(string: "https://betterlectio.dk/r/12345?bl_ref=\(token.uuidString)"))
        XCTAssertEqual(ReferralLink.parse(valid)?.studentID, "12345")
        XCTAssertEqual(ReferralLink.parse(valid)?.token, token)
        XCTAssertNil(ReferralLink.parse(URL(string: "https://betterlectio.dk.evil.example/r/12345")!))
        XCTAssertNil(ReferralLink.parse(URL(string: "http://betterlectio.dk/r/12345")!))
    }

    func testPendingReferralUsesFirstValidTokenAndExpires() {
        let suiteName = "ReferralTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ReferralStore(defaults: defaults)
        let first = UUID()
        let second = UUID()
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertTrue(store.saveFirstPending(token: first, now: now))
        XCTAssertFalse(store.saveFirstPending(token: second, now: now.addingTimeInterval(5)))
        XCTAssertEqual(store.pending(now: now.addingTimeInterval(10))?.token, first)
        XCTAssertNil(store.pending(now: now.addingTimeInterval(ReferralStore.pendingLifetime + 1)))
    }

    func testReferralStatsDecodesRPCShape() throws {
        let data = #"{"total_clicks":7,"unique_clickers":4,"conversions":2,"recent_referrals":[{"student_id":"42","name":"Sofie","attributed_at":"2026-08-01T10:00:00Z"}]}"#.data(using: .utf8)!
        let stats = try JSONDecoder().decode(ReferralStats.self, from: data)
        XCTAssertEqual(stats.totalClicks, 7)
        XCTAssertEqual(stats.conversions, 2)
        XCTAssertEqual(stats.recentReferrals.first?.name, "Sofie")
    }

    func testCachedStatsNeverCrossStudentAccounts() async {
        let suiteName = "ReferralCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let coordinator = ReferralCoordinator(store: ReferralStore(defaults: defaults))
        _ = await coordinator.refreshStats(for: .demo)
        XCTAssertNotNil(coordinator.cachedStats(for: .demo))

        let other = Student(
            studentId: "another-student",
            gymId: 94,
            name: "Other",
            pictureId: nil,
            classLabel: nil,
            schoolName: nil
        )
        XCTAssertNil(coordinator.cachedStats(for: other))
        coordinator.activate(for: other)
        XCTAssertNil(coordinator.cachedStats(for: .demo))
    }
}
