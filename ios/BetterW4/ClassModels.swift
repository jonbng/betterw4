//
//  ClassModels.swift
//  BetterW4
//
//  Academic classes from `academics/classes/myclasses` and
//  `academics/classes/class&class_id=`.
//
//  Live capture 19 Aug 2026. The list is a `dl.class-list` of subject `<dt>`s
//  and one `a[href*=class_id]` per class. The class page is `dl.class-details`
//  (subject / year / block / level / room) plus `ul.student-list` under
//  Teacher and Students headings.
//

import Foundation

/// IB level as W4 prints it on My classes: a letter (`H`/`S`/`C`/`X`) plus a
/// word (`Higher`/`Standard`/`Combined`/`None`).
enum ClassLevel: String, Equatable, Hashable, Sendable, CaseIterable {
    case higher
    case standard
    case combined
    case none
    case unknown

    /// Badge shown in the UI: HL / SL / HL/SL. Empty when W4 has no IB level.
    var badge: String {
        switch self {
        case .higher: return "HL"
        case .standard: return "SL"
        case .combined: return "HL/SL"
        case .none, .unknown: return ""
        }
    }

    static func parse(_ raw: String?) -> ClassLevel {
        let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return .unknown }
        let compact = text.lowercased().filter(\.isLetter)
        // Combined first so "HL/SL" is not read as Higher from the leading H.
        if compact == "hlsl" || compact.hasPrefix("combined") { return .combined }
        if compact == "hl" || compact.hasPrefix("higher") { return .higher }
        if compact == "sl" || compact.hasPrefix("standard") { return .standard }
        if compact == "none" || compact == "x" { return .none }
        switch text.uppercased().first {
        case "H": return .higher
        case "S": return .standard
        case "C": return .combined
        case "X": return .none
        default: return .unknown
        }
    }
}

struct ClassRoom: Equatable, Hashable, Sendable {
    let id: String?
    let name: String

    init(id: String? = nil, name: String) {
        self.id = id
        self.name = name
    }
}

struct ClassMember: Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let kind: DirectoryPersonKind
    let photoURL: URL?
    let level: ClassLevel

    var person: DirectoryPerson {
        DirectoryPerson(
            uwcId: id,
            name: name,
            kind: kind,
            subtitle: level.badge.nilIfEmpty,
            photoURL: photoURL
        )
    }

    /// True when `id` is a real UWC id, so a profile page exists.
    var canOpenProfile: Bool {
        W4PeopleParser.uwcId(fromHref: "?uwc_id=\(id)") == id.lowercased()
    }

    init(
        id: String,
        name: String,
        kind: DirectoryPersonKind,
        photoURL: URL? = nil,
        level: ClassLevel = .unknown
    ) {
        self.id = id.lowercased()
        self.name = name
        self.kind = kind
        self.photoURL = photoURL
        self.level = level
    }
}

struct MyClass: Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let subject: String
    let subjectCode: String?
    let year: String?
    let block: String?
    let level: ClassLevel
    let levelLabel: String?
    let room: ClassRoom?
    let teachers: [ClassMember]
    let students: [ClassMember]
    /// False on the My classes index (caption only); true after the class page.
    let loaded: Bool

    var teacherNames: String {
        teachers.map(\.name).joined(separator: ", ")
    }

    var displayLevel: String {
        let badge = level.badge
        return badge.isEmpty ? (levelLabel ?? "") : badge
    }

    var subtitle: String? {
        let parts = [
            teacherNames.nilIfEmpty,
            room?.name.nilIfEmpty
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var meta: String? {
        var parts: [String] = []
        if let year, !year.isEmpty { parts.append("Year \(year)") }
        if let block, !block.isEmpty { parts.append("Block \(block)") }
        if loaded { parts.append(students.count == 1 ? "1 student" : "\(students.count) students") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    init(
        id: String,
        subject: String,
        subjectCode: String? = nil,
        year: String? = nil,
        block: String? = nil,
        level: ClassLevel = .unknown,
        levelLabel: String? = nil,
        room: ClassRoom? = nil,
        teachers: [ClassMember] = [],
        students: [ClassMember] = [],
        loaded: Bool = false
    ) {
        self.id = id
        self.subject = subject
        self.subjectCode = subjectCode
        self.year = year
        self.block = block
        self.level = level
        self.levelLabel = levelLabel
        self.room = room
        self.teachers = teachers
        self.students = students
        self.loaded = loaded
    }
}
