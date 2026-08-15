import XCTest
@testable import BetterLectio

@MainActor
final class ProfilePictureTests: XCTestCase {
    func testStateDecodesPendingSubmission() throws {
        let data = #"{"unlocked":true,"referralConversions":3,"unlockThreshold":3,"currentUrl":"https://cdn.example/current.jpg","approvedAt":null,"nextEligibleAt":null,"canSubmit":false,"submission":{"id":"abc","status":"pending","createdAt":"2026-08-02T00:00:00Z","submittedAt":"2026-08-02T00:00:01Z","reviewedAt":null,"rejectionReason":null,"reviewNote":null,"approvedUrl":null}}"#.data(using: .utf8)!
        let state = try JSONDecoder().decode(ProfilePictureState.self, from: data)
        XCTAssertTrue(state.unlocked)
        XCTAssertTrue(state.isPending)
        XCTAssertFalse(state.canSubmit)
    }

    func testRejectedStatePreservesModeratorDetails() throws {
        let data = #"{"unlocked":true,"referralConversions":3,"unlockThreshold":3,"currentUrl":null,"approvedAt":null,"nextEligibleAt":null,"canSubmit":true,"submission":{"id":"abc","status":"rejected","createdAt":"2026-08-02T00:00:00Z","submittedAt":null,"reviewedAt":"2026-08-02T01:00:00Z","rejectionReason":"unsuitable","reviewNote":"Vælg et tydeligt portræt","approvedUrl":null}}"#.data(using: .utf8)!
        let state = try JSONDecoder().decode(ProfilePictureState.self, from: data)
        XCTAssertTrue(state.wasRejected)
        XCTAssertEqual(state.submission?.reviewNote, "Vælg et tydeligt portræt")
    }

    func testCooldownAndApprovedStateDecode() throws {
        let data = #"{"unlocked":true,"referralConversions":4,"unlockThreshold":3,"currentUrl":"https://cdn.example/approved.jpg","approvedAt":"2026-08-02T01:00:00Z","nextEligibleAt":"2026-11-02T01:00:00Z","canSubmit":false,"submission":{"id":"abc","status":"approved","createdAt":"2026-08-01T00:00:00Z","submittedAt":"2026-08-01T00:00:01Z","reviewedAt":"2026-08-02T01:00:00Z","rejectionReason":null,"reviewNote":null,"approvedUrl":"https://cdn.example/approved.jpg"}}"#.data(using: .utf8)!
        let state = try JSONDecoder().decode(ProfilePictureState.self, from: data)

        XCTAssertTrue(state.unlocked)
        XCTAssertFalse(state.canSubmit)
        XCTAssertEqual(state.nextEligibleAt, "2026-11-02T01:00:00Z")
        XCTAssertEqual(state.currentImageURL?.absoluteString, "https://cdn.example/approved.jpg")
    }

    func testLockedStateCannotChoose() throws {
        let data = #"{"unlocked":false,"referralConversions":1,"unlockThreshold":3,"currentUrl":null,"approvedAt":null,"nextEligibleAt":null,"canSubmit":false,"submission":null}"#.data(using: .utf8)!
        let state = try JSONDecoder().decode(ProfilePictureState.self, from: data)
        let service = ProfilePictureServiceStub(states: [state])
        let viewModel = ProfilePictureEditorViewModel(student: .demo, service: service)

        viewModel.state = state

        XCTAssertFalse(viewModel.canChoose)
    }

    func testPayloadValidationAcceptsSupportedMagicBytes() throws {
        try ProfilePictureValidator.validate(picture(bytes: [0xff, 0xd8, 0xff, 0x00], mime: "image/jpeg", ext: "jpg"))
        try ProfilePictureValidator.validate(picture(bytes: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a], mime: "image/png", ext: "png"))
        try ProfilePictureValidator.validate(picture(bytes: Array("RIFF0000WEBP".utf8), mime: "image/webp", ext: "webp"))
    }

    func testPayloadValidationRejectsEmptyOversizeUnsupportedAndMismatchedData() {
        XCTAssertThrowsError(try ProfilePictureValidator.validate(picture(bytes: [], mime: "image/jpeg", ext: "jpg")))
        XCTAssertThrowsError(try ProfilePictureValidator.validate(PreparedProfilePicture(
            data: Data(repeating: 0xff, count: ProfilePictureValidator.maximumBytes + 1),
            mimeType: "image/jpeg",
            fileExtension: "jpg"
        )))
        XCTAssertThrowsError(try ProfilePictureValidator.validate(picture(bytes: [0xff, 0xd8, 0xff], mime: "image/gif", ext: "gif")))
        XCTAssertThrowsError(try ProfilePictureValidator.validate(picture(bytes: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a], mime: "image/jpeg", ext: "jpg")))
    }

    func testPayloadValidationAcceptsExactFiveMegabyteBoundary() throws {
        var data = Data([0xff, 0xd8, 0xff])
        data.append(Data(repeating: 0, count: ProfilePictureValidator.maximumBytes - data.count))

        try ProfilePictureValidator.validate(PreparedProfilePicture(
            data: data,
            mimeType: "image/jpeg",
            fileExtension: "jpg"
        ))
    }

    func testAvatarFallbackOrderPrefersCustomThenLectioThenProvidedFallback() {
        let fallback = URL(string: "https://www.lectio.dk/fallback.jpg")!
        let custom = StudentProfile(id: "1", customProfilePictureURL: "https://cdn.example/custom.jpg", lectioProfilePictureURL: "https://cdn.example/lectio.jpg")
        let lectio = StudentProfile(id: "1", lectioProfilePictureURL: "https://cdn.example/lectio.jpg")
        let empty = StudentProfile(id: "1")

        XCTAssertEqual(custom.pictureURL(fallback: fallback)?.absoluteString, "https://cdn.example/custom.jpg")
        XCTAssertEqual(lectio.pictureURL(fallback: fallback)?.absoluteString, "https://cdn.example/lectio.jpg")
        XCTAssertEqual(empty.pictureURL(fallback: fallback), fallback)
    }

    func testReviewMonitorPublishesApprovedTransition() async throws {
        let suite = "ProfilePictureTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let pending = state(status: "pending", currentURL: nil)
        let approved = state(status: "approved", currentURL: "https://cdn.example/approved.jpg")
        let service = ProfilePictureServiceStub(states: [pending, approved])
        let monitor = ProfilePictureReviewMonitor(defaults: defaults, service: service)
        let changed = expectation(forNotification: .profilePictureDidChange, object: nil)

        await monitor.refresh(for: Student(studentId: "123", gymId: 94, name: "Test"))
        await monitor.refresh(for: Student(studentId: "123", gymId: 94, name: "Test"))

        await fulfillment(of: [changed], timeout: 1)
        XCTAssertNotNil(monitor.outcomeMessage)
    }

    func testRecoverableSubmitFailurePreservesPreparedPicture() async {
        let ready = ProfilePictureState(
            unlocked: true,
            referralConversions: 3,
            unlockThreshold: 3,
            currentURL: nil,
            approvedAt: nil,
            nextEligibleAt: nil,
            canSubmit: true,
            submission: nil
        )
        let service = ProfilePictureServiceStub(states: [ready], submitError: URLError(.notConnectedToInternet))
        let viewModel = ProfilePictureEditorViewModel(
            student: Student(studentId: "123", gymId: 94, name: "Test"),
            service: service
        )
        let prepared = picture(bytes: [0xff, 0xd8, 0xff, 0], mime: "image/jpeg", ext: "jpg")
        viewModel.preparedPicture = prepared

        await viewModel.submit()

        XCTAssertEqual(viewModel.preparedPicture, prepared)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    private func picture(bytes: [UInt8], mime: String, ext: String) -> PreparedProfilePicture {
        PreparedProfilePicture(data: Data(bytes), mimeType: mime, fileExtension: ext)
    }

    private func state(status: String, currentURL: String?) -> ProfilePictureState {
        ProfilePictureState(
            unlocked: true,
            referralConversions: 3,
            unlockThreshold: 3,
            currentURL: currentURL,
            approvedAt: status == "approved" ? "2026-08-02T00:00:00Z" : nil,
            nextEligibleAt: status == "approved" ? "2026-11-02T00:00:00Z" : nil,
            canSubmit: false,
            submission: ProfilePictureSubmission(
                id: "submission",
                status: status,
                createdAt: "2026-08-01T00:00:00Z",
                submittedAt: "2026-08-01T00:00:01Z",
                reviewedAt: status == "approved" ? "2026-08-02T00:00:00Z" : nil,
                rejectionReason: nil,
                reviewNote: nil,
                approvedURL: currentURL
            )
        )
    }
}

@MainActor
private final class ProfilePictureServiceStub: ProfilePictureServing {
    private var states: [ProfilePictureState]
    private let submitError: Error?

    init(states: [ProfilePictureState], submitError: Error? = nil) {
        self.states = states
        self.submitError = submitError
    }

    func state(studentID: String) async throws -> ProfilePictureState {
        if states.count > 1 { return states.removeFirst() }
        return states[0]
    }

    func submit(student: Student, picture: PreparedProfilePicture) async throws -> ProfilePictureSubmitResult {
        if let submitError { throw submitError }
        ProfilePictureSubmitResult(ok: true, code: nil, error: nil)
    }
}
