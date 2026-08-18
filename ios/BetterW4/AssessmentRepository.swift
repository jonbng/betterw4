//
//  AssessmentRepository.swift
//  BetterW4
//
//  The read/write layer over `index.php?r=academics/deadlines` (`features.md` §1.3, §2.1, §2.5;
//  plan Wave 5 item 5.2). One W4 surface replaces both of BetterLectio's `lektier` and `opgaver`
//  tabs, and it is the only place in the app that writes anything back to W4.
//
//  THE WRITE PATH IS THE RISKY PART, SO READ THIS BEFORE CHANGING IT
//  ----------------------------------------------------------------
//  * A class-assigned item posts `assessment_id`; a student-created item posts
//    `student_assessment_id`. Send the wrong one and W4 accepts the request and changes nothing —
//    "Confirm done" becomes a silent no-op. The payload is therefore never built here: it comes
//    from `W4AssessmentParser.statusFields(for:)`, which is keyed on the item's kind.
//  * The endpoints are scraped per page render (`var ajax_urls = {…}`, carrying `&month=&year=
//    &uwc_id=`) and must never be hardcoded.
//  * Every one of those payloads is unverified against the real server (OQ-3, capture C-3), so
//    live writes stay behind `AssessmentFeatureFlags.writesEnabled`.
//
//  Optimistic overlay: a tap writes `localStatus` immediately (so the UI flips at once), the POST
//  follows, and the overlay is dropped as soon as a *newer* server status arrives —
//  `AssessmentOverlayPolicy` in `AssessmentStore.swift` owns that rule. A failed write reverts the
//  overlay and rethrows; it never fails silently. A successful write drops the cached page so the
//  next read cannot render the pre-write state.
//
//  Freshness: TTL lives in `CachePolicy` (15 minutes for `.assessments`) and nowhere else.
//
//  Concurrency: an `actor`. It never touches a `ModelContext`; persistence goes through
//  `AssessmentOverlayStoring`, whose parameters and results are value types.
//

import Foundation

// MARK: - Month

/// The month the assessments calendar is showing.
///
/// W4 takes `month` and `year` as sibling query keys, 1-based, and renders its own links
/// zero-padded (`month=08`). This type is the single place that knows that.
struct AssessmentMonth: Hashable, Sendable, CustomStringConvertible {
    let year: Int
    /// 1...12, clamped on construction — a repository must never build `month=0`.
    let month: Int

    init(year: Int, month: Int) {
        self.year = year
        self.month = min(max(month, 1), 12)
    }

    /// The month containing `date`, in Oslo (plan D-11: never `TimeZone.current`).
    static func current(_ date: Date = TimeProvider.now) -> AssessmentMonth {
        let components = W4Dates.calendar.dateComponents([.year, .month], from: date)
        return AssessmentMonth(
            year: components.year ?? W4Dates.calendar.component(.year, from: date),
            month: components.month ?? 1
        )
    }

    /// Cache key and log label: `"2026-08"`.
    var key: String { String(format: "%04d-%02d", year, month) }

    /// The query W4 expects. Zero-padded to match the links the page renders for itself;
    /// PHP reads `"08"` as 8.
    var query: [String: String] {
        ["month": String(format: "%02d", month), "year": String(year)]
    }

    /// The Oslo month as a half-open interval, used to scope pruning to the month we just fetched.
    var interval: DateInterval? {
        guard let start = W4Dates.date(year: year, month: month, day: 1),
              let end = W4Dates.calendar.date(byAdding: DateComponents(month: 1), to: start),
              end > start else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// `offset(byMonths: -1)` is the previous month, rolling the year over correctly.
    func offset(byMonths delta: Int) -> AssessmentMonth {
        let ordinal = (year * 12) + (month - 1) + delta
        return AssessmentMonth(year: ordinal / 12, month: (ordinal % 12) + 1)
    }

    var description: String { key }
}

// MARK: - Errors

/// Why a write could not be attempted. A write that *was* attempted and failed surfaces the
/// transport's own `W4Error` instead, so `.sessionExpired` keeps its meaning all the way up.
enum AssessmentWriteError: Error, LocalizedError, Equatable {
    /// `AssessmentFeatureFlags.writesEnabled` is off (OQ-3): the POST payloads have never been
    /// verified against the real server, so the affordance must stay hidden.
    case writesDisabled
    /// W4 published no endpoint for this transition on the page we last read.
    case endpointUnavailable(AssessmentTransition)
    /// The item carries no usable raw id, so there is nothing to post.
    case missingIdentifier
    /// The scraped endpoint is not a readable W4 route.
    case invalidEndpoint(String)

    var errorDescription: String? {
        switch self {
        case .writesDisabled:
            return "Changing an assessment is not available yet"
        case .endpointUnavailable:
            return "W4 did not offer that action on this page"
        case .missingIdentifier:
            return "That assessment has no identifier to send"
        case .invalidEndpoint:
            return "W4 published an address this app cannot use"
        }
    }
}

// MARK: - Transport seam

/// One fetched page.
struct AssessmentPageResponse: Sendable {
    let html: String
    let finalURL: URL

    init(html: String, finalURL: URL) {
        self.html = html
        self.finalURL = finalURL
    }
}

/// The two requests this repository makes, and nothing else.
///
/// It exists so the repository can be unit-tested against a stub without touching the network;
/// `W4HTTPClient` itself is untouched.
protocol AssessmentPageTransport: Sendable {

    func loadAssessmentsPage(
        month: AssessmentMonth,
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority
    ) async throws -> AssessmentPageResponse

    /// jQuery-shaped POST to a scraped `ajax_urls` endpoint.
    func submitAssessmentAction(
        route: String,
        query: [String: String],
        fields: [String: String],
        credentials: W4Credentials,
        studentId: String?
    ) async throws -> AssessmentPageResponse
}

/// The live transport.
///
/// `@unchecked Sendable` is honest here rather than lazy: `W4HTTPClient` stores only two
/// singletons, and its URLSession and request gate are static, so an instance is immutable and
/// safe to share.
final class AssessmentHTTPTransport: AssessmentPageTransport, @unchecked Sendable {

    private let client: W4HTTPClient

    init(client: W4HTTPClient = W4HTTPClient()) {
        self.client = client
    }

    func loadAssessmentsPage(
        month: AssessmentMonth,
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority
    ) async throws -> AssessmentPageResponse {
        let result = try await client.get(
            route: W4Routes.R.assessments,
            query: month.query,
            credentials: credentials,
            studentId: studentId,
            priority: priority
        )
        return AssessmentPageResponse(
            html: client.decodeHTML(from: result.data),
            finalURL: result.finalURL
        )
    }

    func submitAssessmentAction(
        route: String,
        query: [String: String],
        fields: [String: String],
        credentials: W4Credentials,
        studentId: String?
    ) async throws -> AssessmentPageResponse {
        let result = try await client.postAjax(
            route: route,
            fields: fields,
            query: query,
            credentials: credentials,
            studentId: studentId,
            priority: .important
        )
        return AssessmentPageResponse(
            html: client.decodeHTML(from: result.data),
            finalURL: result.finalURL
        )
    }
}

// MARK: - Repository

actor AssessmentRepository {

    static let shared = AssessmentRepository()

    private let transport: any AssessmentPageTransport
    private let cache: W4PageCache
    private let store: any AssessmentOverlayStoring
    private let resolveContext: @Sendable () throws -> W4RequestContext
    private let now: @Sendable () -> Date
    /// Injected only so the tests can exercise the write path; production always takes the
    /// default, which is the shared OQ-3 gate.
    private let writesEnabled: Bool

    /// Endpoints last scraped from each month's page. In memory only: W4 regenerates them per
    /// render, so a persisted copy would be a stale URL waiting to be posted to.
    private var actionURLsByMonth: [AssessmentMonth: AssessmentActionURLs] = [:]

    /// Months this instance has put in — or read out of — the page cache, so `clear` knows which
    /// keys to remove without wiping other surfaces.
    private var touchedMonths: Set<AssessmentMonth> = []

    init(
        transport: any AssessmentPageTransport = AssessmentHTTPTransport(),
        cache: W4PageCache = .shared,
        store: (any AssessmentOverlayStoring)? = nil,
        resolveContext: @escaping @Sendable () throws -> W4RequestContext = {
            try W4RequestContext.require()
        },
        now: @escaping @Sendable () -> Date = { TimeProvider.now },
        writesEnabled: Bool = AssessmentFeatureFlags.writesEnabled
    ) {
        self.transport = transport
        self.cache = cache
        self.store = store ?? SharedAssessmentOverlayStore()
        self.resolveContext = resolveContext
        self.now = now
        self.writesEnabled = writesEnabled
    }

    // MARK: Reading

    /// The last copy of this month we can render without touching the network, or nil when there
    /// is none. Call this first so a screen paints immediately, then call `assessments(for:)`.
    ///
    /// Read-only: it applies the local overlay but never writes server truth.
    func cachedAssessments(for month: AssessmentMonth = .current()) async -> W4Loaded<[Assessment]>? {
        guard let context = try? resolveContext() else { return nil }

        if context.isDemo {
            return await demoLoaded(uwcId: context.uwcId)
        }

        guard let page = await cache.page(surface: .assessments, key: month.key, uwcId: context.uwcId),
              let items = try? W4AssessmentParser.parse(page.html) else { return nil }

        rememberActionURLs(from: page.html, month: month)
        let merged = await store.applyOverlays(
            to: items,
            uwcId: context.uwcId,
            observedAt: page.fetchedAt
        )
        return W4Loaded(
            AssessmentRepository.sorted(merged),
            freshness: .cached(fetchedAt: page.fetchedAt, isStale: page.isStale)
        )
    }

    /// One month of assessments: cache first while it is inside its TTL, otherwise W4.
    ///
    /// An empty month is a completely normal state on this page and comes back as an empty array,
    /// never an error.
    func assessments(
        for month: AssessmentMonth = .current(),
        forceRefresh: Bool = false,
        priority: FetchPriority = .important
    ) async throws -> W4Loaded<[Assessment]> {
        let context = try resolveContext()

        // Demo never makes a request — the branch comes before anything else can.
        if context.isDemo {
            return await demoLoaded(uwcId: context.uwcId)
        }

        let uwcId = context.uwcId

        if !forceRefresh,
           let page = await cache.freshPage(surface: .assessments, key: month.key, uwcId: uwcId),
           let fromCache = await loadedFromCache(page: page, month: month, uwcId: uwcId) {
            return fromCache
        }

        do {
            let response = try await transport.loadAssessmentsPage(
                month: month,
                credentials: context.credentials,
                studentId: uwcId,
                priority: priority
            )

            // Parse before caching: a page we cannot read must not evict one we can.
            guard let items = try? W4AssessmentParser.parse(response.html) else {
                throw W4Error.parsingError("assessments \(month.key)")
            }
            rememberActionURLs(from: response.html, month: month)

            let fetchedAt = now()
            touchedMonths.insert(month)
            await cache.store(
                html: response.html,
                surface: .assessments,
                key: month.key,
                uwcId: uwcId,
                finalURL: response.finalURL,
                fetchedAt: fetchedAt
            )
            let merged = await store.persist(
                items,
                uwcId: uwcId,
                observedAt: fetchedAt,
                pruning: month.interval
            )
            return W4Loaded(AssessmentRepository.sorted(merged), freshness: .fresh)
        } catch {
            // A dead session must reach the app so it can re-login; everything else may degrade
            // to the last good copy. `.forbidden` is deliberately *not* a dead session.
            if AssessmentRepository.mustPropagate(error) { throw error }

            if let page = await cache.page(surface: .assessments, key: month.key, uwcId: uwcId),
               let fromCache = await loadedFromCache(page: page, month: month, uwcId: uwcId) {
                return fromCache
            }
            throw error
        }
    }

    /// Convenience for pull-to-refresh.
    func refresh(
        for month: AssessmentMonth = .current(),
        priority: FetchPriority = .important
    ) async throws -> W4Loaded<[Assessment]> {
        try await assessments(for: month, forceRefresh: true, priority: priority)
    }

    // MARK: Write affordances

    /// The endpoints W4 published for this month, from memory or the cached page. Never fetches:
    /// a screen asks this to decide whether to *show* a button.
    func actionURLs(for month: AssessmentMonth) async -> AssessmentActionURLs? {
        if let known = actionURLsByMonth[month] { return known }
        guard let context = try? resolveContext(), !context.isDemo else { return nil }
        guard let page = await cache.page(surface: .assessments, key: month.key, uwcId: context.uwcId)
        else { return nil }
        rememberActionURLs(from: page.html, month: month)
        return actionURLsByMonth[month]
    }

    /// Whether the UI may offer Confirm done / Revert to pending at all.
    func canWrite(in month: AssessmentMonth) async -> Bool {
        guard let context = try? resolveContext() else { return false }
        if context.isDemo { return true }
        guard writesEnabled else { return false }
        guard let urls = await actionURLs(for: month) else { return false }
        return urls.url(for: .confirmDone) != nil || urls.url(for: .revertToPending) != nil
    }

    // MARK: Writing

    /// Confirm done / Revert to pending.
    ///
    /// Returns the item as it should now be shown. The optimistic overlay is written before the
    /// POST and removed again if the POST fails, and the error is always rethrown — a write that
    /// fails silently is exactly the bug this surface is most exposed to.
    @discardableResult
    func apply(
        _ transition: AssessmentTransition,
        to item: Assessment,
        in month: AssessmentMonth
    ) async throws -> Assessment {
        let context = try resolveContext()
        let newStatus = transition.resultingStatus
        let writtenAt = now()

        // Demo flips locally and stays flipped for the session; it never makes a request, and the
        // OQ-3 gate does not apply because there is no payload to get wrong.
        if context.isDemo {
            await store.setOverlay(newStatus, for: item, uwcId: context.uwcId, at: writtenAt)
            return AssessmentRepository.applying(newStatus, to: item)
        }

        guard writesEnabled else { throw AssessmentWriteError.writesDisabled }

        // Kind-keyed, never hand-built: class → assessment_id, student → student_assessment_id.
        let fields = W4AssessmentParser.statusFields(for: item)
        guard !fields.isEmpty else { throw AssessmentWriteError.missingIdentifier }

        let urls = try await resolvedActionURLs(for: month, context: context)
        guard let endpoint = urls?.url(for: transition) else {
            throw AssessmentWriteError.endpointUnavailable(transition)
        }
        let target = try AssessmentRepository.routeAndQuery(from: endpoint)

        // Optimistic: the tap is visible before the request leaves.
        await store.setOverlay(newStatus, for: item, uwcId: context.uwcId, at: writtenAt)

        do {
            _ = try await transport.submitAssessmentAction(
                route: target.route,
                query: target.query,
                fields: fields,
                credentials: context.credentials,
                studentId: context.uwcId
            )
        } catch {
            await store.removeOverlay(for: item.id, uwcId: context.uwcId)
            throw error
        }

        // The cached page still shows the pre-write state, so it goes immediately.
        await cache.remove(surface: .assessments, key: month.key, uwcId: context.uwcId)
        return AssessmentRepository.applying(newStatus, to: item)
    }

    /// The transition W4 offers for the item's current status.
    @discardableResult
    func toggle(_ item: Assessment, in month: AssessmentMonth) async throws -> Assessment {
        try await apply(item.offeredTransition, to: item, in: month)
    }

    // MARK: Maintenance

    /// Drops this student's mirrored records, any pending overlay, and the assessment pages this
    /// instance has read.
    ///
    /// It deliberately does **not** call `W4PageCache.clear`: that wipes every surface for the
    /// student, which is the Settings "Clear cache" row's job, not one repository's.
    func clear(uwcId: String?) async {
        let months = touchedMonths
        actionURLsByMonth.removeAll()
        touchedMonths.removeAll()
        await store.clear(uwcId: uwcId)

        guard let uwcId else { return }
        for month in months {
            await cache.remove(surface: .assessments, key: month.key, uwcId: uwcId)
        }
    }

    // MARK: Internals

    private func demoLoaded(uwcId: String) async -> W4Loaded<[Assessment]> {
        let items = AssessmentDemoCatalog.items(now: now())
        let merged = await store.applyOverlays(to: items, uwcId: uwcId, observedAt: nil)
        return W4Loaded(AssessmentRepository.sorted(merged), freshness: .demo)
    }

    /// Turns a cached page into a result, recording its endpoints on the way through.
    /// Returns nil when the HTML no longer parses, so the caller can fall through to the network.
    private func loadedFromCache(
        page: CachedPage,
        month: AssessmentMonth,
        uwcId: String
    ) async -> W4Loaded<[Assessment]>? {
        guard let items = try? W4AssessmentParser.parse(page.html) else { return nil }
        rememberActionURLs(from: page.html, month: month)
        touchedMonths.insert(month)
        let merged = await store.persist(
            items,
            uwcId: uwcId,
            observedAt: page.fetchedAt,
            pruning: month.interval
        )
        return W4Loaded(
            AssessmentRepository.sorted(merged),
            freshness: .cached(fetchedAt: page.fetchedAt, isStale: page.isStale)
        )
    }

    private func rememberActionURLs(from html: String, month: AssessmentMonth) {
        guard let urls = try? W4AssessmentParser.parseAjaxURLs(html), !urls.isEmpty else { return }
        actionURLsByMonth[month] = urls
    }

    /// Endpoints for a write: memory, then the cached page, then — only if both are empty — one
    /// fetch, because a write with no endpoint is not something to guess at.
    private func resolvedActionURLs(
        for month: AssessmentMonth,
        context: W4RequestContext
    ) async throws -> AssessmentActionURLs? {
        if let known = actionURLsByMonth[month] { return known }

        if let page = await cache.page(surface: .assessments, key: month.key, uwcId: context.uwcId) {
            rememberActionURLs(from: page.html, month: month)
            if let known = actionURLsByMonth[month] { return known }
        }

        _ = try await assessments(for: month, forceRefresh: true)
        return actionURLsByMonth[month]
    }

    /// Splits a scraped `ajax_urls` value into a Yii route plus its sibling query keys
    /// (`&month=&year=&uwc_id=`), and refuses anything that is not on the W4 host.
    private static func routeAndQuery(
        from endpoint: String
    ) throws -> (route: String, query: [String: String]) {
        let url = W4Routes.resolve(endpoint)
        try W4HTTPClient.requireW4Host(url, context: "assessments write")

        guard let route = W4Routes.route(of: url), !route.isEmpty else {
            throw AssessmentWriteError.invalidEndpoint(endpoint)
        }

        var query: [String: String] = [:]
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            for queryItem in components.queryItems ?? [] where queryItem.name.lowercased() != "r" {
                query[queryItem.name] = queryItem.value ?? ""
            }
        }
        return (route, query)
    }

    private static func applying(_ status: AssessmentStatus, to item: Assessment) -> Assessment {
        var copy = item
        copy.status = status
        return copy
    }

    /// Soonest first, undated last, then a stable tie-break so a redraw never reorders the list.
    private static func sorted(_ items: [Assessment]) -> [Assessment] {
        items.sorted { lhs, rhs in
            let left = lhs.dueDate ?? .distantFuture
            let right = rhs.dueDate ?? .distantFuture
            if left != right { return left < right }
            if lhs.title != rhs.title { return lhs.title < rhs.title }
            return lhs.id < rhs.id
        }
    }

    /// Errors that must never be answered with a cached copy.
    ///
    /// `.forbidden` is absent on purpose: HTTP 403 without "Login Required" means signed in with
    /// the wrong role, and treating it as a dead session would kick the student to the login
    /// screen (`README` §4.5).
    private static func mustPropagate(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let w4Error = error as? W4Error {
            switch w4Error {
            case .sessionExpired, .cookieExpired:
                return true
            default:
                return false
            }
        }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }
}

// MARK: - Demo data

/// The offline assessments used by the App Review demo session (`features.md` §3):
/// six items spanning −10…+12 days, two done, one overdue, one student-created.
///
/// It lives here rather than in `DemoDataProvider` so the repository's demo branch has no
/// dependency outside this file; folding it into the demo provider later changes nothing.
enum AssessmentDemoCatalog {

    static func items(now: Date = TimeProvider.now) -> [Assessment] {
        let today = W4Dates.startOfDay(now)

        return [
            make(rawId: "9001", kind: .classAssigned, title: "Cell biology lab report",
                 subject: "Biology", classCode: "BIO HL", teacher: "Jane Doe",
                 unit: "Cell biology", daysFromToday: -10, status: .done, today: today),
            make(rawId: "9002", kind: .classAssigned, title: "Cold War essay",
                 subject: "History", classCode: "HIS HL", teacher: "Peter Hansen",
                 unit: "Paper 2", daysFromToday: -3, status: .pending, today: today),
            make(rawId: "9003", kind: .classAssigned, title: "Calculus problem set",
                 subject: "Mathematics", classCode: "MAA HL", teacher: "Maria Costa",
                 unit: "Differentiation", daysFromToday: 1, status: .pending, today: today),
            make(rawId: "9004", kind: .classAssigned, title: "Oral presentation",
                 subject: "Spanish B", classCode: "SPA SL", teacher: "Lucia Marin",
                 unit: "Individual oral", daysFromToday: 5, status: .done, today: today),
            make(rawId: "9005", kind: .studentCreated, title: "Revise TOK exhibition notes",
                 subject: nil, classCode: nil, teacher: nil,
                 unit: nil, daysFromToday: 7, status: .pending, today: today),
            make(rawId: "9006", kind: .classAssigned, title: "Internal assessment draft",
                 subject: "Chemistry", classCode: "CHE HL", teacher: "Anna Lund",
                 unit: "IA", daysFromToday: 12, status: .pending, today: today)
        ]
    }

    private static func make(
        rawId: String,
        kind: AssessmentKind,
        title: String,
        subject: String?,
        classCode: String?,
        teacher: String?,
        unit: String?,
        daysFromToday: Int,
        status: AssessmentStatus,
        today: Date
    ) -> Assessment {
        Assessment(
            id: "\(kind.rawValue):\(rawId)",
            rawId: rawId,
            kind: kind,
            rawKind: kind.rawValue,
            title: title,
            subject: subject,
            classCode: classCode,
            teacher: teacher,
            unit: unit,
            dueDate: W4Dates.adding(days: daysFromToday, to: today),
            daysLeft: daysFromToday,
            status: status,
            rawStatus: status.rawValue,
            // Overdue is styling, not a status: only an unfinished item in the past is overdue.
            isOverdue: daysFromToday < 0 && status == .pending,
            isEditable: kind == .studentCreated,
            href: nil
        )
    }
}
