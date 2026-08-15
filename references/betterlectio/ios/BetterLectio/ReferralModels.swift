import Foundation

let referralUnlockThreshold = 3

struct ReferralStats: Decodable, Equatable, Sendable {
    let totalClicks: Int
    let uniqueClickers: Int
    let conversions: Int
    let recentReferrals: [RecentReferral]

    enum CodingKeys: String, CodingKey {
        case totalClicks = "total_clicks"
        case uniqueClickers = "unique_clickers"
        case conversions
        case recentReferrals = "recent_referrals"
    }

    static let empty = ReferralStats(totalClicks: 0, uniqueClickers: 0, conversions: 0, recentReferrals: [])
    static let demo = ReferralStats(
        totalClicks: 7,
        uniqueClickers: 5,
        conversions: 2,
        recentReferrals: [
            RecentReferral(studentID: "demo-1", name: "Sofie Jensen", attributedAt: nil),
            RecentReferral(studentID: "demo-2", name: "Emil Nielsen", attributedAt: nil),
        ]
    )
}

struct RecentReferral: Decodable, Equatable, Identifiable, Sendable {
    let studentID: String
    let name: String?
    let attributedAt: String?

    var id: String { studentID }

    enum CodingKeys: String, CodingKey {
        case studentID = "student_id"
        case name
        case attributedAt = "attributed_at"
    }

    init(studentID: String, name: String?, attributedAt: String?) {
        self.studentID = studentID
        self.name = name
        self.attributedAt = attributedAt
    }
}

struct ReferralProgress: Equatable, Sendable {
    let current: Int
    let target: Int
    let unlocked: Bool
    let remaining: Int

    init(conversions: Int, target: Int = referralUnlockThreshold) {
        let safeTarget = max(1, target)
        let safeConversions = max(0, conversions)
        self.current = min(safeConversions, safeTarget)
        self.target = safeTarget
        self.unlocked = safeConversions >= safeTarget
        self.remaining = max(0, safeTarget - safeConversions)
    }

    var fraction: Double { Double(current) / Double(target) }
}

struct ReferralFinalizeResult: Decodable, Equatable, Sendable {
    let attributed: Bool
    let reason: String?
    let referrerStudentID: String?
    let referrerName: String?
    let referrerUnlocked: Bool?

    enum CodingKeys: String, CodingKey {
        case attributed, reason, referrerName, referrerUnlocked
        case referrerStudentID = "referrerStudentId"
    }
}

struct PendingReferral: Codable, Equatable, Sendable {
    let token: UUID
    let capturedAt: Date
}

enum ReferralLink {
    static let host = "betterlectio.dk"

    static func shareURL(studentID: String) -> URL? {
        let trimmed = studentID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/r/\(trimmed)"
        return components.url
    }

    static func parse(_ url: URL) -> (studentID: String, token: UUID?)? {
        guard url.scheme?.lowercased() == "https", url.host?.lowercased() == host else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, parts[0] == "r" else { return nil }
        let studentID = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        guard !studentID.isEmpty,
              studentID.count <= 48,
              studentID.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "bl_ref" })?.value
            .flatMap(UUID.init(uuidString:))
        return (studentID, token)
    }
}
