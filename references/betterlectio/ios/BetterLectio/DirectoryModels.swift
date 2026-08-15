//
//  DirectoryModels.swift
//  BetterLectio
//

import Foundation

enum DirectoryEntityKind: String, Codable, CaseIterable, Sendable {
    case student
    case teacher
    case classSynthetic
    case classLectio
    case hold
    case room
    case resource
    case group
    case other

    nonisolated var displayName: String {
        switch self {
        case .student: return "Elev"
        case .teacher: return "Lærer"
        case .classSynthetic: return "Klasse"
        case .classLectio: return "Lectio-klasse"
        case .hold: return "Hold"
        case .room: return "Lokale"
        case .resource: return "Ressource"
        case .group: return "Gruppe"
        case .other: return "Andet"
        }
    }

    nonisolated var hasSchedule: Bool {
        switch self {
        case .student, .teacher, .room, .resource:
            return true
        case .classSynthetic, .classLectio, .hold, .group, .other:
            return false
        }
    }

    nonisolated var hasMembers: Bool {
        switch self {
        case .classSynthetic, .hold:
            return true
        case .student, .teacher, .classLectio, .room, .resource, .group, .other:
            return false
        }
    }

    nonisolated var hasAvatar: Bool {
        self == .student || self == .teacher
    }

    nonisolated var canMessage: Bool {
        switch self {
        case .student, .teacher, .group:
            return true
        case .classSynthetic, .classLectio, .hold, .room, .resource, .other:
            return false
        }
    }

    nonisolated var isPerson: Bool {
        self == .student || self == .teacher
    }
}

enum DirectoryGroupSubtype: String, Codable, CaseIterable, Sendable {
    case builtin
    case user
    case classStudents
    case classTeachers
    case yearStudents
    case yearTeachers
    case other
}

struct DirectoryEntityID: Codable, Equatable, Hashable, Sendable {
    let gymId: Int
    let kind: DirectoryEntityKind
    let rawID: String

    nonisolated var key: String {
        "\(gymId)|\(kind.rawValue)|\(rawID)"
    }
}

struct DirectoryMetadata: Codable, Equatable, Hashable, Sendable {
    var classCode: String?
    var seatNumber: String?
    var abbreviation: String?
    var shortCode: String?
    var subjectCode: String?
    var yearCode: String?
    var groupSubtype: DirectoryGroupSubtype?
    var linkedBuiltinGroupID: String?
    var linkedLectioClassID: String?
    var rawInfo: String?
}

struct DirectoryEntity: Codable, Identifiable, Equatable, Hashable, Sendable {
    let entityID: DirectoryEntityID
    let gymId: Int
    let kind: DirectoryEntityKind
    let rawPrefixedID: String
    let rawPrefix: String
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
    nonisolated var hasSchedule: Bool { kind.hasSchedule }
    nonisolated var hasMembers: Bool { kind.hasMembers }
    nonisolated var hasAvatar: Bool { kind.hasAvatar }
    nonisolated var canMessage: Bool { kind.canMessage }
    nonisolated var isPerson: Bool { kind.isPerson }
    nonisolated var classCode: String? { metadata.classCode }
    nonisolated var seatNumber: String? { metadata.seatNumber }
    nonisolated var abbreviation: String? { metadata.abbreviation }
    nonisolated var shortCode: String? { metadata.shortCode }
    nonisolated var subjectCode: String? { metadata.subjectCode }
    nonisolated var groupSubtype: DirectoryGroupSubtype? { metadata.groupSubtype }

    nonisolated var displaySubtitle: String? {
        if let subtitle, !subtitle.isEmpty {
            return subtitle
        }

        switch kind {
        case .student:
            return metadata.classCode
        case .teacher:
            return metadata.abbreviation
        case .classSynthetic:
            return "Klasse"
        case .classLectio:
            return "Lectio-klasse"
        case .hold:
            return metadata.subjectCode
        case .room:
            return metadata.shortCode
        case .resource:
            return metadata.shortCode
        case .group:
            return metadata.groupSubtype?.rawValue
        case .other:
            return nil
        }
    }

    nonisolated var schedulableTarget: SchedulableTarget? {
        guard hasSchedule else { return nil }

        let kind: SchedulableTargetKind
        switch self.kind {
        case .student:
            kind = .student
        case .teacher:
            kind = .teacher
        case .room:
            kind = .room
        case .resource:
            kind = .resource
        case .classSynthetic, .classLectio, .hold, .group, .other:
            return nil
        }

        return SchedulableTarget(
            kind: kind,
            id: numericID,
            displayName: name,
            gymId: gymId
        )
    }

    nonisolated func asMessageRecipient() -> MessageRecipient? {
        guard canMessage else { return nil }

        let type: RecipientType
        switch kind {
        case .student:
            type = .student
        case .teacher:
            type = .teacher
        case .group:
            type = .group
        case .classSynthetic, .classLectio, .hold, .room, .resource, .other:
            return nil
        }

        return MessageRecipient(
            id: rawPrefixedID,
            name: name,
            type: type,
            info: displaySubtitle,
            lectioRecipientID: rawPrefixedID
        )
    }
}

enum SchedulableTargetKind: String, Codable, Hashable, Sendable {
    case student
    case teacher
    case room
    case resource

    nonisolated var iconName: String {
        switch self {
        case .student: return "person.fill"
        case .teacher: return "person.text.rectangle.fill"
        case .room: return "door.left.hand.closed"
        case .resource: return "shippingbox.fill"
        }
    }
}

struct SchedulableTarget: Codable, Hashable, Sendable {
    let kind: SchedulableTargetKind
    let id: String
    let displayName: String
    let gymId: Int

    nonisolated var storageKey: String {
        "\(kind.rawValue):\(id)"
    }

    nonisolated var displayKindName: String {
        switch kind {
        case .student: return "Elev"
        case .teacher: return "Lærer"
        case .room: return "Lokale"
        case .resource: return "Ressource"
        }
    }
}

struct RawDirectoryItem: Codable, Equatable, Hashable, Sendable {
    let gymId: Int
    let rawLabel: String
    let rawPrefixedID: String
    let prefix: String
    let numericID: String
    let isActive: Bool
    let rawTypeMarker: String?
}

struct ParsedHoldMember: Equatable, Hashable, Sendable {
    let entity: DirectoryEntity
    let pictureID: String?
}
