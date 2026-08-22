//
//  ClassRosterRepository.swift
//  BetterW4
//
//  People enrolled in one class, from `academics/classes/class&class_id=`.
//
//  W4 has no Lectio-style members.aspx. The class page is the roster: the same
//  `ul.user-list` / `a[href*=uwc_id]` shape as every other people list, parsed
//  by `W4PeopleParser`. Breakfast and assembly bricks have no class id, so
//  they return an empty list without touching the network.
//
//  Cache: `W4Surface.classes`, one key per class id. A missing roster never
//  fails the lesson sheet — the caller just sees no people.
//

import Foundation

actor ClassRosterRepository {

    static let shared = ClassRosterRepository()

    private let client: any W4SecondaryFetching
    private let cache: W4PageCache
    private let resolveContext: @Sendable () throws -> W4RequestContext

    init(
        client: any W4SecondaryFetching = W4HTTPClient(),
        cache: W4PageCache = .shared,
        resolveContext: @escaping @Sendable () throws -> W4RequestContext = {
            try W4RequestContext.require()
        }
    ) {
        self.client = client
        self.cache = cache
        self.resolveContext = resolveContext
    }

    /// People on this class page. Empty when the block is not a class, or when
    /// W4 answered with nothing we could parse. Demo returns the demo roster.
    func people(
        for event: TimetableEvent,
        forceRefresh: Bool = false
    ) async throws -> W4Loaded<[DirectoryPerson]> {
        let context = try resolveContext()
        if context.isDemo {
            return W4Loaded(Self.demoPeople(for: event), freshness: .demo)
        }

        guard let classId = ClassRoster.classId(from: event.href) else {
            return W4Loaded(Self.teacherFallback(for: event), freshness: .fresh)
        }
        return try await people(classId: classId, forceRefresh: forceRefresh)
    }

    func people(
        classId: String,
        forceRefresh: Bool = false
    ) async throws -> W4Loaded<[DirectoryPerson]> {
        let context = try resolveContext()
        if context.isDemo {
            return W4Loaded(DirectoryRepository.demoPeople, freshness: .demo)
        }
        let trimmed = classId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return W4Loaded([], freshness: .fresh)
        }

        let loaded = try await W4SecondaryPageLoader.loadHTML(
            surface: .classes,
            key: Self.cacheKey(trimmed),
            route: W4Routes.R.classPage,
            query: ["class_id": trimmed],
            forceRefresh: forceRefresh,
            priority: .important,
            context: context,
            client: client,
            cache: cache
        )
        return loaded.map { W4PeopleParser.parsePeople($0) }
    }

    nonisolated static func cacheKey(_ classId: String) -> String {
        "class-\(classId.lowercased())"
    }

    /// Demo: a teacher plus a couple of classmates, so the sheet is tappable
    /// without a network. Breakfast-style blocks stay empty.
    static func demoPeople(for event: TimetableEvent) -> [DirectoryPerson] {
        guard !event.isAllDay,
              event.source == .academics || event.source == .extraAcademics else {
            return []
        }
        let staff = DirectoryRepository.demoPeople.filter { $0.kind == .staff }
        let students = DirectoryRepository.demoPeople.filter { $0.kind == .student }
        return Array(staff.prefix(1)) + Array(students.prefix(3))
    }

    private static func teacherFallback(for event: TimetableEvent) -> [DirectoryPerson] {
        guard let id = event.teacherUwcId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !id.isEmpty else {
            return []
        }
        let name = event.teacher?.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            DirectoryPerson(
                uwcId: id.lowercased(),
                name: (name?.isEmpty == false) ? name! : id,
                kind: .staff,
                photoURL: W4PeopleParser.photoURL(forUWCId: id)
            )
        ]
    }
}
