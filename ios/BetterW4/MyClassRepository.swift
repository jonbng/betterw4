//
//  MyClassRepository.swift
//  BetterW4
//
//  `academics/classes/myclasses` plus one `academics/classes/class&class_id=`
//  page per class. The class page is also the roster, so the cache key is
//  shared with `ClassRosterRepository`.
//
//  Cache: `W4Surface.classes`, TTL 30 minutes. The index is one key; each
//  class page is its own. Requests stay sequential — W4 is one Apache box.
//

import Foundation

actor MyClassRepository {

    static let shared = MyClassRepository()

    static let indexCacheKey = "myclasses"

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

    // MARK: - Reading

    func loadIndex(
        forceRefresh: Bool = false,
        priority: FetchPriority = .important
    ) async throws -> W4Loaded<[MyClass]> {
        let context = try resolveContext()
        if context.isDemo {
            return W4Loaded(Self.demoClasses.map { Self.unloaded($0) }, freshness: .demo)
        }
        let loaded = try await W4SecondaryPageLoader.loadHTML(
            surface: .classes,
            key: Self.indexCacheKey,
            route: W4Routes.R.myClasses,
            forceRefresh: forceRefresh,
            priority: priority,
            context: context,
            client: client,
            cache: cache
        )
        return loaded.map(W4ClassParser.parseIndex)
    }

    func loadClass(
        id classId: String,
        forceRefresh: Bool = false,
        priority: FetchPriority = .important
    ) async throws -> W4Loaded<MyClass> {
        let context = try resolveContext()
        let trimmed = classId.trimmingCharacters(in: .whitespacesAndNewlines)
        if context.isDemo {
            let match = Self.demoClasses.first { $0.id.caseInsensitiveCompare(trimmed) == .orderedSame }
                ?? MyClass(id: trimmed, subject: trimmed, loaded: true)
            return W4Loaded(match, freshness: .demo)
        }
        guard !trimmed.isEmpty else {
            return W4Loaded(MyClass(id: trimmed, subject: trimmed, loaded: true), freshness: .fresh)
        }
        let loaded = try await W4SecondaryPageLoader.loadHTML(
            surface: .classes,
            key: ClassRosterRepository.cacheKey(trimmed),
            route: W4Routes.R.classPage,
            query: ["class_id": trimmed],
            forceRefresh: forceRefresh,
            priority: priority,
            context: context,
            client: client,
            cache: cache
        )
        return loaded.map { W4ClassParser.parseClass($0, classId: trimmed) }
    }

    func cachedIndex() async -> W4Loaded<[MyClass]>? {
        guard let context = try? resolveContext() else { return nil }
        if context.isDemo {
            return W4Loaded(Self.demoClasses.map { Self.unloaded($0) }, freshness: .demo)
        }
        let cached = await W4SecondaryPageLoader.cachedHTML(
            surface: .classes,
            key: Self.indexCacheKey,
            context: context,
            cache: cache
        )
        return cached?.map(W4ClassParser.parseIndex)
    }

    func cachedClass(id classId: String) async -> W4Loaded<MyClass>? {
        guard let context = try? resolveContext() else { return nil }
        let trimmed = classId.trimmingCharacters(in: .whitespacesAndNewlines)
        if context.isDemo {
            let match = Self.demoClasses.first { $0.id.caseInsensitiveCompare(trimmed) == .orderedSame }
                ?? MyClass(id: trimmed, subject: trimmed, loaded: true)
            return W4Loaded(match, freshness: .demo)
        }
        let cached = await W4SecondaryPageLoader.cachedHTML(
            surface: .classes,
            key: ClassRosterRepository.cacheKey(trimmed),
            context: context,
            cache: cache
        )
        return cached?.map { W4ClassParser.parseClass($0, classId: trimmed) }
    }

    // MARK: - Demo

    /// Invented IB classes that reuse the one demo roster, so a profile tap
    /// from My classes lands on a person the rest of demo already knows.
    static var demoClasses: [MyClass] {
        let people = DirectoryRepository.demoPeople
        let students = people.filter { $0.kind == .student }
        let staff = people.filter { $0.kind == .staff }
        let mathTeacher = staff.first
        let englishTeacher = staff.dropFirst().first ?? staff.first
        let demoId = DemoDataProvider.uwcId

        func member(_ person: DirectoryPerson, level: ClassLevel = .unknown) -> ClassMember {
            ClassMember(
                id: person.uwcId,
                name: person.displayName,
                kind: person.kind,
                photoURL: nil,
                level: level
            )
        }

        func members(ids: [String], levels: [String: ClassLevel] = [:]) -> [ClassMember] {
            let ordered = ids.compactMap { id in
                students.first { $0.uwcId == id }
            }
            let withDemo = ordered.contains(where: { $0.uwcId == demoId })
                ? ordered
                : (students.first { $0.uwcId == demoId }.map { [$0] } ?? []) + ordered
            return withDemo.map { member($0, level: levels[$0.uwcId] ?? .unknown) }
        }

        return [
            MyClass(
                id: "1DA13HMTAA",
                subject: "Mathematics Analysis and Approaches",
                subjectCode: "MTAA",
                year: "1",
                block: "D",
                level: .higher,
                levelLabel: "HL",
                room: ClassRoom(id: "a13", name: "A 1.3"),
                teachers: mathTeacher.map { [member($0)] } ?? [],
                students: members(ids: ["nc00aaa", "nc00ddd", "nc00ggg", "nc00iii"]),
                loaded: true
            ),
            MyClass(
                id: "1YA25SLALI",
                subject: "English Language & Literature",
                subjectCode: "LALI",
                year: "1",
                block: "Y",
                level: .standard,
                levelLabel: "SL",
                room: ClassRoom(id: "a25", name: "A 2.5"),
                teachers: englishTeacher.map { [member($0)] } ?? [],
                students: members(ids: ["nc00aaa", "nc00bbb", "nc00eee", "nc00hhh"]),
                loaded: true
            ),
            MyClass(
                id: "1EA16CECOX",
                subject: "Economics",
                subjectCode: "ECOX",
                year: "1",
                block: "E",
                level: .combined,
                levelLabel: "Combined",
                room: ClassRoom(id: "a16", name: "A 1.6"),
                teachers: mathTeacher.map { [member($0)] } ?? [],
                students: members(
                    ids: ["nc00aaa", "nc00bbb", "nc00ddd", "nc00eee"],
                    levels: [
                        "nc00aaa": .higher,
                        "nc00bbb": .standard,
                        "nc00ddd": .higher,
                        "nc00eee": .standard
                    ]
                ),
                loaded: true
            ),
            MyClass(
                id: "1ZAUDXCORE",
                subject: "Core meetings",
                subjectCode: "CORE",
                year: "1",
                block: "Z",
                level: .none,
                room: ClassRoom(id: "aud", name: "Auditorium"),
                teachers: englishTeacher.map { [member($0)] } ?? [],
                students: students.prefix(8).map { member($0) },
                loaded: true
            )
        ]
    }

    private static func unloaded(_ item: MyClass) -> MyClass {
        MyClass(
            id: item.id,
            subject: item.subject,
            subjectCode: item.subjectCode,
            year: item.year,
            block: item.block,
            level: item.level,
            levelLabel: item.levelLabel,
            room: item.room,
            teachers: item.teachers,
            students: [],
            loaded: false
        )
    }
}
