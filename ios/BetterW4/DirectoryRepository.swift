//
//  DirectoryRepository.swift
//  BetterW4
//
//  The people directory between `W4PeopleParser` and the transport (plan Wave 5 item 5.5,
//  `docs/spec/features.md` §1.12 and §2.1).
//
//  Three things make this file different from the Lectio directory it replaces:
//
//    1. **`uwcId` is the key.** W4 has no numeric person id, no `gymId` and no nine-case entity
//       taxonomy — one host, one school, people and rooms. Every lookup here is a UWC id.
//    2. **The sweep is deliberately slow.** ~200 students plus staff is a lot of pages for one
//       small Apache box (README §5.5), so `syncFullDirectory` walks its sources strictly one at a
//       time and every one of its requests is `.opportunistic`. A greedy sweep would sit in front
//       of the screen the student is actually looking at, because all W4 traffic shares a single
//       serial gate.
//    3. **Photos are derived, never fetched.** W4 serves `{uwc_id}.jpg`; there is no
//       `pictureId` to look up and therefore no per-person request to make.
//
//  Cache: `W4Surface.people`, TTL 7 days — the number lives in `CachePolicy`, never here.
//
//  PII: names and UWC ids are never logged. Every log line below counts rows.
//

import Foundation
import OSLog

// MARK: - Transport seam

/// One fetched W4 page.
struct W4PeopleFetchResult: Sendable {
    let html: String
    let finalURL: URL

    init(html: String, finalURL: URL) {
        self.html = html
        self.finalURL = finalURL
    }
}

/// Everything `DirectoryRepository` and `ProfileRepository` need from the network.
///
/// It exists so the repositories can be unit-tested against a stub without anybody having to
/// modify `W4HTTPClient` to make them testable (Wave 5 rule 6).
protocol W4PeopleFetching: Sendable {
    func fetchPage(
        route: String,
        query: [String: String],
        priority: FetchPriority,
        credentials: W4Credentials,
        uwcId: String
    ) async throws -> W4PeopleFetchResult
}

/// The live implementation: a plain `W4HTTPClient` GET.
///
/// The client is created per call on purpose — it is a thin wrapper around a shared `URLSession`
/// and a process-global serial gate, so there is nothing to keep alive between requests, and a
/// value type keeps this `Sendable` without an unchecked escape hatch.
struct W4PeopleHTTPFetcher: W4PeopleFetching {

    init() {}

    func fetchPage(
        route: String,
        query: [String: String],
        priority: FetchPriority,
        credentials: W4Credentials,
        uwcId: String
    ) async throws -> W4PeopleFetchResult {
        let client = W4HTTPClient()
        let response = try await client.get(
            route: route,
            query: query,
            credentials: credentials,
            studentId: uwcId,
            priority: priority
        )
        return W4PeopleFetchResult(
            html: client.decodeHTML(from: response.data),
            finalURL: response.finalURL
        )
    }
}

// MARK: - Persistence seam

/// The slice of `DirectoryStore` the repositories touch, so tests can watch what was written
/// without standing up a SwiftData container.
protocol W4PeopleStoring: Sendable {
    /// Replaces the whole people table. Used by the full sweep only.
    func replaceAll(_ people: [DirectoryPerson]) async
    /// Merges rows in without deleting anybody. Used by single-page loads and profiles.
    func upsert(_ people: [DirectoryPerson]) async
    func allPeople() async -> [DirectoryPerson]
    func person(uwcId: String) async -> DirectoryPerson?
}

/// Forwards to the app's real `DirectoryStore`.
struct DirectoryStoreBridge: W4PeopleStoring {

    init() {}

    func replaceAll(_ people: [DirectoryPerson]) async {
        await DirectoryStore.shared.replacePeople(people)
    }

    func upsert(_ people: [DirectoryPerson]) async {
        await DirectoryStore.shared.upsertPeople(people)
    }

    func allPeople() async -> [DirectoryPerson] {
        await DirectoryStore.shared.allPeopleAsync()
    }

    func person(uwcId: String) async -> DirectoryPerson? {
        await DirectoryStore.shared.personAsync(uwcId: uwcId)
    }
}

// MARK: - Pins

/// Pinned people, scoped to the signed-in UWC id so a second account on the same device never
/// inherits the first one's pins (`features.md` §1.12, key shape kept from
/// `DirectoryViewModel.pinnedKey`).
///
/// Reading is deliberately forgiving: the pre-W4 build stored Lectio composite ids
/// (`"131|student|S123"`) under the same key, and a pin the store cannot understand is dropped
/// rather than crashed on.
struct DirectoryPinStore: @unchecked Sendable {

    /// `UserDefaults` is documented as thread-safe; the struct is otherwise stateless.
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func key(forOwner ownerUwcId: String) -> String {
        "w4.directory.pinned.\(ownerUwcId.lowercased())"
    }

    func pinned(owner ownerUwcId: String) -> Set<String> {
        let raw = defaults.stringArray(forKey: Self.key(forOwner: ownerUwcId)) ?? []
        return Set(raw.compactMap(Self.normalizedPin))
    }

    func setPinned(_ ids: Set<String>, owner ownerUwcId: String) {
        let key = Self.key(forOwner: ownerUwcId)
        if ids.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(ids.sorted(), forKey: key)
        }
    }

    /// `"0|student|nc00aaa"` and `"NC00AAA"` both mean `nc00aaa`.
    static func normalizedPin(_ raw: String) -> String? {
        let tail = raw.split(separator: "|").last.map(String.init) ?? raw
        let trimmed = tail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Sweep report

/// What one `syncFullDirectory` actually did, so a caller (and a test) can see the shape of the
/// sweep without re-deriving it from the people list.
struct DirectorySyncReport: Sendable, Equatable {
    /// Pages actually fetched over the network. Zero means everything was still fresh on disk.
    let pagesFetched: Int
    /// Pages served from `W4PageCache` instead of the network.
    let pagesFromCache: Int
    /// Sources that failed and had no cached copy to fall back on.
    let failedSources: [PeopleDirectorySource]
    let peopleCount: Int
}

// MARK: - Repository

actor DirectoryRepository {

    static let shared = DirectoryRepository()

    /// The default full-directory sweep.
    ///
    /// `allStudents` already contains first and second year, so fetching `firstyear` and
    /// `secondyear` as well would triple the load on the school's box for rows we already have.
    /// They stay available through `people(source:)` for a screen that wants exactly one year.
    static let defaultSweepSources: [PeopleDirectorySource] = [.allStudents, .currentStaff]

    /// **[I]** — no paged W4 people list has ever been captured. Yii 1's `CLinkPager` defaults to a
    /// `page` query key, so that is what a follow-up page asks for. The cap exists so a
    /// misunderstood pager can never turn into an unbounded crawl of a school server.
    static let maxPagesPerSource = 10

    private let fetcher: W4PeopleFetching
    private let cache: W4PageCache
    private let store: W4PeopleStoring
    private let pins: DirectoryPinStore
    private let contextProvider: @Sendable () throws -> W4RequestContext

    private let log = Logger(subsystem: "dk.jonathanb.w4", category: "DirectoryRepository")

    init(
        fetcher: W4PeopleFetching = W4PeopleHTTPFetcher(),
        cache: W4PageCache = .shared,
        store: W4PeopleStoring = DirectoryStoreBridge(),
        pins: DirectoryPinStore = DirectoryPinStore(),
        context: @escaping @Sendable () throws -> W4RequestContext = { try W4RequestContext.require() }
    ) {
        self.fetcher = fetcher
        self.cache = cache
        self.store = store
        self.pins = pins
        self.contextProvider = context
    }

    // MARK: - One list page

    /// The cached copy of one people list, with no network call at all.
    ///
    /// A screen calls this first so it can render instantly, then calls `people(source:)` to
    /// refresh (`features.md` §2.4).
    func cachedPeople(source: PeopleDirectorySource) async -> W4Loaded<DirectoryPeoplePage>? {
        guard let context = try? contextProvider() else { return nil }
        if context.isDemo {
            return W4Loaded(Self.demoPage(for: source), freshness: .demo)
        }
        guard let page = await cache.page(
            surface: .people,
            key: Self.cacheKey(source: source, page: 1),
            uwcId: context.uwcId
        ) else { return nil }
        return W4Loaded(
            W4PeopleParser.parseList(page.html),
            freshness: .cached(fetchedAt: page.fetchedAt, isStale: page.isStale)
        )
    }

    /// One people list, cache-first.
    ///
    /// Fresh on disk wins outright; stale on disk is refetched and only falls back to the stale
    /// copy when the refetch fails. `.sessionExpired` always propagates so the app can re-login;
    /// `.forbidden` is a wrong-role answer, not a dead session, and takes the cache fallback like
    /// any other failure.
    func people(
        source: PeopleDirectorySource,
        forceRefresh: Bool = false,
        priority: FetchPriority = .important
    ) async throws -> W4Loaded<DirectoryPeoplePage> {
        let context = try contextProvider()
        if context.isDemo {
            return W4Loaded(Self.demoPage(for: source), freshness: .demo)
        }

        let key = Self.cacheKey(source: source, page: 1)
        let cached = await cache.page(surface: .people, key: key, uwcId: context.uwcId)

        if !forceRefresh, let cached, !cached.isStale {
            let page = W4PeopleParser.parseList(cached.html)
            await store.upsert(page.people)
            return W4Loaded(page, freshness: .cached(fetchedAt: cached.fetchedAt, isStale: false))
        }

        do {
            let fetched = try await fetchAndStore(
                source: source,
                pageNumber: 1,
                priority: priority,
                context: context
            )
            let page = W4PeopleParser.parseList(fetched.html)
            await store.upsert(page.people)
            return W4Loaded(page, freshness: .fresh)
        } catch {
            try Self.rethrowIfFatal(error)
            guard let cached else { throw error }
            log.warning("People list fetch failed; serving the cached copy instead.")
            let page = W4PeopleParser.parseList(cached.html)
            return W4Loaded(page, freshness: .cached(fetchedAt: cached.fetchedAt, isStale: true))
        }
    }

    // MARK: - The full sweep

    /// Walks every sweep source, page by page, and replaces the people table with the result.
    ///
    /// **Strictly serial and `.opportunistic`.** One `await` per page inside one actor means one
    /// request in flight at a time, and `.opportunistic` lets any screen the student is waiting on
    /// queue ahead of the sweep at the shared request gate. Doing it the other way round is how a
    /// 200-person directory refresh makes the timetable take twenty seconds to open.
    ///
    /// The table is only replaced when at least one source produced people: a sweep that failed
    /// everywhere must not wipe a directory the app already had.
    @discardableResult
    func syncFullDirectory(
        sources: [PeopleDirectorySource]? = nil,
        forceRefresh: Bool = false
    ) async throws -> W4Loaded<[DirectoryPerson]> {
        let context = try contextProvider()
        if context.isDemo {
            let people = Self.demoPeople
            await store.replaceAll(people)
            lastReport = DirectorySyncReport(
                pagesFetched: 0,
                pagesFromCache: 0,
                failedSources: [],
                peopleCount: people.count
            )
            return W4Loaded(people, freshness: .demo)
        }

        let sweep = sources ?? Self.defaultSweepSources
        var order: [String] = []
        var byUwcId: [String: DirectoryPerson] = [:]
        var pagesFetched = 0
        var pagesFromCache = 0
        var oldestCacheDate: Date?
        var failed: [PeopleDirectorySource] = []

        for source in sweep {
            try Task.checkCancellation()
            do {
                let outcome = try await sweepOneSource(
                    source,
                    forceRefresh: forceRefresh,
                    context: context
                )
                pagesFetched += outcome.fetched
                pagesFromCache += outcome.fromCache
                if let date = outcome.oldestCacheDate {
                    oldestCacheDate = min(oldestCacheDate ?? date, date)
                }
                for person in outcome.people where byUwcId[person.uwcId] == nil {
                    byUwcId[person.uwcId] = person
                    order.append(person.uwcId)
                }
            } catch {
                // A dead session ends the sweep immediately: every remaining page would fail the
                // same way, and the app needs to get the student back to the login screen.
                try Self.rethrowIfFatal(error)
                failed.append(source)
                log.warning("A directory source failed during the sweep; continuing with the rest.")
            }
        }

        let people = order.compactMap { byUwcId[$0] }

        if people.isEmpty {
            lastReport = DirectorySyncReport(
                pagesFetched: pagesFetched,
                pagesFromCache: pagesFromCache,
                failedSources: failed,
                peopleCount: 0
            )
            // Nothing new to say. Hand back whatever is already stored rather than an empty list,
            // and never overwrite a good table with nothing.
            let existing = await store.allPeople()
            if failed.count == sweep.count, !existing.isEmpty {
                return W4Loaded(existing, freshness: .cached(fetchedAt: oldestCacheDate ?? .distantPast, isStale: true))
            }
            return W4Loaded(existing, freshness: pagesFetched > 0 ? .fresh : .cached(
                fetchedAt: oldestCacheDate ?? .distantPast,
                isStale: true
            ))
        }

        await store.replaceAll(people)
        lastReport = DirectorySyncReport(
            pagesFetched: pagesFetched,
            pagesFromCache: pagesFromCache,
            failedSources: failed,
            peopleCount: people.count
        )
        log.info("Directory sweep finished: \(people.count, privacy: .public) people, \(pagesFetched, privacy: .public) page(s) fetched.")

        if pagesFetched > 0 {
            return W4Loaded(people, freshness: .fresh)
        }
        return W4Loaded(people, freshness: .cached(fetchedAt: oldestCacheDate ?? .distantPast, isStale: false))
    }

    /// The report from the most recent `syncFullDirectory`, for diagnostics and tests.
    private(set) var lastReport: DirectorySyncReport?

    private struct SourceOutcome {
        var people: [DirectoryPerson] = []
        var fetched = 0
        var fromCache = 0
        var oldestCacheDate: Date?
    }

    /// One source, following its pager while it says there is more.
    ///
    /// A page that adds no new UWC id ends the walk even when the pager still claims a next page:
    /// an unverified pager must not be able to loop forever against a school server.
    private func sweepOneSource(
        _ source: PeopleDirectorySource,
        forceRefresh: Bool,
        context: W4RequestContext
    ) async throws -> SourceOutcome {
        var outcome = SourceOutcome()
        var seen = Set<String>()
        var pageNumber = 1
        var firstError: Error?

        while pageNumber <= Self.maxPagesPerSource {
            try Task.checkCancellation()
            let key = Self.cacheKey(source: source, page: pageNumber)
            let cached = await cache.page(surface: .people, key: key, uwcId: context.uwcId)

            var html: String?
            if !forceRefresh, let cached, !cached.isStale {
                html = cached.html
                outcome.fromCache += 1
                outcome.oldestCacheDate = min(outcome.oldestCacheDate ?? cached.fetchedAt, cached.fetchedAt)
            } else {
                do {
                    // Every sweep request is opportunistic: the student is not waiting on it.
                    let fetched = try await fetchAndStore(
                        source: source,
                        pageNumber: pageNumber,
                        priority: .opportunistic,
                        context: context
                    )
                    html = fetched.html
                    outcome.fetched += 1
                } catch {
                    try Self.rethrowIfFatal(error)
                    guard let cached else {
                        if pageNumber == 1 { throw error }
                        firstError = firstError ?? error
                        break
                    }
                    html = cached.html
                    outcome.fromCache += 1
                    outcome.oldestCacheDate = min(outcome.oldestCacheDate ?? cached.fetchedAt, cached.fetchedAt)
                }
            }

            guard let pageHTML = html else { break }
            let page = W4PeopleParser.parseList(pageHTML)
            var addedSomebody = false
            for person in page.people where !seen.contains(person.uwcId) {
                seen.insert(person.uwcId)
                outcome.people.append(person)
                addedSomebody = true
            }

            guard page.hasMorePages, addedSomebody else { break }
            pageNumber += 1
        }

        if outcome.people.isEmpty, let firstError {
            throw firstError
        }
        return outcome
    }

    // MARK: - Reads

    /// Everybody the store knows about, without touching the network.
    func storedPeople() async -> [DirectoryPerson] {
        if let context = try? contextProvider(), context.isDemo {
            return Self.demoPeople
        }
        return await store.allPeople()
    }

    func person(uwcId: String) async -> DirectoryPerson? {
        let id = Self.normalizedUwcId(uwcId)
        guard !id.isEmpty else { return nil }
        if let context = try? contextProvider(), context.isDemo {
            return Self.demoPeople.first { $0.uwcId == id }
        }
        return await store.person(uwcId: id)
    }

    /// Prefix-then-substring search over one computed normalized string per person
    /// (`features.md` §2.1 — the stored token table is gone; ~200 rows fit in memory).
    func search(_ rawQuery: String, limit: Int = 30) async -> [DirectoryPerson] {
        let query = DirectorySearchText.normalize(rawQuery)
        guard !query.isEmpty else { return [] }
        let people = await storedPeople()

        var prefixHits: [DirectoryPerson] = []
        var containsHits: [DirectoryPerson] = []
        for person in people {
            let haystack = DirectorySearchText.searchText(for: person)
            if haystack.hasPrefix(query) || haystack.split(separator: " ").contains(where: { $0.hasPrefix(query) }) {
                prefixHits.append(person)
            } else if haystack.contains(query) {
                containsHits.append(person)
            }
        }
        let ordered = prefixHits.sorted { $0.displayName < $1.displayName }
            + containsHits.sorted { $0.displayName < $1.displayName }
        return Array(ordered.prefix(limit))
    }

    // MARK: - Pins

    /// The signed-in student's pins. Empty when nobody is signed in — a pin has no meaning
    /// without an owner.
    func pinnedUwcIds() -> Set<String> {
        guard let owner = try? contextProvider().uwcId else { return [] }
        return pins.pinned(owner: owner)
    }

    func isPinned(_ uwcId: String) -> Bool {
        pinnedUwcIds().contains(Self.normalizedUwcId(uwcId))
    }

    func setPinned(_ pinned: Bool, uwcId: String) {
        guard let owner = try? contextProvider().uwcId else { return }
        let id = Self.normalizedUwcId(uwcId)
        guard !id.isEmpty else { return }
        var current = pins.pinned(owner: owner)
        if pinned { current.insert(id) } else { current.remove(id) }
        pins.setPinned(current, owner: owner)
    }

    /// Returns the new pin state.
    @discardableResult
    func togglePin(uwcId: String) -> Bool {
        let next = !isPinned(uwcId)
        setPinned(next, uwcId: uwcId)
        return next
    }

    /// Pinned people, resolved against the store. A pin whose person is no longer in the
    /// directory is kept in `UserDefaults` (they may come back next sweep) but is not returned.
    func pinnedPeople() async -> [DirectoryPerson] {
        let ids = pinnedUwcIds()
        guard !ids.isEmpty else { return [] }
        return await storedPeople()
            .filter { ids.contains($0.uwcId) }
            .sorted { $0.displayName < $1.displayName }
    }

    // MARK: - Fetch + cache write

    private func fetchAndStore(
        source: PeopleDirectorySource,
        pageNumber: Int,
        priority: FetchPriority,
        context: W4RequestContext
    ) async throws -> W4PeopleFetchResult {
        var query: [String: String] = [:]
        if pageNumber > 1 { query["page"] = String(pageNumber) }

        let result = try await fetcher.fetchPage(
            route: source.route,
            query: query,
            priority: priority,
            credentials: context.credentials,
            uwcId: context.uwcId
        )
        await cache.store(
            html: result.html,
            surface: .people,
            key: Self.cacheKey(source: source, page: pageNumber),
            uwcId: context.uwcId,
            finalURL: result.finalURL,
            contentType: "text/html"
        )
        return result
    }

    // MARK: - Helpers

    static func cacheKey(source: PeopleDirectorySource, page: Int) -> String {
        page <= 1 ? source.rawValue : "\(source.rawValue)#\(page)"
    }

    static func normalizedUwcId(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Errors that must never be swallowed by a cache fallback.
    ///
    /// `.sessionExpired` has to reach `AuthenticationViewModel` or the app sits on a dead session
    /// forever. Cancellation is the caller changing their mind, not a failure to paper over.
    /// `.forbidden` is deliberately absent: a student opening a staff-only list is not logged out.
    static func rethrowIfFatal(_ error: Error) throws {
        if error is CancellationError { throw error }
        if let w4 = error as? W4Error, case .sessionExpired = w4 { throw w4 }
        if let urlError = error as? URLError, urlError.code == .cancelled { throw urlError }
    }
}

// MARK: - Search text

/// One normalized string per person, computed on demand.
///
/// This replaces `DirectoryEntityRecord.searchTokensData`: with ~200 people the whole table fits
/// in memory and a stored token blob buys nothing but a migration problem
/// (`features.md` §2.1).
enum DirectorySearchText {

    /// Lowercased, diacritic-folded, punctuation collapsed to single spaces.
    static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Name, preferred name, UWC id and the subtitle fields, in one normalized haystack.
    static func searchText(for person: DirectoryPerson) -> String {
        let parts = [
            person.name,
            person.preferredName,
            person.uwcId,
            person.country,
            person.house,
            person.subtitle
        ].compactMap { $0 }
        return normalize(parts.joined(separator: " "))
    }
}

// MARK: - Demo data

extension DirectoryRepository {

    /// Invented identities (`reviewer-notes.md` §8): `nc00…` ids that cannot collide with a real
    /// UWC id, and names that belong to nobody.
    private static func demoStudent(
        _ id: String,
        _ name: String,
        year: String,
        house: String,
        country: String,
        status: String? = nil
    ) -> DirectoryPerson {
        DirectoryPerson(
            uwcId: id,
            name: name,
            kind: .student,
            year: year,
            house: house,
            country: country,
            subtitle: "Year \(year) · \(house) · \(country)",
            status: status,
            photoURL: W4PeopleParser.photoURL(forUWCId: id)
        )
    }

    static let demoPeople: [DirectoryPerson] = [
        demoStudent("nc00aaa", "Alex Andersen", year: "1", house: "Haugland", country: "Denmark"),
        demoStudent("nc00bbb", "Bea Beltran", year: "2", house: "Fjaera", country: "Italy"),
        demoStudent("nc00ddd", "Dana Dlamini", year: "1", house: "Vikja", country: "South Africa"),
        demoStudent("nc00eee", "Eli Eriksen", year: "2", house: "Haugland", country: "Norway"),
        demoStudent("nc00ggg", "Gita Ghosh", year: "1", house: "Finland", country: "India", status: "Off campus"),
        demoStudent("nc00hhh", "Cara Cole", year: "2", house: "Finland", country: "Canada"),
        demoStudent("nc00iii", "Mei Nakamura", year: "1", house: "Finland", country: "Japan"),
        demoStudent("nc00jjj", "Luis Ortega", year: "2", house: "Iceland", country: "Mexico"),
        demoStudent("nc00kkk", "Amara Okonkwo", year: "1", house: "Iceland", country: "Nigeria"),
        demoStudent("nc00lll", "Noor Haddad", year: "1", house: "Denmark", country: "Jordan"),
        demoStudent("nc00mmm", "Sofia Alvarez", year: "2", house: "Norway", country: "Argentina"),
        demoStudent("nc00nnn", "Tomas Novak", year: "1", house: "Norway", country: "Czechia"),
        demoStudent("nc00ppp", "Linh Nguyen", year: "1", house: "Norway", country: "Vietnam"),
        demoStudent("nc00qqq", "Amina Diallo", year: "2", house: "Sweden", country: "Senegal"),
        demoStudent("nc00rrr", "Hana Kim", year: "1", house: "Sweden", country: "South Korea"),
        demoStudent("nc00sss", "Mateo Silva", year: "2", house: "Sweden", country: "Brazil"),
        demoStudent("nc00ttt", "Jamal Farouk", year: "2", house: "Sweden", country: "Egypt"),
        DirectoryPerson(
            uwcId: "nc00ccc",
            name: "Chris Chen",
            kind: .staff,
            subtitle: "Advisor, Teacher",
            photoURL: W4PeopleParser.photoURL(forUWCId: "nc00ccc")
        ),
        DirectoryPerson(
            uwcId: "nc00fff",
            name: "Frankie Fossum",
            kind: .staff,
            subtitle: "Teacher",
            photoURL: W4PeopleParser.photoURL(forUWCId: "nc00fff")
        )
    ]

    static func demoPeople(for source: PeopleDirectorySource) -> [DirectoryPerson] {
        switch source {
        case .allStudents, .byName, .byPreferredName, .byCountry, .byHouse:
            return demoPeople.filter { $0.kind == .student }
        case .firstYear:
            return demoPeople.filter { $0.kind == .student && $0.year == "1" }
        case .secondYear:
            return demoPeople.filter { $0.kind == .student && $0.year == "2" }
        case .currentStaff, .myTeachers, .myGroupLeaders:
            return demoPeople.filter { $0.kind == .staff }
        case .staffOnLeave:
            return []
        }
    }

    static func demoPage(for source: PeopleDirectorySource) -> DirectoryPeoplePage {
        let people = demoPeople(for: source)
        return DirectoryPeoplePage(
            heading: source.title,
            people: people,
            notice: people.isEmpty ? "No users found" : nil,
            hasMorePages: false
        )
    }
}
