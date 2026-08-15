import Foundation
import UIKit

enum FeedbackCategory: String, CaseIterable, Identifiable, Sendable {
    case bug
    case idea
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bug: String(localized: "Fejl", comment: "Feedback category")
        case .idea: String(localized: "Idé", comment: "Feedback category")
        case .other: String(localized: "Andet", comment: "Feedback category")
        }
    }

    var systemImage: String {
        switch self {
        case .bug: "ladybug"
        case .idea: "lightbulb"
        case .other: "ellipsis"
        }
    }

    var prompt: String {
        switch self {
        case .bug: String(localized: "Hvad gik galt, og hvad lavede du lige inden?", comment: "Bug feedback prompt")
        case .idea: String(localized: "Hvad mangler eller kunne fungere bedre?", comment: "Idea feedback prompt")
        case .other: String(localized: "Skriv din besked her", comment: "Other feedback prompt")
        }
    }
}

struct FeedbackCapture {
    let screenshot: UIImage?
    let logs: String
    let capturedAt: Date
}

struct FeedbackSubmission {
    let category: FeedbackCategory
    let message: String
    let includeScreenshot: Bool
    let includeLogs: Bool
    let capture: FeedbackCapture
}

enum FeedbackLimits {
    static let maximumMessageCharacters = 4_000
    static let maximumScreenshotBytes = 500_000
}

enum FeedbackAttachmentStatus: Equatable, Sendable {
    case notRequested
    case uploaded
    case failed
}

struct FeedbackSubmitResult: Equatable, Sendable {
    let feedbackID: String?
    let attachmentStatus: FeedbackAttachmentStatus
    let isDemo: Bool

    static let demo = FeedbackSubmitResult(
        feedbackID: nil,
        attachmentStatus: .notRequested,
        isDemo: true
    )
}

enum FeedbackSubmissionError: LocalizedError {
    case demoMode
    case notConfigured
    case notAuthenticated
    case emptyMessage
    case messageTooLong

    var errorDescription: String? {
        switch self {
        case .demoMode: String(localized: "Feedback kan ikke sendes fra demotilstand.")
        case .notConfigured: String(localized: "Feedbacktjenesten er ikke konfigureret.")
        case .notAuthenticated: String(localized: "Din sikre feedbacksession kunne ikke oprettes. Prøv igen.")
        case .emptyMessage: String(localized: "Skriv en besked, før du sender.")
        case .messageTooLong:
            String(
                localized: "Beskeden må højst være \(FeedbackLimits.maximumMessageCharacters) tegn.",
                comment: "Feedback message character limit"
            )
        }
    }
}
