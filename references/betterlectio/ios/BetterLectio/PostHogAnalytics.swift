import Foundation
import PostHog

/// Single analytics boundary for the app. Keeping SDK calls here makes identity and
/// privacy behavior consistent and keeps feature code independent of the vendor API.
enum Analytics {
    private static let projectTokenKey = "POSTHOG_PROJECT_TOKEN"
    private static let hostKey = "POSTHOG_HOST"
    private static let identifiedStudentKey = "posthog.identifiedStudent"
    private static let errorBudgetKey = "posthog.errorBudget"
    private static let maxErrorsPerDay = 5
    private static let allowedEvents: Set<String> = [
        "login_completed", "login_started", "login_failed", "demo_entered",
        "lectio session lost", "logged_out",
        "feedback_submitted", "referral_shared", "referral_share_sheet_opened",
        "referral_screen_opened", "absence_cause_updated",
        "browser_extension_opened", "browser_extension_copied", "browser_extension_shared",
        "review_prompt_shown", "review_prompt_positive", "review_prompt_negative",
        "review_prompt_dismissed", "review_play_flow_requested",
    ]

    static func configure() {
        guard
            let projectToken = bundleValue(for: projectTokenKey),
            !projectToken.isEmpty
        else {
            #if DEBUG
            print("⚠️ [Analytics] PostHog disabled: missing POSTHOG_PROJECT_TOKEN")
            #endif
            return
        }

        let host = bundleValue(for: hostKey) ?? "https://eu.i.posthog.com"
        let config = PostHogConfig(projectToken: projectToken, host: host)
        // Explicit-only analytics. Automatic signals are too noisy for the
        // small set of product questions we use PostHog to answer.
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
        config.errorTrackingConfig.autoCapture = true
        config.captureElementInteractions = false
        config.sessionReplay = false
        config.preloadFeatureFlags = false
        config.capturePushNotificationSubscriptions = false
        config.capturePushNotificationOpened = false
        if #available(iOS 15.0, *) {
            config.surveys = false
        }

        #if DEBUG
        config.debug = true
        #endif

        PostHogSDK.shared.setup(config)
    }

    /// Uses the same stable distinct ID as Android so a student has one cross-platform profile.
    static func identify(_ student: Student) {
        guard !student.isDemo else { return }
        guard UserDefaults.standard.string(forKey: identifiedStudentKey) != student.studentId else {
            return
        }

        var properties: [String: Any] = [
            "gym_id": student.gymId,
            "platform": "ios"
        ]
        if let schoolName = student.schoolName, !schoolName.isEmpty {
            properties["school_name"] = schoolName
        }
        if let classLabel = student.classLabel, !classLabel.isEmpty {
            properties["class_name"] = classLabel
        }

        PostHogSDK.shared.identify(student.studentId, userProperties: properties)
        UserDefaults.standard.set(student.studentId, forKey: identifiedStudentKey)
    }

    static func capture(_ event: String, properties: [String: Any]? = nil) {
        guard allowedEvents.contains(event) else { return }
        FeedbackLogBuffer.shared.record("Analytics event=\(event)")
        var enriched = properties ?? [:]
        enriched["platform"] = "ios"
        PostHogSDK.shared.capture(event, properties: enriched)
    }

    static func capture(_ error: Error, source: String) {
        FeedbackLogBuffer.shared.record(
            "Operational error source=\(source) type=\(String(reflecting: type(of: error)))",
            level: "E"
        )
        let day = Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
        let key = "\(errorBudgetKey).\(day)"
        let signature = String(
            "\(source):\(String(reflecting: type(of: error))):\(error.localizedDescription)".prefix(500)
        )
        var signatures = UserDefaults.standard.stringArray(forKey: key) ?? []
        guard signatures.count < maxErrorsPerDay, !signatures.contains(signature) else { return }

        signatures.append(signature)
        UserDefaults.standard.set(signatures, forKey: key)
        PostHogSDK.shared.captureException(error, properties: [
            "source": source,
            "platform": "ios"
        ])
    }

    static func reset() {
        PostHogSDK.shared.reset()
        UserDefaults.standard.removeObject(forKey: identifiedStudentKey)
    }

    private static func bundleValue(for key: String) -> String? {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
