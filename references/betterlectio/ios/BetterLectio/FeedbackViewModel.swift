import Combine
import Foundation
@preconcurrency import UIKit

@MainActor
final class FeedbackViewModel: ObservableObject {
    struct Success: Equatable {
        let isDemo: Bool
        let attachmentFailed: Bool
    }

    enum Phase: Equatable {
        case editing
        case sending
        case success(Success)
        case failure(String)
    }

    @Published var category: FeedbackCategory = .bug
    @Published private(set) var message = ""
    @Published var includeScreenshot: Bool
    @Published var includeLogs: Bool
    @Published private(set) var phase: Phase = .editing

    let presentation: FeedbackPresentation
    private let service: any FeedbackSubmitting

    init(
        presentation: FeedbackPresentation,
        service: any FeedbackSubmitting = SupabaseFeedbackService.shared
    ) {
        self.presentation = presentation
        self.service = service
        includeScreenshot = presentation.capture.screenshot != nil
        includeLogs = !presentation.capture.logs.isEmpty
    }

    var isSending: Bool { phase == .sending }

    var canSubmit: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    var remainingCharacters: Int {
        FeedbackLimits.maximumMessageCharacters - message.count
    }

    func updateMessage(_ value: String) {
        message = String(value.prefix(FeedbackLimits.maximumMessageCharacters))
        if case .failure = phase {
            phase = .editing
        }
    }

    func submit() async {
        guard !isSending else { return }
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            phase = .failure(FeedbackSubmissionError.emptyMessage.localizedDescription)
            return
        }

        // Freeze every user choice before asynchronous image work starts. The UI is
        // disabled while sending, and these values make that invariant explicit.
        let selectedCategory = category
        let wantsScreenshot = includeScreenshot
        let wantsLogs = includeLogs
        let capture = presentation.capture
        phase = .sending

        if presentation.student.isDemo {
            try? await Task.sleep(nanoseconds: 250_000_000)
            phase = .success(Success(isDemo: true, attachmentFailed: false))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return
        }

        do {
            let screenshot: EncodedFeedbackScreenshot?
            if wantsScreenshot, let image = capture.screenshot {
                screenshot = await Task.detached(priority: .userInitiated) {
                    Self.encodeScreenshot(image)
                }.value
            } else {
                screenshot = nil
            }

            let logs = wantsLogs
                ? String(capture.logs.prefix(FeedbackLogBuffer.maxSnapshotCharacters))
                : nil
            let bundle = Bundle.main
            let context = FeedbackContext(
                app_version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                app_build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                os_version: UIDevice.current.systemVersion,
                device_model: Self.deviceModelIdentifier,
                locale: Locale.current.identifier,
                captured_at: ISO8601DateFormatter().string(from: capture.capturedAt),
                include_logs: logs != nil,
                logs: logs
            )

            let result = try await service.submit(
                student: presentation.student,
                category: selectedCategory,
                message: trimmedMessage,
                context: context,
                screenshot: screenshot
            )

            let attachmentFailed = wantsScreenshot && result.attachmentStatus != .uploaded
            FeedbackLogBuffer.shared.record(
                "Feedback submitted category=\(selectedCategory.rawValue) attachment=\(result.attachmentStatus)"
            )
            var analytics: [String: Any] = [
                "category": selectedCategory.rawValue,
                "has_screenshot": result.attachmentStatus == .uploaded,
                "screenshot_requested": wantsScreenshot,
                "has_logs": logs != nil
            ]
            if let feedbackID = result.feedbackID {
                analytics["feedback_id"] = feedbackID
            }
            Analytics.capture("feedback_submitted", properties: analytics)

            phase = .success(Success(isDemo: false, attachmentFailed: attachmentFailed))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            FeedbackLogBuffer.shared.record("Feedback submission failed: \(type(of: error))", level: "E")
            phase = .failure(Self.userFacingMessage(for: error))
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    func retry() async {
        await submit()
    }

    private nonisolated static func userFacingMessage(for error: Error) -> String {
        if let feedbackError = error as? FeedbackSubmissionError {
            return feedbackError.localizedDescription
        }
        if error is URLError {
            return String(localized: "Tjek din internetforbindelse, og prøv igen. Din tekst er stadig gemt.")
        }
        if error.localizedDescription.localizedCaseInsensitiveContains("rate limit") {
            return String(localized: "Du har sendt flere tilbagemeldinger på kort tid. Vent lidt, og prøv igen.")
        }
        return String(localized: "Feedbacken kunne ikke sendes. Prøv igen om et øjeblik. Din tekst er stadig gemt.")
    }

    nonisolated static func encodeScreenshot(_ sourceImage: UIImage) -> EncodedFeedbackScreenshot? {
        var image = sourceImage
        let sourceWidth = image.cgImage?.width ?? Int(image.size.width * image.scale)
        let sourceHeight = image.cgImage?.height ?? Int(image.size.height * image.scale)
        if sourceWidth > 720 {
            image = resizedImage(
                image,
                pixelWidth: 720,
                pixelHeight: max(1, Int(Double(sourceHeight) * 720 / Double(sourceWidth)))
            )
        }
        var quality: CGFloat = 0.82

        for _ in 0..<8 {
            if let data = image.jpegData(compressionQuality: quality),
               data.count <= FeedbackLimits.maximumScreenshotBytes {
                return EncodedFeedbackScreenshot(
                    data: data,
                    width: image.cgImage?.width ?? Int(image.size.width * image.scale),
                    height: image.cgImage?.height ?? Int(image.size.height * image.scale)
                )
            }

            let pixelWidth = image.cgImage?.width ?? Int(image.size.width * image.scale)
            let pixelHeight = image.cgImage?.height ?? Int(image.size.height * image.scale)
            if pixelWidth > 480 {
                let nextWidth = max(480, Int(Double(pixelWidth) * 0.75))
                let nextHeight = max(1, Int(Double(pixelHeight) * Double(nextWidth) / Double(pixelWidth)))
                image = resizedImage(image, pixelWidth: nextWidth, pixelHeight: nextHeight)
            }
            quality = max(0.4, quality - 0.08)
        }
        return nil
    }

    private nonisolated static func resizedImage(
        _ image: UIImage,
        pixelWidth: Int,
        pixelHeight: Int
    ) -> UIImage {
        let size = CGSize(width: pixelWidth, height: pixelHeight)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private nonisolated static var deviceModelIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }
}
