//
//  StudentProfile.swift
//  BetterLectio
//

import Foundation

/// BetterLectio profile metadata returned by the school-scoped profile RPCs.
/// Lectio's directory entry remains the source of truth and fallback identity.
struct StudentProfile: Decodable, Equatable, Sendable {
    let id: String
    let name: String?
    let profileDescription: String?
    let instagram: String?
    let birthdate: String?
    let showBirthday: Bool
    let customProfilePictureURL: String?
    let lectioProfilePictureURL: String?
    let className: String?
    let lastSeenAt: String?
    let extensionInstalledAt: String?
    let extensionUninstalledAt: String?
    let appInstalledAt: String?

    init(
        id: String,
        name: String? = nil,
        profileDescription: String? = nil,
        instagram: String? = nil,
        birthdate: String? = nil,
        showBirthday: Bool = false,
        customProfilePictureURL: String? = nil,
        lectioProfilePictureURL: String? = nil,
        className: String? = nil,
        lastSeenAt: String? = nil,
        extensionInstalledAt: String? = nil,
        extensionUninstalledAt: String? = nil,
        appInstalledAt: String? = nil
    ) {
        self.id = id
        self.name = name
        self.profileDescription = profileDescription
        self.instagram = instagram
        self.birthdate = birthdate
        self.showBirthday = showBirthday
        self.customProfilePictureURL = customProfilePictureURL
        self.lectioProfilePictureURL = lectioProfilePictureURL
        self.className = className
        self.lastSeenAt = lastSeenAt
        self.extensionInstalledAt = extensionInstalledAt
        self.extensionUninstalledAt = extensionUninstalledAt
        self.appInstalledAt = appInstalledAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, instagram, birthdate
        case profileDescription = "description"
        case showBirthday = "show_birthday"
        case customProfilePictureURL = "custom_pfp_url"
        case lectioProfilePictureURL = "lectio_pfp_url"
        case className = "class_name"
        case lastSeenAt = "last_seen_at"
        case extensionInstalledAt = "extension_installed_at"
        case extensionUninstalledAt = "extension_uninstalled_at"
        case appInstalledAt = "app_installed_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        profileDescription = try container.decodeIfPresent(String.self, forKey: .profileDescription)
        instagram = try container.decodeIfPresent(String.self, forKey: .instagram)
        birthdate = try container.decodeIfPresent(String.self, forKey: .birthdate)
        showBirthday = try container.decodeIfPresent(Bool.self, forKey: .showBirthday) ?? false
        customProfilePictureURL = try container.decodeIfPresent(String.self, forKey: .customProfilePictureURL)
        lectioProfilePictureURL = try container.decodeIfPresent(String.self, forKey: .lectioProfilePictureURL)
        className = try container.decodeIfPresent(String.self, forKey: .className)
        lastSeenAt = try container.decodeIfPresent(String.self, forKey: .lastSeenAt)
        extensionInstalledAt = try container.decodeIfPresent(String.self, forKey: .extensionInstalledAt)
        extensionUninstalledAt = try container.decodeIfPresent(String.self, forKey: .extensionUninstalledAt)
        appInstalledAt = try container.decodeIfPresent(String.self, forKey: .appInstalledAt)
    }

    nonisolated var hasBetterLectio: Bool {
        hasBetterLectio(at: Date())
    }

    nonisolated func hasBetterLectio(at date: Date) -> Bool {
        isActiveStudent(at: date) || Self.nonEmpty(appInstalledAt) != nil
    }

    nonisolated func displayName(fallback: String) -> String {
        Self.nonEmpty(name) ?? fallback
    }

    /// Profile URLs are remote public assets. Restrict them to HTTPS before display.
    nonisolated func pictureURL(fallback: URL?) -> URL? {
        for value in [customProfilePictureURL, lectioProfilePictureURL] {
            guard let value = Self.nonEmpty(value),
                  let url = URL(string: value),
                  url.scheme?.lowercased() == "https",
                  url.host != nil else { continue }
            return url
        }
        return fallback
    }

    nonisolated var formattedBirthday: String? {
        guard showBirthday, let raw = Self.nonEmpty(birthdate) else { return nil }
        let parts = raw.prefix(10).split(separator: "-")
        guard parts.count == 3,
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              (1...12).contains(month),
              (1...31).contains(day) else { return raw }
        let months = ["jan", "feb", "mar", "apr", "maj", "jun", "jul", "aug", "sep", "okt", "nov", "dec"]
        return "\(day). \(months[month - 1]) \(parts[0])"
    }

    private nonisolated func isActiveStudent(at date: Date) -> Bool {
        guard Self.nonEmpty(extensionUninstalledAt) == nil,
              let rawTimestamp = Self.nonEmpty(lastSeenAt) ?? Self.nonEmpty(extensionInstalledAt),
              let timestamp = Self.parseTimestamp(rawTimestamp) else { return false }
        let age = date.timeIntervalSince(timestamp)
        return age >= -5 * 60 && age <= 14 * 24 * 60 * 60
    }

    private nonisolated static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private nonisolated static func parseTimestamp(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

enum InstagramProfileLink {
    nonisolated static func handle(from value: String?) -> String? {
        guard var candidate = value?.trimmingCharacters(in: .whitespacesAndNewlines), !candidate.isEmpty else {
            return nil
        }

        let lowercased = candidate.lowercased()
        if lowercased.contains("://") || lowercased.hasPrefix("instagram.com/") || lowercased.hasPrefix("www.instagram.com/") {
            let urlString = lowercased.contains("://") ? candidate : "https://\(candidate)"
            guard let components = URLComponents(string: urlString),
                  let host = components.host?.lowercased(),
                  host == "instagram.com" || host == "www.instagram.com" else { return nil }
            let pathParts = components.path.split(separator: "/")
            guard pathParts.count == 1 else { return nil }
            candidate = String(pathParts[0])
        }

        candidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "@/"))
        guard !candidate.isEmpty, candidate.count <= 30,
              candidate.unicodeScalars.allSatisfy({ scalar in
                  let value = scalar.value
                  return (48...57).contains(value)
                      || (65...90).contains(value)
                      || (97...122).contains(value)
                      || value == 46
                      || value == 95
              }) else { return nil }
        return candidate
    }

    nonisolated static func displayText(for value: String?) -> String? {
        handle(from: value).map { "@\($0)" }
    }

    nonisolated static func url(for value: String?) -> URL? {
        guard let handle = handle(from: value) else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.instagram.com"
        components.path = "/\(handle)"
        return components.url
    }
}
