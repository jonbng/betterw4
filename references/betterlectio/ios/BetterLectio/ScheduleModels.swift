//
//  ScheduleModels.swift
//  BetterLectio
//
//  Created by Elliott Friedrich on 03/02/2026.
//

import Foundation

// MARK: - Schedule Models

struct ScheduleEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let startTime: String
    let endTime: String
    let teacher: String?
    let teacherId: String?
    let room: String?
    let status: EventStatus
    let date: Date
    let notes: String?
    let homework: String?
    let isAllDay: Bool

    init(
        id: String? = nil,
        title: String,
        subtitle: String,
        startTime: String,
        endTime: String,
        teacher: String? = nil,
        teacherId: String? = nil,
        room: String? = nil,
        status: EventStatus = .normal,
        date: Date,
        notes: String? = nil,
        homework: String? = nil,
        isAllDay: Bool = false
    ) {
        self.id = id ?? UUID().uuidString
        self.title = title
        self.subtitle = subtitle
        self.startTime = startTime
        self.endTime = endTime
        self.teacher = teacher
        self.teacherId = teacherId
        self.room = room
        self.status = status
        self.date = date
        self.notes = notes
        self.homework = homework
        self.isAllDay = isAllDay
    }
}

extension ScheduleEvent: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, title, subtitle, startTime, endTime, teacher, teacherId,
             room, status, date, notes, homework, isAllDay
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        subtitle = try c.decode(String.self, forKey: .subtitle)
        startTime = try c.decode(String.self, forKey: .startTime)
        endTime = try c.decode(String.self, forKey: .endTime)
        teacher = try c.decodeIfPresent(String.self, forKey: .teacher)
        teacherId = try c.decodeIfPresent(String.self, forKey: .teacherId)
        room = try c.decodeIfPresent(String.self, forKey: .room)
        status = try c.decode(EventStatus.self, forKey: .status)
        date = try c.decode(Date.self, forKey: .date)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        homework = try c.decodeIfPresent(String.self, forKey: .homework)
        isAllDay = (try? c.decode(Bool.self, forKey: .isAllDay)) ?? false
    }
}

enum EventStatus: String, Codable {
    case normal
    case cancelled
    case moved
    case changed

    var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .cancelled: return "Aflyst"  // Danish for "Cancelled"
        case .moved: return "Ændret"      // Danish for "Changed"
        case .changed: return "Ændret"
        }
    }
}

// MARK: - Lesson Content Models

struct LessonContent: Codable, Equatable {
    let teacherNote: String?
    let items: [LessonContentItem]

    var homework: [LessonContentItem] {
        items.filter { $0.isHomework }
    }

    var otherContent: [LessonContentItem] {
        items.filter { !$0.isHomework }
    }

    static let empty = LessonContent(teacherNote: nil, items: [])
}

struct LessonContentItem: Equatable, Identifiable {
    let id: String
    let title: String?
    let note: String?
    let blocks: [ContentBlock]
    let links: [LessonLink]
    let isHomework: Bool

    init(id: String, title: String?, note: String?, blocks: [ContentBlock],
         links: [LessonLink], isHomework: Bool) {
        self.id = id
        self.title = title
        self.note = note
        self.blocks = blocks
        self.links = links
        self.isHomework = isHomework
    }
}

extension LessonContentItem: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, title, note, blocks, links, isHomework
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(note, forKey: .note)
        try c.encode(blocks, forKey: .blocks)
        try c.encode(links, forKey: .links)
        try c.encode(isHomework, forKey: .isHomework)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        // Backward compat: old cached JSON has `body: String?` but no `blocks`
        blocks = (try? c.decode([ContentBlock].self, forKey: .blocks)) ?? []
        links = (try? c.decode([LessonLink].self, forKey: .links)) ?? []
        isHomework = (try? c.decode(Bool.self, forKey: .isHomework)) ?? true
    }
}

struct LessonLink: Codable, Equatable {
    let title: String
    let url: String
    let type: LessonLinkType
}

enum LessonLinkType: String, Codable {
    case file
    case external
}

// MARK: - Rich Content Blocks

enum InlineElement: Equatable {
    case text(String)
    case link(text: String, url: String, type: LessonLinkType)
    case image(url: String, alt: String)
}

extension InlineElement: Codable {
    private enum CodingKeys: String, CodingKey { case type, text, url, linkType, alt }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let s):
            try c.encode("text", forKey: .type)
            try c.encode(s, forKey: .text)
        case .link(let text, let url, let linkType):
            try c.encode("link", forKey: .type)
            try c.encode(text, forKey: .text)
            try c.encode(url, forKey: .url)
            try c.encode(linkType, forKey: .linkType)
        case .image(let url, let alt):
            try c.encode("image", forKey: .type)
            try c.encode(url, forKey: .url)
            try c.encode(alt, forKey: .alt)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try c.decode(String.self, forKey: .text))
        case "link":
            let linkTypeRaw = try c.decode(String.self, forKey: .linkType)
            let linkType = LessonLinkType(rawValue: linkTypeRaw) ?? .external
            self = .link(
                text: try c.decode(String.self, forKey: .text),
                url: try c.decode(String.self, forKey: .url),
                type: linkType
            )
        case "image":
            self = .image(
                url: try c.decode(String.self, forKey: .url),
                alt: (try? c.decode(String.self, forKey: .alt)) ?? ""
            )
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c,
                debugDescription: "Unknown InlineElement type: \(type)")
        }
    }
}

enum ContentBlock: Equatable {
    case heading(level: Int, inlines: [InlineElement])
    case paragraph(inlines: [InlineElement])
    case image(url: String, alt: String)
    case divider
}

extension ContentBlock: Codable {
    private enum CodingKeys: String, CodingKey { case type, level, inlines, url, alt }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .heading(let level, let inlines):
            try c.encode("heading", forKey: .type)
            try c.encode(level, forKey: .level)
            try c.encode(inlines, forKey: .inlines)
        case .paragraph(let inlines):
            try c.encode("paragraph", forKey: .type)
            try c.encode(inlines, forKey: .inlines)
        case .image(let url, let alt):
            try c.encode("image", forKey: .type)
            try c.encode(url, forKey: .url)
            try c.encode(alt, forKey: .alt)
        case .divider:
            try c.encode("divider", forKey: .type)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "heading":
            self = .heading(
                level: try c.decode(Int.self, forKey: .level),
                inlines: try c.decode([InlineElement].self, forKey: .inlines)
            )
        case "paragraph":
            self = .paragraph(inlines: try c.decode([InlineElement].self, forKey: .inlines))
        case "image":
            self = .image(
                url: try c.decode(String.self, forKey: .url),
                alt: (try? c.decode(String.self, forKey: .alt)) ?? ""
            )
        case "divider":
            self = .divider
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c,
                debugDescription: "Unknown ContentBlock type: \(type)")
        }
    }
}

// MARK: - Schedule Data

struct ScheduleData: Codable {
    let studentId: String
    let events: [ScheduleEvent]
    let lastUpdated: Date

    var eventsByDate: [Date: [ScheduleEvent]] {
        Dictionary(grouping: events) { event in
            Calendar.current.startOfDay(for: event.date)
        }
    }
}
