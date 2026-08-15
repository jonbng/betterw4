import Combine
import Foundation

extension Notification.Name {
    static let profilePictureDidChange = Notification.Name("dk.echolabs.betterlectio.profilePictureDidChange")
}

@MainActor
final class ProfilePictureReviewMonitor: ObservableObject {
    static let shared = ProfilePictureReviewMonitor()
    @Published var outcomeMessage: String?

    private let defaults: UserDefaults
    private let service: any ProfilePictureServing

    init(
        defaults: UserDefaults = .standard,
        service: any ProfilePictureServing = SupabaseProfilePictureService.shared
    ) {
        self.defaults = defaults
        self.service = service
    }

    func refresh(for student: Student) async {
        guard !student.isDemo,
              let state = try? await service.state(studentID: student.studentId)
        else { return }
        let key = "profilePicture.reviewStatus.\(student.studentId)"
        let previous = defaults.string(forKey: key)
        let current = state.submission?.status
        if previous == "pending" || previous == "uploading" {
            if current == "approved" {
                outcomeMessage = String(localized: "profile_picture.review_approved", defaultValue: "Dit nye profilbillede er godkendt og nu synligt.")
                await publishChange(for: student)
            } else if current == "rejected" {
                outcomeMessage = String(localized: "profile_picture.review_rejected", defaultValue: "Dit profilbillede blev ikke godkendt. Åbn profilbilledet for at se årsagen og prøve igen.")
                await publishChange(for: student)
            }
        }
        if let current { defaults.set(current, forKey: key) }
    }

    func resetPresentation() { outcomeMessage = nil }

    private func publishChange(for student: Student) async {
        SupabaseStudentProfileService.shared.clearCache()
        await PublicProfileImageLoader.shared.clearCache()
        NotificationCenter.default.post(
            name: .profilePictureDidChange,
            object: nil,
            userInfo: ["studentId": student.studentId]
        )
    }
}
