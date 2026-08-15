import Combine
import SwiftUI
import UIKit
import CoreMotion

@MainActor
final class FeedbackCoordinator: ObservableObject {
    static let shared = FeedbackCoordinator()

    @Published private(set) var presentation: FeedbackPresentation?
    private var lastPresentationDate = Date.distantPast
    private let cooldown: TimeInterval = 2.5

    private init() {}

    func present(for student: Student) {
        guard presentation == nil, Date().timeIntervalSince(lastPresentationDate) >= cooldown else { return }
        lastPresentationDate = Date()

        let capture = FeedbackCapture(
            screenshot: Self.captureActiveWindow(),
            logs: FeedbackLogBuffer.shared.snapshot(),
            capturedAt: Date()
        )
        presentation = FeedbackPresentation(student: student, capture: capture)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func dismiss() {
        presentation = nil
    }

    private static func captureActiveWindow() -> UIImage? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = scenes
            .flatMap(\.windows)
            .first(where: { $0.isKeyWindow && !$0.isHidden })
        else { return nil }

        // Never capture a system alert; Settings contains credential-management
        // alerts whose values must not become feedback attachments.
        var presentedController = window.rootViewController?.presentedViewController
        while let controller = presentedController {
            if controller is UIAlertController { return nil }
            presentedController = controller.presentedViewController
        }

        let bounds = window.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = min(window.windowScene?.screen.scale ?? 2, 2)
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
        return renderer.image { context in
            if !window.drawHierarchy(in: bounds, afterScreenUpdates: false) {
                window.layer.render(in: context.cgContext)
            }
        }
    }
}

struct FeedbackPresentation: Identifiable {
    let id = UUID()
    let student: Student
    let capture: FeedbackCapture
}

struct ShakeListener: UIViewControllerRepresentable {
    let onShake: () -> Void

    func makeUIViewController(context: Context) -> ShakeListenerViewController {
        let controller = ShakeListenerViewController()
        controller.onShake = onShake
        return controller
    }

    func updateUIViewController(_ controller: ShakeListenerViewController, context: Context) {
        controller.onShake = onShake
    }
}

final class ShakeListenerViewController: UIViewController {
    var onShake: (() -> Void)?
    private let motionManager = CMMotionManager()
    private var impulseDetector = ShakeImpulseDetector()
    private var isObservingLifecycle = false

    override var canBecomeFirstResponder: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
        observeLifecycleIfNeeded()
        startMotionUpdates()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        motionManager.stopDeviceMotionUpdates()
        stopObservingLifecycle()
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        guard motion == .motionShake else {
            super.motionEnded(motion, with: event)
            return
        }
        onShake?()
    }

    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable, !motionManager.isDeviceMotionActive else { return }
        impulseDetector.reset()
        motionManager.deviceMotionUpdateInterval = 0.1
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let acceleration = motion?.userAcceleration else { return }
            let magnitude = sqrt(
                acceleration.x * acceleration.x
                    + acceleration.y * acceleration.y
                    + acceleration.z * acceleration.z
            )
            guard self.impulseDetector.record(
                magnitude: magnitude,
                at: ProcessInfo.processInfo.systemUptime
            ) else { return }
            self.onShake?()
        }
    }

    private func observeLifecycleIfNeeded() {
        guard !isObservingLifecycle else { return }
        isObservingLifecycle = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    private func stopObservingLifecycle() {
        guard isObservingLifecycle else { return }
        isObservingLifecycle = false
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func appWillResignActive() {
        motionManager.stopDeviceMotionUpdates()
        impulseDetector.reset()
    }

    @objc private func appDidBecomeActive() {
        guard viewIfLoaded?.window != nil else { return }
        becomeFirstResponder()
        startMotionUpdates()
    }
}

/// Requires two strong impulses close together, which rejects isolated bumps and drops
/// while still recognizing a deliberate back-and-forth shake.
struct ShakeImpulseDetector {
    private(set) var firstImpulseAt: TimeInterval?
    let threshold: Double
    let minimumSpacing: TimeInterval
    let maximumSpacing: TimeInterval

    init(
        threshold: Double = 1.35,
        minimumSpacing: TimeInterval = 0.08,
        maximumSpacing: TimeInterval = 0.7
    ) {
        self.threshold = threshold
        self.minimumSpacing = minimumSpacing
        self.maximumSpacing = maximumSpacing
    }

    mutating func record(magnitude: Double, at timestamp: TimeInterval) -> Bool {
        guard magnitude >= threshold else { return false }
        guard let firstImpulseAt else {
            self.firstImpulseAt = timestamp
            return false
        }

        let spacing = timestamp - firstImpulseAt
        if spacing > maximumSpacing {
            self.firstImpulseAt = timestamp
            return false
        }
        guard spacing >= minimumSpacing else { return false }

        self.firstImpulseAt = nil
        return true
    }

    mutating func reset() {
        firstImpulseAt = nil
    }
}
