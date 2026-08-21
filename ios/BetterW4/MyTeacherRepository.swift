//
//  MyTeacherRepository.swift
//  BetterW4
//
//  `people/students/staff` — the unfiltered My teachers / group leaders list.
//  Academics' "My teachers" (`&type=teachers`) is the same `ul.user-list` for
//  a student who has no separate leaders; Extra Academics' leaders page is
//  `&type=leaders`. This screen scrapes the combined page the user asked for.
//
//  Cache: `W4Surface.people`, TTL 7 days. One key. W4 is one Apache box.
//

import Foundation

actor MyTeacherRepository {

    static let shared = MyTeacherRepository()

    static let cacheKey = "myteachers"

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

    func load(
        forceRefresh: Bool = false,
        priority: FetchPriority = .important
    ) async throws -> W4Loaded<[MyTeacher]> {
        let context = try resolveContext()
        if context.isDemo {
            return W4Loaded(Self.demoTeachers, freshness: .demo)
        }
        let loaded = try await W4SecondaryPageLoader.loadHTML(
            surface: .people,
            key: Self.cacheKey,
            route: W4Routes.R.staff,
            forceRefresh: forceRefresh,
            priority: priority,
            context: context,
            client: client,
            cache: cache
        )
        return loaded.map(W4TeacherParser.parse)
    }

    func cached() async -> W4Loaded<[MyTeacher]>? {
        guard let context = try? resolveContext() else { return nil }
        if context.isDemo {
            return W4Loaded(Self.demoTeachers, freshness: .demo)
        }
        let cached = await W4SecondaryPageLoader.cachedHTML(
            surface: .people,
            key: Self.cacheKey,
            context: context,
            cache: cache
        )
        return cached?.map(W4TeacherParser.parse)
    }

    // MARK: - Demo

    /// Reuses the two demo staff so a profile tap lands on someone the rest of
    /// demo already knows, plus the invented IB roles from My classes.
    static var demoTeachers: [MyTeacher] {
        let staff = DirectoryRepository.demoPeople.filter { $0.kind == .staff }
        let advisor = staff.first
        let teacher = staff.dropFirst().first ?? staff.first

        func row(_ person: DirectoryPerson?, role: String, level: ClassLevel = .unknown) -> MyTeacher? {
            guard let person else { return nil }
            return MyTeacher(
                id: person.uwcId,
                name: person.displayName,
                role: role,
                level: level,
                photoURL: person.photoURL
            )
        }

        return [
            row(advisor, role: "Advisor group"),
            row(teacher, role: "English Language & Literature", level: .standard)
        ].compactMap { $0 }
    }
}
