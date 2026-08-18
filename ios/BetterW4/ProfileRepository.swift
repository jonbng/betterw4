//
//  ProfileRepository.swift
//  BetterW4
//
//  Public profiles — `people/students/student&uwc_id=`, `people/staff/staff&uwc_id=` — and the
//  signed-in student's own `site/profile` (plan Wave 5 item 5.5, `features.md` §1.12).
//
//  Everything here resolves by UWC id. There is no numeric person id on W4 and no per-school
//  scope, so the id in the URL is the id in the cache key is the id in the store.
//
//  Cache: `W4Surface.profile`, TTL from `CachePolicy` (1 h).
//
//  PII: names and UWC ids are never logged.
//

import Foundation
import OSLog

actor ProfileRepository {

    static let shared = ProfileRepository()

    private let fetcher: W4PeopleFetching
    private let cache: W4PageCache
    private let store: W4PeopleStoring
    private let contextProvider: @Sendable () throws -> W4RequestContext

    private let log = Logger(subsystem: "dk.jonathanb.w4", category: "ProfileRepository")

    init(
        fetcher: W4PeopleFetching = W4PeopleHTTPFetcher(),
        cache: W4PageCache = .shared,
        store: W4PeopleStoring = DirectoryStoreBridge(),
        context: @escaping @Sendable () throws -> W4RequestContext = { try W4RequestContext.require() }
    ) {
        self.fetcher = fetcher
        self.cache = cache
        self.store = store
        self.contextProvider = context
    }

    // MARK: - Keys

    static func cacheKey(uwcId: String) -> String {
        "person:\(DirectoryRepository.normalizedUwcId(uwcId))"
    }

    /// The signed-in student's own profile lives at a route with no `uwc_id`, so it gets its own
    /// key rather than sharing the by-id namespace.
    static let myProfileCacheKey = "me"

    // MARK: - Cache-first read

    /// The stored copy, with no network call, so a profile sheet can paint before it refreshes.
    func cachedProfile(uwcId: String) async -> W4Loaded<DirectoryPersonProfile>? {
        guard let context = try? contextProvider() else { return nil }
        let id = DirectoryRepository.normalizedUwcId(uwcId)
        if context.isDemo {
            return Self.demoProfile(uwcId: id).map { W4Loaded($0, freshness: .demo) }
        }
        guard let page = await cache.page(
            surface: .profile,
            key: Self.cacheKey(uwcId: id),
            uwcId: context.uwcId
        ) else { return nil }
        guard let profile = W4PeopleParser.parseProfile(page.html) else { return nil }
        return W4Loaded(profile, freshness: .cached(fetchedAt: page.fetchedAt, isStale: page.isStale))
    }

    // MARK: - One profile

    /// A public profile, cache-first.
    ///
    /// - Parameter kind: the route to use. When the caller does not know, the store is asked
    ///   (a directory row already recorded student-vs-staff from *its own* href), and only as a
    ///   last resort are both routes tried in turn. Guessing from the page itself is what
    ///   `W4PeopleParser` does *after* the fetch; guessing before it would just pick a URL.
    func profile(
        uwcId rawUwcId: String,
        kind: DirectoryPersonKind? = nil,
        forceRefresh: Bool = false,
        priority: FetchPriority = .important
    ) async throws -> W4Loaded<DirectoryPersonProfile> {
        let context = try contextProvider()
        let uwcId = DirectoryRepository.normalizedUwcId(rawUwcId)
        guard !uwcId.isEmpty else { throw W4Error.parsingError("A profile needs a uwc id") }

        if context.isDemo {
            guard let profile = Self.demoProfile(uwcId: uwcId) else {
                throw W4Error.parsingError("No demo profile for that person")
            }
            return W4Loaded(profile, freshness: .demo)
        }

        let key = Self.cacheKey(uwcId: uwcId)
        let cached = await cache.page(surface: .profile, key: key, uwcId: context.uwcId)

        if !forceRefresh, let cached, !cached.isStale,
           let profile = W4PeopleParser.parseProfile(cached.html) {
            return W4Loaded(profile, freshness: .cached(fetchedAt: cached.fetchedAt, isStale: false))
        }

        do {
            let profile = try await fetchProfile(
                uwcId: uwcId,
                kind: kind,
                priority: priority,
                context: context,
                cacheKey: key
            )
            await store.upsert([profile.person])
            return W4Loaded(profile, freshness: .fresh)
        } catch {
            try DirectoryRepository.rethrowIfFatal(error)
            guard let cached, let profile = W4PeopleParser.parseProfile(cached.html) else { throw error }
            log.warning("Profile fetch failed; serving the cached copy instead.")
            return W4Loaded(profile, freshness: .cached(fetchedAt: cached.fetchedAt, isStale: true))
        }
    }

    // MARK: - My own profile

    /// `site/profile` — the signed-in student's own page.
    func myProfile(
        forceRefresh: Bool = false,
        priority: FetchPriority = .important
    ) async throws -> W4Loaded<DirectoryPersonProfile> {
        let context = try contextProvider()

        if context.isDemo {
            guard let profile = Self.demoProfile(uwcId: Self.demoOwnUwcId) else {
                throw W4Error.parsingError("No demo profile")
            }
            return W4Loaded(profile, freshness: .demo)
        }

        let key = Self.myProfileCacheKey
        let cached = await cache.page(surface: .profile, key: key, uwcId: context.uwcId)

        if !forceRefresh, let cached, !cached.isStale,
           let profile = W4PeopleParser.parseProfile(cached.html) {
            return W4Loaded(profile, freshness: .cached(fetchedAt: cached.fetchedAt, isStale: false))
        }

        do {
            let result = try await fetcher.fetchPage(
                route: W4Routes.R.profile,
                query: [:],
                priority: priority,
                credentials: context.credentials,
                uwcId: context.uwcId
            )
            await cache.store(
                html: result.html,
                surface: .profile,
                key: key,
                uwcId: context.uwcId,
                finalURL: result.finalURL,
                contentType: "text/html"
            )
            guard let profile = W4PeopleParser.parseProfile(result.html) else {
                throw W4Error.parsingError("site/profile carried no recognisable uwc id")
            }
            await store.upsert([profile.person])
            return W4Loaded(profile, freshness: .fresh)
        } catch {
            try DirectoryRepository.rethrowIfFatal(error)
            guard let cached, let profile = W4PeopleParser.parseProfile(cached.html) else { throw error }
            log.warning("Own-profile fetch failed; serving the cached copy instead.")
            return W4Loaded(profile, freshness: .cached(fetchedAt: cached.fetchedAt, isStale: true))
        }
    }

    // MARK: - Route resolution

    /// Fetches the profile page, caching only the response we actually managed to parse.
    ///
    /// When the kind is unknown both routes are tried in order. A wrong guess on W4 answers with
    /// either a 403 or a page with no `uwc_id` on it, and neither is a dead session — so the first
    /// attempt's failure is remembered and only rethrown if the second one fails too.
    private func fetchProfile(
        uwcId: String,
        kind: DirectoryPersonKind?,
        priority: FetchPriority,
        context: W4RequestContext,
        cacheKey: String
    ) async throws -> DirectoryPersonProfile {
        let candidates: [DirectoryPersonKind]
        if let kind {
            candidates = [kind]
        } else if let known = await store.person(uwcId: uwcId) {
            candidates = [known.kind]
        } else {
            candidates = [.student, .staff]
        }

        var firstError: Error?
        for candidate in candidates {
            do {
                let result = try await fetcher.fetchPage(
                    route: candidate.profileRoute,
                    query: ["uwc_id": uwcId],
                    priority: priority,
                    credentials: context.credentials,
                    uwcId: context.uwcId
                )
                guard let profile = W4PeopleParser.parseProfile(result.html, kind: candidate) else {
                    firstError = firstError ?? W4Error.parsingError("Profile page carried no uwc id")
                    continue
                }
                // Only a page we could actually read is worth keeping: caching an unparseable
                // body would make every later cache-first read fall straight through anyway.
                await cache.store(
                    html: result.html,
                    surface: .profile,
                    key: cacheKey,
                    uwcId: context.uwcId,
                    finalURL: result.finalURL,
                    contentType: "text/html"
                )
                return profile
            } catch {
                try DirectoryRepository.rethrowIfFatal(error)
                firstError = firstError ?? error
            }
        }
        throw firstError ?? W4Error.parsingError("Profile page could not be read")
    }
}

// MARK: - Demo data

extension ProfileRepository {

    /// The demo session's own UWC id. Invented, and outside any real cohort's range.
    static let demoOwnUwcId = "nc00aaa"

    static func demoProfile(uwcId: String) -> DirectoryPersonProfile? {
        let id = DirectoryRepository.normalizedUwcId(uwcId)
        guard let person = DirectoryRepository.demoPeople.first(where: { $0.uwcId == id }) else {
            return nil
        }
        var fields: [PersonProfileField] = [
            PersonProfileField(label: "UWC id", value: person.uwcId),
            PersonProfileField(label: "Name", value: person.name),
            PersonProfileField(label: "Email", value: person.email)
        ]
        if let country = person.country {
            fields.append(PersonProfileField(label: "Country", value: country))
        }
        if let house = person.house {
            fields.append(PersonProfileField(label: "House", value: house))
        }
        if let year = person.year {
            fields.append(PersonProfileField(label: "Year", value: year))
        }
        return DirectoryPersonProfile(
            person: person,
            birthday: person.kind == .student ? "1 January" : nil,
            lastLogin: nil,
            scrapedEmail: person.email,
            fields: fields
        )
    }
}
