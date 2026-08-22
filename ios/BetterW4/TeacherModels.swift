//
//  TeacherModels.swift
//  BetterW4
//
//  The signed-in student's teachers and group leaders from
//  `people/students/staff`. Each row is a staff profile plus the role caption
//  W4 prints under the name (`Core meetings`, `Economics`, `… HL`).
//
//  Live capture 21 Aug 2026. The page is a filter form and a `ul.user-list` of
//  photo + name anchors. Staff ids are not always `nc…`.
//

import Foundation

struct MyTeacher: Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    /// Caption under the name, with a trailing HL/SL already stripped.
    let role: String?
    let level: ClassLevel
    let photoURL: URL?

    var person: DirectoryPerson {
        DirectoryPerson(
            uwcId: id,
            name: name,
            kind: .staff,
            subtitle: role,
            photoURL: photoURL
        )
    }

    var displayLevel: String { level.badge }

    init(
        id: String,
        name: String,
        role: String? = nil,
        level: ClassLevel = .unknown,
        photoURL: URL? = nil
    ) {
        self.id = id.lowercased()
        self.name = name
        self.role = role
        self.level = level
        self.photoURL = photoURL
    }
}
