//
//  AttendanceRepository.swift
//  BetterW4
//
//  The attendance layer between `W4AbsenceParser` and the transport (plan Wave 5 item 5.4;
//  `features.md` §1.5, §2.5; D-13).
//
//  W4 exposes attendance in three places, and they are NOT three views of one page:
//
//    1. `site/index`                    — the two Home meters ("You have 0 absences and 0
//                                          latenesses so far"), the cheap summary Home and More
//                                          show. **Not a request of its own**: whenever a Home page
//                                          is already in the page cache and still inside its TTL,
//                                          the meters are parsed out of that copy and this
//                                          repository issues ZERO network traffic. That is the
//                                          whole point of `W4AbsenceParser.parseHomeMeters`.
//    2. `people/students/absences`      — the Academics registration list (the detail).
//    3. `people/students/eaabsences`    — the Extra Academics registration list.
//
//  Plus `people/students/absences/register`, whose captured native form can be submitted.
//
//  Cache scoping (`W4PageCache`, TTLs from `CachePolicy` and nowhere else):
//
//    | what                | surface                      | key                                |
//    |---------------------|------------------------------|------------------------------------|
//    | meters (own copy)   | `.attendanceMeters`          | `site/index`                       |
//    | meters (borrowed)   | `.home`                      | read-only probe, several key shapes |
//    | AC list             | `.attendanceAcademics`       | `people/students/absences`         |
//    | EA list             | `.attendanceExtraAcademics`  | `people/students/eaabsences`       |
//    | register form       | `.attendanceAcademics`       | `people/students/absences/register`|
//
//  This repository **reads** the `.home` surface and never writes it: the Home page belongs to
//  `HomeRepository`, and two writers with two key conventions would quietly double-store it.
//
//  Degrade contract (plan rule 3d):
//    * a fetch failure with any cached copy → that copy, flagged stale, plus the failure;
//    * a fetch failure with no cached copy  → an *empty* list / empty meters plus the failure —
//      the caller gets a renderable screen and an honest error, not a thrown exception;
//    * `W4Error.sessionExpired` and cancellation are the two exceptions: they propagate, always.
//      `W4Error.forbidden` (403 without "Login Required") is a role problem, never a dead session,
//      so it degrades like any other failure.
//

import Foundation

// MARK: - Transport seam

/// One fetched W4 page, reduced to what this repository needs.
///
/// Exists so the repository can be exercised against a stub in `BetterW4Tests` without a socket;
/// `W4HTTPClient` itself is untouched.
struct AttendancePageResponse: Sendable {
    let html: String
    let finalURL: URL?

    init(html: String, finalURL: URL? = nil) {
        self.html = html
        self.finalURL = finalURL
    }
}

/// The one thing `AttendanceRepository` needs from the network: a route in, HTML out.
protocol AttendancePageFetching: Sendable {
    func fetchPage(
        route: String,
        query: [String: String],
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority
    ) async throws -> AttendancePageResponse

    func postPage(
        route: String,
        query: [String: String],
        fields: [(String, String)],
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority
    ) async throws -> AttendancePageResponse
}

extension AttendancePageFetching {
    func postPage(
        route: String,
        query: [String: String],
        fields: [(String, String)],
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority
    ) async throws -> AttendancePageResponse {
        throw W4Error.parsingError("This transport does not support form submission")
    }
}

/// The production adapter over `W4HTTPClient`.
///
/// `@unchecked Sendable` because `W4HTTPClient` is a plain class whose only state is a handful of
/// shared singletons (`CookieManager.shared`, `KeychainManager.shared`, the static session and the
/// static request gate); nothing per-instance is mutated.
final class W4AttendancePageFetcher: AttendancePageFetching, @unchecked Sendable {
    private let client: W4HTTPClient

    init(client: W4HTTPClient = W4HTTPClient()) {
        self.client = client
    }

    func fetchPage(
        route: String,
        query: [String: String],
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority
    ) async throws -> AttendancePageResponse {
        let result = try await client.get(
            route: route,
            query: query,
            credentials: credentials,
            studentId: studentId,
            priority: priority
        )
        return AttendancePageResponse(
            html: client.decodeHTML(from: result.data),
            finalURL: result.finalURL
        )
    }

    func postPage(
        route: String,
        query: [String: String],
        fields: [(String, String)],
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority
    ) async throws -> AttendancePageResponse {
        let result = try await client.postForm(
            route: route,
            fields: fields,
            query: query,
            credentials: credentials,
            studentId: studentId,
            priority: priority
        )
        return AttendancePageResponse(
            html: client.decodeHTML(from: result.data),
            finalURL: result.finalURL
        )
    }
}

// MARK: - Failures

/// Which attendance surface a failure belongs to, so a screen showing all three can say *which*
/// half is stale instead of failing wholesale.
enum AttendanceLoadTarget: Sendable, Equatable, Hashable {
    case meters
    case list(AttendanceSource)
    case registrationForm
}

/// A fetch that did not succeed, carried *next to* whatever data we could still show.
///
/// Deliberately not an `Error`: by the time this exists we have decided not to throw.
struct AttendanceFetchFailure: Sendable, Equatable {

    /// Coarse buckets, chosen for the copy a screen shows — not a mirror of `W4Error`.
    enum Kind: Sendable, Equatable {
        /// No usable connection. The cached copy, if any, is the right thing to show.
        case offline
        /// 403 without "Login Required" — signed in, wrong role (reviewer-notes §3). **Never a
        /// dead session**, and it must never log anybody out.
        case forbidden
        /// W4 answered, unhappily: 5xx, a 409 conflict, an unreadable body.
        case server
        /// Anything else that stopped the request.
        case transport
    }

    let target: AttendanceLoadTarget
    let kind: Kind
    /// User-facing text, taken from the underlying error rather than invented here.
    let message: String

    var isForbidden: Bool { kind == .forbidden }
    var isOffline: Bool { kind == .offline }

    static func classify(_ error: Error, target: AttendanceLoadTarget) -> AttendanceFetchFailure {
        AttendanceFetchFailure(target: target, kind: kind(of: error), message: describe(error))
    }

    private static func kind(of error: Error) -> Kind {
        if let w4 = error as? W4Error {
            switch w4 {
            case .forbidden:
                return .forbidden
            case .httpError, .serverConflict, .noResponse, .parsingError:
                return .server
            case .networkError(let underlying):
                return kind(of: underlying)
            default:
                return .transport
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
                 .cannotFindHost, .dataNotAllowed, .internationalRoamingOff, .timedOut:
                return .offline
            default:
                return .transport
            }
        }
        return .transport
    }

    private static func describe(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}

// MARK: - Snapshots

/// Both Home meters plus the failure, if the refresh that produced them did not succeed.
struct AttendanceMetersSnapshot: Sendable, Equatable {
    let meters: AttendanceMeters
    let failure: AttendanceFetchFailure?

    init(meters: AttendanceMeters, failure: AttendanceFetchFailure? = nil) {
        self.meters = meters
        self.failure = failure
    }

    var academic: AttendanceMeter? { meters.academic }
    var extraAcademic: AttendanceMeter? { meters.extraAcademic }
    var isEmpty: Bool { meters.isEmpty }
}

/// One ledger's list page plus the failure, if any.
///
/// `list` is always present — `AttendanceList.empty(source:)` when the fetch failed cold — because
/// a screen that can render "nothing to show, and here is why" beats one that throws.
struct AttendanceListSnapshot: Sendable, Equatable {
    let list: AttendanceList
    let failure: AttendanceFetchFailure?

    init(list: AttendanceList, failure: AttendanceFetchFailure? = nil) {
        self.list = list
        self.failure = failure
    }

    var source: AttendanceSource { list.source }
    var records: [AttendanceRecord] { list.records }
    var isEmpty: Bool { list.records.isEmpty }
}

/// Everything the attendance screen shows: both meters and both ledgers.
struct AttendanceSnapshot: Sendable, Equatable {
    let meters: AttendanceMetersSnapshot
    let academic: AttendanceListSnapshot
    let extraAcademic: AttendanceListSnapshot

    /// Whatever went wrong, in load order. Empty when everything came back clean.
    var failures: [AttendanceFetchFailure] {
        [meters.failure, academic.failure, extraAcademic.failure].compactMap { $0 }
    }

    /// AC rows then EA rows, in the order W4 rendered them. Sorting is a presentation decision and
    /// belongs to the view model.
    var records: [AttendanceRecord] { academic.records + extraAcademic.records }

    var isEmpty: Bool { records.isEmpty && meters.isEmpty }

    /// Per-class breakdown by count (W4 has no percentages, so neither do we).
    var subjectBreakdown: [SubjectAttendance] { SubjectAttendance.breakdown(of: records) }

    /// The UI aggregate. D-13: both meters come from meter prose — the Home meters when W4 rendered
    /// them, otherwise the list page's own sentence — and never from counting rows.
    func overview(fetchedAt: Date) -> AttendanceOverview {
        AttendanceOverview(
            academic: meters.meters.academic ?? academic.list.meter,
            extraAcademic: meters.meters.extraAcademic ?? extraAcademic.list.meter,
            records: records,
            fetchedAt: fetchedAt
        )
    }
}

// MARK: - The register-absence form

/// One input of the register-absence form, verbatim.
struct AbsenceRegistrationField: Sendable, Equatable, Identifiable {
    let name: String
    let value: String

    var id: String { name }
}

struct AbsenceRegistrationSlot: Sendable, Equatable, Identifiable {
    let id: String
    let value: String
    let label: String
    let disabled: Bool
    let checked: Bool
}

struct AbsenceRegistrationForm: Sendable, Equatable {
    /// Always `people/students/absences/register` — carried so a UI can link out to W4.
    let route: String
    /// The form's own `action`, when it declares one (Yii usually omits it).
    let action: String?
    let fields: [AbsenceRegistrationField]
    let submitButtons: [AbsenceRegistrationField]
    let note: String?
    let date: String
    let slots: [AbsenceRegistrationSlot]
    let reason: String
    let emptyDayMessage: String?
    let isDemo: Bool

    init(
        route: String = W4Routes.R.absencesRegister,
        action: String? = nil,
        fields: [AbsenceRegistrationField] = [],
        submitButtons: [AbsenceRegistrationField] = [],
        note: String? = nil,
        date: String = "",
        slots: [AbsenceRegistrationSlot] = [],
        reason: String = "",
        emptyDayMessage: String? = nil,
        isDemo: Bool = false
    ) {
        self.route = route
        self.action = action
        self.fields = fields
        self.submitButtons = submitButtons
        self.note = note
        self.date = date
        self.slots = slots
        self.reason = reason
        self.emptyDayMessage = emptyDayMessage
        self.isDemo = isDemo
    }

    var canSubmit: Bool { AttendanceFeatureFlags.writesEnabled && !isDemo && !slots.isEmpty }

    /// `StudentAbsenceForm[absence_date]` when the form carries it.
    var dateField: AbsenceRegistrationField? {
        fields.first { $0.name.lowercased().contains("absence_date") }
    }

    var isEmpty: Bool { date.isEmpty && fields.isEmpty && submitButtons.isEmpty }
}

// MARK: - Repository

/// Cache policy, demo branching and degradation for the three attendance surfaces.
///
/// An actor: several screens (Home meters, More, the attendance list) ask for attendance at once,
/// and the page cache underneath is an actor too.
actor AttendanceRepository {

    static let shared = AttendanceRepository()

    private let fetcher: any AttendancePageFetching
    private let cache: W4PageCache
    private let resolveContext: @Sendable () throws -> W4RequestContext
    private let now: @Sendable () -> Date

    init(
        fetcher: any AttendancePageFetching = W4AttendancePageFetcher(),
        cache: W4PageCache = .shared,
        resolveContext: @escaping @Sendable () throws -> W4RequestContext = {
            try W4RequestContext.require()
        },
        now: @escaping @Sendable () -> Date = { TimeProvider.now }
    ) {
        self.fetcher = fetcher
        self.cache = cache
        self.resolveContext = resolveContext
        self.now = now
    }

    // MARK: Cache addressing

    /// Cache keys. One place, so "which key holds the AC list?" has a single answer.
    enum CacheKey {
        /// Our own copy of the Home page, kept only for the meters.
        static let meters = W4Routes.R.home
        static let registrationForm = W4Routes.R.absencesRegister

        static func registrationForm(date: String?) -> String {
            guard let date, !date.isEmpty else { return registrationForm }
            return "\(registrationForm)/\(date)"
        }

        static func list(for source: AttendanceSource) -> String { source.listRoute }

        /// Key shapes a Home page may have been stored under by `HomeRepository`. We read these and
        /// never write them; probing a few candidates is three file lookups and buys the
        /// zero-request meter path even if the Home repository keys its page differently.
        static let borrowedHome = [W4Routes.R.home, "home", ""]
    }

    static func surface(for source: AttendanceSource) -> W4Surface {
        switch source {
        case .academics: return .attendanceAcademics
        case .extraAcademics: return .attendanceExtraAcademics
        }
    }

    // MARK: - Meters

    /// Both Home meters.
    ///
    /// Order of preference:
    ///   1. demo → demo meters, no I/O at all;
    ///   2. a cached Home page (ours or `HomeRepository`'s) still inside its TTL → **no request**;
    ///   3. `GET site/index`, parsed, stored under `.attendanceMeters`;
    ///   4. on failure, the newest cached copy of any age, flagged stale, plus the failure;
    ///   5. with nothing cached at all, empty meters plus the failure.
    func loadMeters(
        priority: FetchPriority = .important,
        forceRefresh: Bool = false
    ) async throws -> W4Loaded<AttendanceMetersSnapshot> {
        let context = try resolveContext()
        if context.isDemo {
            return W4Loaded(
                AttendanceMetersSnapshot(meters: Self.demoMeters()),
                freshness: .demo
            )
        }

        if !forceRefresh,
           let cached = await cachedMeterPage(uwcId: context.uwcId, allowStale: false) {
            return W4Loaded(
                AttendanceMetersSnapshot(meters: cached.meters),
                freshness: .cached(fetchedAt: cached.fetchedAt, isStale: false)
            )
        }

        do {
            let response = try await fetcher.fetchPage(
                route: W4Routes.R.home,
                query: [:],
                credentials: context.credentials,
                studentId: context.uwcId,
                priority: priority
            )
            await cache.store(
                html: response.html,
                surface: .attendanceMeters,
                key: CacheKey.meters,
                uwcId: context.uwcId,
                finalURL: response.finalURL,
                contentType: nil,
                fetchedAt: now()
            )
            return W4Loaded(
                AttendanceMetersSnapshot(meters: W4AbsenceParser.parseHomeMeters(response.html)),
                freshness: .fresh
            )
        } catch {
            try rethrowIfFatal(error)
            let failure = AttendanceFetchFailure.classify(error, target: .meters)

            if let cached = await cachedMeterPage(uwcId: context.uwcId, allowStale: true) {
                return W4Loaded(
                    AttendanceMetersSnapshot(meters: cached.meters, failure: failure),
                    freshness: .cached(fetchedAt: cached.fetchedAt, isStale: cached.isStale)
                )
            }
            return W4Loaded(
                AttendanceMetersSnapshot(meters: .empty, failure: failure),
                freshness: Self.nothingCached
            )
        }
    }

    /// Meters from the cache only — never a request, `nil` when there is nothing to show.
    ///
    /// This is the "render instantly, then refresh" half of §3.2: a view model publishes this,
    /// then calls `loadMeters(forceRefresh:)`.
    func cachedMeters() async -> W4Loaded<AttendanceMetersSnapshot>? {
        guard let context = try? resolveContext() else { return nil }
        if context.isDemo {
            return W4Loaded(AttendanceMetersSnapshot(meters: Self.demoMeters()), freshness: .demo)
        }
        guard let cached = await cachedMeterPage(uwcId: context.uwcId, allowStale: true) else {
            return nil
        }
        return W4Loaded(
            AttendanceMetersSnapshot(meters: cached.meters),
            freshness: .cached(fetchedAt: cached.fetchedAt, isStale: cached.isStale)
        )
    }

    // MARK: - Lists

    /// One ledger's registration list.
    ///
    /// Never throws for a transport problem: an empty list plus a failure is a screen, an exception
    /// is a crash report. `sessionExpired` and cancellation still propagate.
    func loadList(
        for source: AttendanceSource,
        priority: FetchPriority = .important,
        forceRefresh: Bool = false
    ) async throws -> W4Loaded<AttendanceListSnapshot> {
        let context = try resolveContext()
        if context.isDemo {
            return W4Loaded(
                AttendanceListSnapshot(list: Self.demoList(for: source, now: now())),
                freshness: .demo
            )
        }

        let surface = Self.surface(for: source)
        let key = CacheKey.list(for: source)

        if !forceRefresh,
           let page = await cache.page(surface: surface, key: key, uwcId: context.uwcId),
           isFresh(page, for: surface) {
            return W4Loaded(
                AttendanceListSnapshot(list: W4AbsenceParser.parseList(page.html, source: source)),
                freshness: .cached(fetchedAt: page.fetchedAt, isStale: false)
            )
        }

        do {
            let response = try await fetcher.fetchPage(
                route: source.listRoute,
                query: ["uwc_id": context.uwcId],
                credentials: context.credentials,
                studentId: context.uwcId,
                priority: priority
            )
            await cache.store(
                html: response.html,
                surface: surface,
                key: key,
                uwcId: context.uwcId,
                finalURL: response.finalURL,
                contentType: nil,
                fetchedAt: now()
            )
            return W4Loaded(
                AttendanceListSnapshot(list: W4AbsenceParser.parseList(response.html, source: source)),
                freshness: .fresh
            )
        } catch {
            try rethrowIfFatal(error)
            let failure = AttendanceFetchFailure.classify(error, target: .list(source))

            if let page = await cache.page(surface: surface, key: key, uwcId: context.uwcId) {
                return W4Loaded(
                    AttendanceListSnapshot(
                        list: W4AbsenceParser.parseList(page.html, source: source),
                        failure: failure
                    ),
                    freshness: .cached(fetchedAt: page.fetchedAt, isStale: !isFresh(page, for: surface))
                )
            }
            return W4Loaded(
                AttendanceListSnapshot(list: .empty(source: source), failure: failure),
                freshness: Self.nothingCached
            )
        }
    }

    /// One ledger from the cache only — never a request, `nil` when there is nothing stored.
    func cachedList(for source: AttendanceSource) async -> W4Loaded<AttendanceListSnapshot>? {
        guard let context = try? resolveContext() else { return nil }
        if context.isDemo {
            return W4Loaded(
                AttendanceListSnapshot(list: Self.demoList(for: source, now: now())),
                freshness: .demo
            )
        }
        let surface = Self.surface(for: source)
        guard let page = await cache.page(
            surface: surface,
            key: CacheKey.list(for: source),
            uwcId: context.uwcId
        ) else { return nil }

        return W4Loaded(
            AttendanceListSnapshot(list: W4AbsenceParser.parseList(page.html, source: source)),
            freshness: .cached(fetchedAt: page.fetchedAt, isStale: !isFresh(page, for: surface))
        )
    }

    /// One ledger's week grid (`…/absences/index&year=&week=&uwc_id=`).
    func loadWeek(
        for source: AttendanceSource,
        year: Int,
        week: Int,
        priority: FetchPriority = .important,
        forceRefresh: Bool = false
    ) async throws -> W4Loaded<ScheduleWeek> {
        let context = try resolveContext()
        let eventSource: EventSource = source == .academics ? .academics : .extraAcademics
        if context.isDemo {
            return W4Loaded(ScheduleWeek(year: year, week: week, days: [], source: eventSource), freshness: .demo)
        }
        let key = "\(source.weekRoute)/\(year)/\(week)"
        let surface = Self.surface(for: source)
        let query = [
            "year": String(year),
            "week": String(week),
            "uwc_id": context.uwcId
        ]
        if !forceRefresh,
           let page = await cache.page(surface: surface, key: key, uwcId: context.uwcId),
           isFresh(page, for: surface) {
            return W4Loaded(
                W4TimetableParser.parseWeek(
                    html: page.html,
                    source: eventSource,
                    fallbackYear: year,
                    fallbackWeek: week
                ),
                freshness: .cached(fetchedAt: page.fetchedAt, isStale: false)
            )
        }
        do {
            let response = try await fetcher.fetchPage(
                route: source.weekRoute,
                query: query,
                credentials: context.credentials,
                studentId: context.uwcId,
                priority: priority
            )
            await cache.store(
                html: response.html,
                surface: surface,
                key: key,
                uwcId: context.uwcId,
                finalURL: response.finalURL,
                contentType: nil,
                fetchedAt: now()
            )
            return W4Loaded(
                W4TimetableParser.parseWeek(
                    html: response.html,
                    source: eventSource,
                    fallbackYear: year,
                    fallbackWeek: week
                ),
                freshness: .fresh
            )
        } catch {
            try rethrowIfFatal(error)
            if let page = await cache.page(surface: surface, key: key, uwcId: context.uwcId) {
                return W4Loaded(
                    W4TimetableParser.parseWeek(
                        html: page.html,
                        source: eventSource,
                        fallbackYear: year,
                        fallbackWeek: week
                    ),
                    freshness: .cached(fetchedAt: page.fetchedAt, isStale: true)
                )
            }
            return W4Loaded(
                ScheduleWeek(year: year, week: week, days: [], source: eventSource),
                freshness: Self.nothingCached
            )
        }
    }

    // MARK: - Everything the attendance screen shows

    /// Meters + both ledgers.
    ///
    /// The meters cost nothing when a Home page is already cached and fresh. AC runs at the
    /// caller's priority; EA is `.opportunistic` because it renders second and the request gate is
    /// serial — a greedy secondary fetch would delay the list the student is looking at.
    func loadSnapshot(
        priority: FetchPriority = .important,
        forceRefresh: Bool = false
    ) async throws -> W4Loaded<AttendanceSnapshot> {
        let context = try resolveContext()
        if context.isDemo {
            return W4Loaded(Self.demoSnapshot(now: now()), freshness: .demo)
        }

        let metersLoaded = try await loadMeters(priority: priority, forceRefresh: forceRefresh)
        let academicLoaded = try await loadList(
            for: .academics,
            priority: priority,
            forceRefresh: forceRefresh
        )
        let extraLoaded = try await loadList(
            for: .extraAcademics,
            priority: .opportunistic,
            forceRefresh: forceRefresh
        )

        let snapshot = AttendanceSnapshot(
            meters: metersLoaded.value,
            academic: academicLoaded.value,
            extraAcademic: extraLoaded.value
        )
        let freshness = Self.combine(
            [metersLoaded.freshness, academicLoaded.freshness, extraLoaded.freshness],
            now: now()
        )
        return W4Loaded(snapshot, freshness: freshness)
    }

    /// Whatever is already on disk, with no request at all. `nil` only when every surface is cold.
    func cachedSnapshot() async -> W4Loaded<AttendanceSnapshot>? {
        guard let context = try? resolveContext() else { return nil }
        if context.isDemo {
            return W4Loaded(Self.demoSnapshot(now: now()), freshness: .demo)
        }

        let metersLoaded = await cachedMeters()
        let academicLoaded = await cachedList(for: .academics)
        let extraLoaded = await cachedList(for: .extraAcademics)
        if metersLoaded == nil, academicLoaded == nil, extraLoaded == nil { return nil }

        let snapshot = AttendanceSnapshot(
            meters: metersLoaded?.value ?? AttendanceMetersSnapshot(meters: .empty),
            academic: academicLoaded?.value ?? AttendanceListSnapshot(list: .empty(source: .academics)),
            extraAcademic: extraLoaded?.value
                ?? AttendanceListSnapshot(list: .empty(source: .extraAcademics))
        )
        let freshness = Self.combine(
            [metersLoaded?.freshness, academicLoaded?.freshness, extraLoaded?.freshness]
                .compactMap { $0 },
            now: now()
        )
        return W4Loaded(snapshot, freshness: freshness)
    }

    // MARK: - Register absence

    /// The captured register-absence form, scraped and modelled for native submission.
    ///
    /// Unlike the lists this throws when it has nothing to show: a form with no inputs is not a
    /// degraded screen, it is a broken one.
    func loadRegistrationForm(
        date: String? = nil,
        priority: FetchPriority = .important,
        forceRefresh: Bool = false
    ) async throws -> W4Loaded<AbsenceRegistrationForm> {
        let context = try resolveContext()
        if context.isDemo {
            return W4Loaded(Self.demoRegistrationForm(now: now()), freshness: .demo)
        }

        let surface = W4Surface.attendanceAcademics
        let key = CacheKey.registrationForm(date: date)
        let query = date.map { ["date": $0] } ?? [:]

        if !forceRefresh,
           let page = await cache.page(surface: surface, key: key, uwcId: context.uwcId),
           isFresh(page, for: surface) {
            return W4Loaded(
                W4AbsenceParser.parseRegistrationForm(page.html),
                freshness: .cached(fetchedAt: page.fetchedAt, isStale: false)
            )
        }

        do {
            let response = try await fetcher.fetchPage(
                route: W4Routes.R.absencesRegister,
                query: query,
                credentials: context.credentials,
                studentId: context.uwcId,
                priority: priority
            )
            await cache.store(
                html: response.html,
                surface: surface,
                key: key,
                uwcId: context.uwcId,
                finalURL: response.finalURL,
                contentType: nil,
                fetchedAt: now()
            )
            let form = W4AbsenceParser.parseRegistrationForm(response.html)
            guard !form.isEmpty else { throw W4Error.parsingError("W4 did not return an absence form") }
            return W4Loaded(form, freshness: .fresh)
        } catch {
            try rethrowIfFatal(error)
            guard let page = await cache.page(surface: surface, key: key, uwcId: context.uwcId) else {
                throw error
            }
            return W4Loaded(
                W4AbsenceParser.parseRegistrationForm(page.html),
                freshness: .cached(fetchedAt: page.fetchedAt, isStale: !isFresh(page, for: surface))
            )
        }
    }

    func submitRegistration(
        form: AbsenceRegistrationForm,
        selectedValues: [String],
        wholeDay: Bool,
        reason: String,
        priority: FetchPriority = .important
    ) async throws {
        let context = try resolveContext()
        guard !context.isDemo else { throw W4Error.parsingError("Registration is unavailable in demo mode") }
        guard AttendanceFeatureFlags.writesEnabled else { throw W4Error.parsingError("Absence registration is disabled") }
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else { throw W4Error.parsingError("Absence reason is required") }
        let enabled = Set(form.slots.filter { !$0.disabled }.map(\.value))
        let chosen = wholeDay ? Array(enabled) : selectedValues.filter { enabled.contains($0) }
        guard !chosen.isEmpty else { throw W4Error.parsingError("Select at least one class") }

        var fields: [(String, String)] = [
            ("StudentAbsenceForm[absence_date]", form.date),
            ("StudentAbsenceForm[absences]", ""),
            ("StudentAbsenceForm[reason]", String(trimmedReason.prefix(60)))
        ]
        if wholeDay { fields.append(("StudentAbsenceForm_absences_all", "1")) }
        fields.append(contentsOf: chosen.map { ("StudentAbsenceForm[absences][]", $0) })
        fields.append(("yt0", "Register absences"))

        let response = try await fetcher.postPage(
            route: W4Routes.R.absencesRegister,
            query: ["date": form.date],
            fields: fields,
            credentials: context.credentials,
            studentId: context.uwcId,
            priority: priority
        )
        if let error = W4AbsenceParser.parseSubmissionError(response.html) {
            throw W4Error.parsingError(error)
        }
        await invalidateCaches()
    }

    // MARK: - Cache maintenance

    /// Drops every page this repository owns for the signed-in student.
    ///
    /// The borrowed `.home` page is deliberately left alone — it is `HomeRepository`'s to evict.
    func invalidateCaches() async {
        guard let context = try? resolveContext(), !context.isDemo else { return }
        await cache.remove(surface: .attendanceMeters, key: CacheKey.meters, uwcId: context.uwcId)
        await cache.remove(
            surface: .attendanceAcademics,
            key: CacheKey.list(for: .academics),
            uwcId: context.uwcId
        )
        await cache.remove(
            surface: .attendanceExtraAcademics,
            key: CacheKey.list(for: .extraAcademics),
            uwcId: context.uwcId
        )
        await cache.remove(
            surface: .attendanceAcademics,
            key: CacheKey.registrationForm,
            uwcId: context.uwcId
        )
    }

    // MARK: - Internals

    /// The freshness of a value we could not fetch and did not have: as old as data gets.
    ///
    /// `W4Freshness` has no "nothing" case and this file does not get to add one, so the honest
    /// encoding is "cached, from the distant past, stale". Callers must read `failure` — it is the
    /// field that says what actually happened.
    private static let nothingCached = W4Freshness.cached(fetchedAt: .distantPast, isStale: true)

    /// TTL is `CachePolicy`'s answer, evaluated against this repository's clock so tests can move
    /// time without fighting `CachedPage.isStale` (which always uses `TimeProvider.now`).
    private func isFresh(_ page: CachedPage, for surface: W4Surface) -> Bool {
        CachePolicy.isFresh(page.fetchedAt, for: surface, now: now())
    }

    /// `sessionExpired` must reach the app so it can re-login; cancellation must not be reported as
    /// a failure. Everything else degrades.
    private func rethrowIfFatal(_ error: Error) throws {
        if let w4 = error as? W4Error, case .sessionExpired = w4 { throw error }
        if error is CancellationError { throw error }
        if let urlError = error as? URLError, urlError.code == .cancelled { throw urlError }
    }

    private struct CachedMeters {
        let meters: AttendanceMeters
        let fetchedAt: Date
        let isStale: Bool
    }

    /// The newest cached page that actually yields meters.
    ///
    /// Candidates, newest first: `HomeRepository`'s Home page (borrowed, several key shapes) and
    /// our own `.attendanceMeters` copy. A page that parses to no meters at all is skipped so a
    /// truncated or unrelated cached page cannot pin the meters to "absent" — with one exception:
    /// our own copy, inside its TTL, is authoritative even when empty, otherwise a student whose
    /// W4 renders no meter would refetch `site/index` on every appear.
    private func cachedMeterPage(uwcId: String, allowStale: Bool) async -> CachedMeters? {
        var candidates: [(surface: W4Surface, page: CachedPage)] = []
        for key in CacheKey.borrowedHome {
            if let page = await cache.page(surface: .home, key: key, uwcId: uwcId) {
                candidates.append((.home, page))
            }
        }
        if let page = await cache.page(
            surface: .attendanceMeters,
            key: CacheKey.meters,
            uwcId: uwcId
        ) {
            candidates.append((.attendanceMeters, page))
        }

        for candidate in candidates.sorted(by: { $0.page.fetchedAt > $1.page.fetchedAt }) {
            let fresh = isFresh(candidate.page, for: candidate.surface)
            guard allowStale || fresh else { continue }

            let meters = W4AbsenceParser.parseHomeMeters(candidate.page.html)
            if !meters.isEmpty {
                return CachedMeters(
                    meters: meters,
                    fetchedAt: candidate.page.fetchedAt,
                    isStale: !fresh
                )
            }
            if fresh, candidate.surface == .attendanceMeters {
                return CachedMeters(meters: .empty, fetchedAt: candidate.page.fetchedAt, isStale: false)
            }
        }
        return nil
    }

    /// The coarsest honest answer for a value assembled from several surfaces: demo only when every
    /// part is demo, fresh only when no part came off disk, otherwise the oldest `fetchedAt` and
    /// stale if any part was.
    static func combine(_ freshnesses: [W4Freshness], now: Date) -> W4Freshness {
        guard !freshnesses.isEmpty else { return .fresh }
        if freshnesses.allSatisfy({ $0 == .demo }) { return .demo }

        var oldest: Date?
        var anyStale = false
        var anyCached = false
        for freshness in freshnesses {
            switch freshness {
            case .demo:
                continue
            case .fresh:
                oldest = min(oldest ?? now, now)
            case .cached(let fetchedAt, let isStale):
                anyCached = true
                anyStale = anyStale || isStale
                oldest = min(oldest ?? fetchedAt, fetchedAt)
            }
        }
        guard anyCached else { return .fresh }
        return .cached(fetchedAt: oldest ?? now, isStale: anyStale)
    }

}

// MARK: - Demo mode (features.md §4)

/// Zero network, zero persistence, English, UWC-shaped. The numbers match the demo table in
/// `features.md` §4: AC "2 absences and 1 lateness", EA clean, three AC rows, an empty EA ledger,
/// and a register form that opens read-only with an explanatory note.
extension AttendanceRepository {

    static func demoMeters() -> AttendanceMeters {
        AttendanceMeters(
            academic: AttendanceMeter(absences: 2, latenesses: 1),
            extraAcademic: .zero
        )
    }

    static func demoList(for source: AttendanceSource, now: Date) -> AttendanceList {
        switch source {
        case .academics:
            return AttendanceList(
                source: .academics,
                meter: AttendanceMeter(absences: 2, latenesses: 1),
                records: demoAcademicRecords(now: now),
                hasMorePages: false,
                emptyMessage: nil
            )
        case .extraAcademics:
            return AttendanceList(
                source: .extraAcademics,
                meter: .zero,
                records: [],
                hasMorePages: false,
                emptyMessage: "No results found."
            )
        }
    }

    static func demoSnapshot(now: Date) -> AttendanceSnapshot {
        AttendanceSnapshot(
            meters: AttendanceMetersSnapshot(meters: demoMeters()),
            academic: AttendanceListSnapshot(list: demoList(for: .academics, now: now)),
            extraAcademic: AttendanceListSnapshot(list: demoList(for: .extraAcademics, now: now))
        )
    }

    static func demoRegistrationForm(now: Date) -> AbsenceRegistrationForm {
        AbsenceRegistrationForm(
            route: W4Routes.R.absencesRegister,
            action: nil,
            fields: [
                AbsenceRegistrationField(
                    name: "StudentAbsenceForm[absence_date]",
                    value: W4Dates.format(now)
                )
            ],
            submitButtons: [],
            note: "Demo data. Not connected to W4. Registering an absence is not available here.",
            date: W4Dates.format(now),
            isDemo: true
        )
    }

    private static func demoAcademicRecords(now: Date) -> [AttendanceRecord] {
        let today = W4Dates.startOfDay(now)

        func record(
            dayOffset: Int,
            period: String,
            subject: String,
            kind: AttendanceKind,
            status: String,
            teacher: String,
            note: String?
        ) -> AttendanceRecord {
            let date = today.addingTimeInterval(TimeInterval(dayOffset) * 86_400)
            let displayDate = W4Dates.format(date)
            return AttendanceRecord(
                id: AttendanceRecord.identity(
                    source: .academics,
                    dateRaw: displayDate,
                    period: period,
                    subject: subject,
                    kind: kind
                ),
                source: .academics,
                date: date,
                displayDate: displayDate,
                period: period,
                subject: subject,
                kind: kind,
                status: status,
                teacher: teacher,
                note: note
            )
        }

        return [
            record(
                dayOffset: -1,
                period: "P2",
                subject: "English A HL",
                kind: .lateness,
                status: "Excused",
                teacher: "C. Berg",
                note: "Arrived 8 minutes late"
            ),
            record(
                dayOffset: -3,
                period: "P3",
                subject: "Biology SL",
                kind: .absence,
                status: "Unexcused",
                teacher: "B. Holm",
                note: nil
            ),
            record(
                dayOffset: -8,
                period: "P1",
                subject: "Mathematics HL",
                kind: .absence,
                status: "Unexcused",
                teacher: "A. Nordahl",
                note: "Missed the morning block"
            )
        ]
    }
}
