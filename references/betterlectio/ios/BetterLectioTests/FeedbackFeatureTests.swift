import UIKit
import XCTest
@testable import BetterLectio

@MainActor
final class FeedbackFeatureTests: XCTestCase {
    func testMessageIsLimitedWithoutSilentSubmissionTruncation() {
        let viewModel = makeViewModel(service: FeedbackServiceStub())

        viewModel.updateMessage(String(repeating: "a", count: 4_250))

        XCTAssertEqual(viewModel.message.count, FeedbackLimits.maximumMessageCharacters)
        XCTAssertEqual(viewModel.remainingCharacters, 0)
    }

    func testNetworkFailurePreservesDraftAndUsesFriendlyMessage() async {
        let viewModel = makeViewModel(
            service: FeedbackServiceStub(error: URLError(.notConnectedToInternet))
        )
        viewModel.updateMessage("Min tekst skal blive her")

        await viewModel.submit()

        XCTAssertEqual(viewModel.message, "Min tekst skal blive her")
        guard case .failure(let message) = viewModel.phase else {
            return XCTFail("Expected failure")
        }
        XCTAssertTrue(message.contains("internetforbindelse"))
    }

    func testAttachmentFailureIsPartialSuccessInsteadOfFullSuccess() async {
        let viewModel = makeViewModel(
            capture: FeedbackCapture(
                screenshot: UIImage(systemName: "photo"),
                logs: "safe log",
                capturedAt: Date()
            ),
            service: FeedbackServiceStub(
                result: FeedbackSubmitResult(
                    feedbackID: "feedback-id",
                    attachmentStatus: .failed,
                    isDemo: false
                )
            )
        )
        viewModel.updateMessage("Et problem")

        await viewModel.submit()

        XCTAssertEqual(
            viewModel.phase,
            .success(.init(isDemo: false, attachmentFailed: true))
        )
    }

    func testDemoExercisesSuccessWithoutCallingService() async {
        let service = FeedbackServiceStub(error: TestError.serviceMustNotBeCalled)
        let presentation = FeedbackPresentation(
            student: .demo,
            capture: FeedbackCapture(screenshot: nil, logs: "", capturedAt: Date())
        )
        let viewModel = FeedbackViewModel(presentation: presentation, service: service)
        viewModel.updateMessage("Demo feedback")

        await viewModel.submit()

        XCTAssertEqual(
            viewModel.phase,
            .success(.init(isDemo: true, attachmentFailed: false))
        )
    }

    func testScreenshotEncodingHonorsPixelAndByteBudgets() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: 1_400, height: 2_000),
            format: format
        ).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1_400, height: 1_000))
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 1_000, width: 1_400, height: 1_000))
        }

        let encoded = try XCTUnwrap(FeedbackViewModel.encodeScreenshot(image))

        XCTAssertLessThanOrEqual(encoded.width, 720)
        XCTAssertLessThanOrEqual(encoded.data.count, FeedbackLimits.maximumScreenshotBytes)
    }

    func testShakeRequiresTwoSeparatedImpulses() {
        var detector = ShakeImpulseDetector(
            threshold: 1.0,
            minimumSpacing: 0.08,
            maximumSpacing: 0.7
        )

        XCTAssertFalse(detector.record(magnitude: 1.2, at: 1.0))
        XCTAssertFalse(detector.record(magnitude: 1.3, at: 1.04))
        XCTAssertTrue(detector.record(magnitude: 1.4, at: 1.2))
        XCTAssertFalse(detector.record(magnitude: 1.4, at: 2.0))
        XCTAssertFalse(detector.record(magnitude: 1.4, at: 2.9))
    }

    private func makeViewModel(
        capture: FeedbackCapture = FeedbackCapture(
            screenshot: nil,
            logs: "safe log",
            capturedAt: Date()
        ),
        service: any FeedbackSubmitting
    ) -> FeedbackViewModel {
        FeedbackViewModel(
            presentation: FeedbackPresentation(
                student: Student(
                    studentId: "123",
                    gymId: 94,
                    name: "Test",
                    pictureId: nil,
                    classLabel: nil,
                    schoolName: "Testskole"
                ),
                capture: capture
            ),
            service: service
        )
    }
}

@MainActor
private struct FeedbackServiceStub: FeedbackSubmitting {
    var result = FeedbackSubmitResult(
        feedbackID: "feedback-id",
        attachmentStatus: .notRequested,
        isDemo: false
    )
    var error: Error?

    func submit(
        student: Student,
        category: FeedbackCategory,
        message: String,
        context: FeedbackContext,
        screenshot: EncodedFeedbackScreenshot?
    ) async throws -> FeedbackSubmitResult {
        if let error { throw error }
        return result
    }
}

private enum TestError: Error {
    case serviceMustNotBeCalled
}
