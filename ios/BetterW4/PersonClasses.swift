//
//  PersonClasses.swift
//  BetterW4
//
//  Academic classes a student is enrolled in.
//
//  Another student's public profile (`people/students/student&uwc_id=`) lists
//  their classes. `myclasses` / `mytimetable&uwc_id=` always returns the
//  signed-in student, so the profile page is the source of truth. The week
//  helper below is kept for callers that only have a timetable.
//

import Foundation

/// One academic class a student is in. `classId` is W4's `class_id` when the
/// profile (or a timetable brick) linked `academics/classes/class` — that is
/// what opens the roster page.
struct PersonClass: Equatable, Hashable, Identifiable, Sendable {
    let classId: String?
    let name: String
    let year: String?
    let levelLabel: String?
    let teacher: String?
    let room: String?

    var id: String { classId?.lowercased() ?? "name:\(name.lowercased())" }
    var canOpen: Bool { classId?.isEmpty == false }

    var subtitle: String? {
        let parts = [
            year.map { $0.hasPrefix("Year") ? $0 : "Year \($0)" },
            levelLabel.flatMap { $0.isEmpty ? nil : $0 },
            teacher.flatMap { $0.isEmpty ? nil : $0 },
            room.flatMap { $0.isEmpty ? nil : $0 }
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    init(
        classId: String?,
        name: String,
        year: String? = nil,
        levelLabel: String? = nil,
        teacher: String? = nil,
        room: String? = nil
    ) {
        self.classId = classId
        self.name = name
        self.year = year
        self.levelLabel = levelLabel
        self.teacher = teacher
        self.room = room
    }
}

enum PersonClasses {
    private static let skipTitles: Set<String> = [
        "breakfast", "lunch", "dinner", "assembly", "tutorial",
        "study hall", "studyhall"
    ]

    static func from(week: ScheduleWeek) -> [PersonClass] {
        var linked: [String: PersonClass] = [:]
        var linkedOrder: [String] = []
        var fallback: [String: PersonClass] = [:]
        var fallbackOrder: [String] = []

        for event in week.allEvents {
            let name = event.subject.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            if let classId = ClassRoster.classId(from: event.href) {
                let key = classId.lowercased()
                if linked[key] == nil {
                    linked[key] = PersonClass(classId: classId, name: name)
                    linkedOrder.append(key)
                }
                continue
            }
            let key = name.lowercased()
            if event.source == .academics, !event.isAllDay, !skipTitles.contains(key) {
                if fallback[key] == nil {
                    fallback[key] = PersonClass(classId: nil, name: name)
                    fallbackOrder.append(key)
                }
            }
        }
        let source = linked.isEmpty
            ? fallbackOrder.compactMap { fallback[$0] }
            : linkedOrder.compactMap { linked[$0] }
        return source.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func merge(_ existing: [PersonClass], _ incoming: [PersonClass]) -> [PersonClass] {
        var seen: [String: PersonClass] = [:]
        var order: [String] = []
        for item in existing + incoming {
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let key = item.classId?.lowercased() ?? "name:\(name.lowercased())"
            if let previous = seen[key] {
                seen[key] = PersonClass(
                    classId: previous.classId ?? item.classId,
                    name: Self.preferName(previous.name, name),
                    year: previous.year ?? item.year,
                    levelLabel: previous.levelLabel ?? item.levelLabel,
                    teacher: previous.teacher ?? item.teacher,
                    room: previous.room ?? item.room
                )
            } else {
                seen[key] = PersonClass(
                    classId: item.classId,
                    name: name,
                    year: item.year,
                    levelLabel: item.levelLabel,
                    teacher: item.teacher,
                    room: item.room
                )
                order.append(key)
            }
        }
        return order.compactMap { seen[$0] }.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func preferName(_ existing: String, _ incoming: String) -> String {
        let a = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        if b.isEmpty { return a }
        if a.isEmpty { return b }
        if a.contains(":") && !b.contains(":") { return b }
        if b.contains(":") && !a.contains(":") { return a }
        return b.count > a.count ? b : a
    }

    /// `"1EA16CECOX: Economics 1st Year C level in room A 1.6"`
    static func parseCaption(_ caption: String) -> (
        code: String,
        subject: String,
        year: String?,
        levelLabel: String?,
        room: String?
    )? {
        let clean = caption.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard let match = firstCapture(
            #"^([A-Za-z0-9]+):\s*(.+?)\s+(\d+)\s*(?:st|nd|rd|th)?\s*Year\s+([A-Z])\s+level(?:\s+with\s+.+?)?(?:\s+in room\s+(.+))?$"#,
            in: clean,
            groups: 5
        ) else { return nil }
        let code = match[0]
        let subject = match[1]
        let year = match[2].isEmpty ? nil : match[2]
        let levelLabel: String?
        switch match[3].uppercased() {
        case "H": levelLabel = "HL"
        case "S": levelLabel = "SL"
        case "C": levelLabel = "HL/SL"
        default: levelLabel = nil
        }
        let room = match[4].isEmpty ? nil : match[4]
        guard !code.isEmpty, !subject.isEmpty else { return nil }
        return (code, subject, year, levelLabel, room)
    }

    private static func firstCapture(_ pattern: String, in text: String, groups: Int) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > groups else { return nil }
        var result: [String] = []
        for index in 1...groups {
            guard let captured = Range(match.range(at: index), in: text) else {
                result.append("")
                continue
            }
            result.append(String(text[captured]))
        }
        return result
    }
}