//
//  DirectoryModels.swift
//  BetterW4
//
//  The **legacy entity bridge** for the people directory.
//
//  W4's real people model is `PeopleModels.swift` — `DirectoryPerson`, `DirectoryPersonProfile`,
//  `PeopleDirectorySource` — produced by `W4PeopleParser` and served by `DirectoryRepository`.
//  What is left in this file is the older, flatter shape that `DirectoryStore`'s legacy bridge
//  still hands to code outside the directory.
//
//  `DirectoryStore.legacyEntity(_:)` is the only thing that builds a `DirectoryEntity`, and it
//  builds it from a W4 `DirectoryPerson`. Nothing here fetches, parses or stores anything, and
//  nothing here knows about any host but `w4.uwcrcn.no`.
//
//  Delete this file together with `DirectoryStore`'s `// MARK: - Legacy bridge` section, once
//  nothing outside the directory asks for a `DirectoryEntity` again.
//

import Foundation

// MARK: - Kind

/// The two kinds of person W4 has: students, and the staff W4's own markup calls `people/staff`.
enum DirectoryEntityKind: String, Codable, CaseIterable, Sendable {
    case student
    /// W4 staff. The case name is the one `DirectoryStore.legacyEntity(_:)` writes.
    case teacher

    nonisolated var displayName: String {
        switch self {
        case .student: return "Student"
        case .teacher: return "Staff"
        }
    }
}

// MARK: - Identity

/// A legacy entity key. `rawID` carries the UWC id, which is the only id W4 has.
struct DirectoryEntityID: Codable, Equatable, Hashable, Sendable {
    let kind: DirectoryEntityKind
    let rawID: String

    init(kind: DirectoryEntityKind, rawID: String) {
        self.kind = kind
        self.rawID = rawID
    }

    nonisolated var key: String {
        "\(kind.rawValue)|\(rawID)"
    }
}

/// The few extra fields a legacy row can carry. Everything W4-specific lives on `DirectoryPerson`.
struct DirectoryMetadata: Codable, Equatable, Hashable, Sendable {
    /// `"Year 1"` when W4 told us the person's IB year.
    var classCode: String?
    /// Whatever the row printed under the name, verbatim.
    var rawInfo: String?
}

// MARK: - Entity

/// One person in the flat shape the non-directory screens still ask for.
///
/// Property order is load-bearing: `DirectoryStore.legacyEntity(_:)` uses the memberwise
/// initialiser.
struct DirectoryEntity: Codable, Identifiable, Equatable, Hashable, Sendable {
    let entityID: DirectoryEntityID
    let kind: DirectoryEntityKind
    /// The UWC id. W4 has no prefixed composite ids.
    let rawPrefixedID: String
    /// Always empty on W4.
    let rawPrefix: String
    /// The UWC id again — what the avatar lookups read.
    let numericID: String
    let name: String
    let subtitle: String?
    let rawLabel: String
    let normalizedName: String
    let searchTokens: [String]
    let isActive: Bool
    let rawTypeMarker: String?
    let metadata: DirectoryMetadata

    nonisolated var id: String { entityID.key }
    /// Every row W4 can produce is a person; kept so the bridge's callers read the same way.
    nonisolated var isPerson: Bool { true }
    nonisolated var classCode: String? { metadata.classCode }

    /// `{uwc_id}@uwcrcn.no` — derived, never scraped (README §6).
    nonisolated var email: String { "\(numericID)@uwcrcn.no" }

    nonisolated var displaySubtitle: String? {
        if let subtitle, !subtitle.isEmpty { return subtitle }
        if let info = metadata.rawInfo, !info.isEmpty { return info }
        return metadata.classCode
    }
}
