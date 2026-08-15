//
//  LiveActivityVariant.swift
//  BetterLectio
//
//  Created by Elliott Friedrich on 27/02/2026.
//

import Foundation

enum LiveActivityVariant: String, Codable, CaseIterable, Identifiable {
    case compact
    case standard
    case expanded

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .compact:  return "Kompakt"
        case .standard: return "Standard"
        case .expanded: return "Udvidet"
        }
    }

    var description: String {
        switch self {
        case .compact:  return "Fag og tid"
        case .standard: return "Fag, lokale, tid og fremgang"
        case .expanded: return "Alt info inkl. næste lektion"
        }
    }

    static let appGroupIdentifier = "group.dk.elliottf.betterlectio"
    private static let userDefaultsKey = "liveActivityVariant"

    static var current: LiveActivityVariant {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
              let raw = defaults.string(forKey: userDefaultsKey),
              let variant = LiveActivityVariant(rawValue: raw) else {
            return .standard
        }
        return variant
    }

    static func save(_ variant: LiveActivityVariant) {
        UserDefaults(suiteName: appGroupIdentifier)?
            .set(variant.rawValue, forKey: userDefaultsKey)
    }
}
