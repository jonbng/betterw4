import StoreKit
import UIKit

/// App Store in-app review wrapper. Safe when no scene is available.
enum AppStoreReviewLauncher {
    /// Requests the system review dialog. Returns whether a foreground scene was found
    /// to host the request (the system may still suppress the UI due to quota).
    @MainActor
    @discardableResult
    static func request() -> Bool {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive })
                ?? scenes.first
        else {
            return false
        }
        AppStore.requestReview(in: scene)
        return true
    }
}
