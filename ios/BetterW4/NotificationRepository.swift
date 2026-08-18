//
//  NotificationRepository.swift
//  BetterW4
//
//  Owns the notification bell: the current snapshot, its cached copy, the eight `notifications/*`
//  writes, and the 60-second foreground poll.
//
//  Spec: `features.md` §1.8, plan item 5.6, decision D-23, bug B8.
//
//  HOW THE BELL STAYS CURRENT, IN ORDER OF PREFERENCE
//
//    1. **Free.** `#header div.notifications` is in the chrome of every authenticated page, so
//       ``apply(pageHTML:origin:)`` — fed by `ChromeObserver` from pages other repositories already
//       fetched — refreshes the bell with zero extra requests.
//    2. **A fragment.** Every one of W4's own `$.post` endpoints answers with the replacement markup
//       for `div.notifications` (`notifications.js:59-69`), so every mutation re-parses what came
//       back and *replaces* the snapshot instead of assuming the write did what we asked.
//    3. **A poll.** `notifications/refresh`, every 60 s, **only while the sheet is closed** and the
//       app is foregrounded, always `.opportunistic` — the same rule W4's own
//       `notifications.js:51-57` follows. The interval is `CachePolicy.ttl(for: .chrome)`; there is
//       no lifetime literal in this file.
//
//  BUG B8. Zero notifications is the *normal* state at this school: `div.notifications` is empty in
//  both real captures. An empty snapshot is therefore a success, never a failure, and never a reason
//  to retry.
//
//  THE GATE THAT MATTERS. `W4NotificationParser.parse` falls through to `document.body()` when it
//  finds no bell markup, and an arbitrary document has no rows — so feeding it a login page, a PDF
//  or a 404 would silently *clear* a populated bell. ``apply(pageHTML:origin:)`` therefore requires
//  `ChromeObserver.carriesChrome` first. ``applyFragment(_:)`` skips that gate on purpose: a
//  `notifications/refresh` payload is not a page and never carries `#user-panel`.
//
//  WHAT GETS CACHED. The parsed ``W4NotificationSnapshot``, JSON-encoded into `W4PageCache` under
//  `W4Surface.chrome` — see the note in `CampusStatusRepository` for why the snapshot rather than
//  the page.
//

import Foundation

// MARK: - Write errors

/// A bell action that cannot be posted as asked.
enum NotificationWriteError: Error, LocalizedError, Equatable {

    /// `read` / `clear` need a `data-notification-id`; `readgroup` / `cleargroup` need a
    /// `data-notification-type`. OQ-9: never invent one — an invented id posts garbage at the
    /// server and reports success for something that did not happen.
    case identifierRequired(W4NotificationAction)

    var errorDescription: String? {
        switch self {
        case .identifierRequired(let action):
            return "That notification cannot be updated — W4 needs an identifier for \(action.rawValue)"
        }
    }
}

// MARK: - Repository

actor NotificationRepository {

    static let shared = NotificationRepository()

    /// The bell shares the `chrome` surface with the campus chip; the key keeps the two apart.
    static let cacheKey = "notifications"
    private static let surface: W4Surface = .chrome
    private static let cacheContentType = "application/json; charset=utf-8"

    // MARK: Dependencies

    private let client: W4ChromeTransport
    private let cache: W4PageCache
    private let resolveContext: W4ChromeContextResolver
    private let updates = ChromeBroadcast<W4Loaded<W4NotificationSnapshot>>()

    // MARK: State

    private var latest: W4NotificationSnapshot?
    private var latestFetchedAt: Date?
    private var latestUwcId: String?
    private var isDemoSession = false
    private var didReadDisk = false

    /// The sheet is open ⇒ the poll pauses. W4's own JS gates on the dropdown being visible, and
    /// refreshing the list under the student's finger would reshuffle what they are tapping.
    private var isSheetOpen = false
    private var isForegroundActive = true
    private var pollTask: Task<Void, Never>?

    init(
        client: W4ChromeTransport = W4ChromeClient(),
        cache: W4PageCache = .shared,
        resolveContext: @escaping W4ChromeContextResolver = { try W4RequestContext.require() }
    ) {
        self.client = client
        self.cache = cache
        self.resolveContext = resolveContext
    }

    // MARK: - Observation

    nonisolated func updatesStream() -> AsyncStream<W4Loaded<W4NotificationSnapshot>> {
        updates.stream()
    }

    /// The last known bell, with no I/O.
    func snapshot() -> W4Loaded<W4NotificationSnapshot>? {
        held(now: TimeProvider.now)
    }

    // MARK: - Reading

    /// The persisted copy, with no network request.
    @discardableResult
    func loadCached() async -> W4Loaded<W4NotificationSnapshot>? {
        guard let context = try? resolveContext() else { return nil }
        adopt(context)
        if context.isDemo {
            return record(Self.demoSnapshot, fetchedAt: TimeProvider.now, freshness: .demo)
        }
        await primeFromDisk(uwcId: context.uwcId)
        return held(now: TimeProvider.now)
    }

    /// Cache-first read, then `notifications/refresh` when the cached copy is missing or stale.
    ///
    /// Uses the AJAX refresh rather than a page fetch: the fragment is a few hundred bytes where
    /// `site/index` is sixteen kilobytes, and the bell is the only thing being asked for.
    @discardableResult
    func load(
        forceRefresh: Bool = false,
        priority: FetchPriority = .important
    ) async throws -> W4Loaded<W4NotificationSnapshot> {
        let context = try resolveContext()
        adopt(context)
        let now = TimeProvider.now

        if context.isDemo {
            return record(latest ?? Self.demoSnapshot, fetchedAt: now, freshness: .demo)
        }

        if !forceRefresh, let fresh = heldIfFresh(now: now) { return fresh }
        await primeFromDisk(uwcId: context.uwcId)
        if !forceRefresh, let fresh = heldIfFresh(now: now) { return fresh }

        return try await refresh(priority: priority)
    }

    /// `POST notifications/refresh`, degrading to the held copy on anything but a dead session.
    @discardableResult
    func refresh(priority: FetchPriority = .important) async throws -> W4Loaded<W4NotificationSnapshot> {
        do {
            return try await perform(.refresh, priority: priority)
        } catch {
            if ChromeFailure.mustPropagate(error) { throw error }
            if let cached = held(now: TimeProvider.now) { return cached }
            throw error
        }
    }

    // MARK: - Harvesting

    /// Reads the bell out of a page somebody else fetched. Never makes a request.
    @discardableResult
    func apply(
        pageHTML html: String,
        origin: ChromePageOrigin = .live
    ) async -> W4Loaded<W4NotificationSnapshot>? {
        guard let context = try? resolveContext() else { return nil }
        adopt(context)
        guard !context.isDemo else { return nil }
        guard ChromeObserver.carriesChrome(html) else { return nil }

        let now = TimeProvider.now
        let fetchedAt = origin.fetchedAt(now: now)
        if let existing = latestFetchedAt, fetchedAt < existing { return held(now: now) }

        let snapshot = W4NotificationParser.parse(html)
        let shouldPersist = latest != snapshot
            || latestFetchedAt == nil
            || !CachePolicy.isFresh(latestFetchedAt ?? .distantPast, for: Self.surface, now: fetchedAt)

        let loaded = record(snapshot, fetchedAt: fetchedAt, freshness: origin.freshness(now: now))
        if shouldPersist {
            await persist(snapshot, fetchedAt: fetchedAt, uwcId: context.uwcId)
        }
        return loaded
    }

    /// Reads a `notifications/*` response fragment. **Skips the page gate on purpose** — the
    /// fragment is a bare wrapper whose children are the new bell (`notifications.js:65`), so it
    /// carries no `#user-panel` and never will.
    ///
    /// An empty fragment legitimately means "the bell is now empty", which is exactly what W4's own
    /// JS does with it.
    @discardableResult
    func applyFragment(_ html: String) async -> W4Loaded<W4NotificationSnapshot> {
        let now = TimeProvider.now
        let snapshot = W4NotificationParser.parse(html)
        let loaded = record(snapshot, fetchedAt: now, freshness: .fresh)
        if let uwcId = latestUwcId, !isDemoSession {
            await persist(snapshot, fetchedAt: now, uwcId: uwcId)
        }
        return loaded
    }

    // MARK: - Writing

    /// The one write path. Every action posts through W4's own jQuery endpoint and replaces the
    /// snapshot with whatever fragment came back.
    ///
    /// `identifier` is the `data-notification-id` for ``W4NotificationAction/read`` /
    /// ``W4NotificationAction/clear`` and the `data-notification-type` for the group actions.
    @discardableResult
    func perform(
        _ action: W4NotificationAction,
        identifier: String? = nil,
        priority: FetchPriority = .important
    ) async throws -> W4Loaded<W4NotificationSnapshot> {
        let context = try resolveContext()
        adopt(context)

        guard let fields = action.body(identifier) else {
            throw NotificationWriteError.identifierRequired(action)
        }

        let now = TimeProvider.now
        if context.isDemo {
            let base = latest ?? Self.demoSnapshot
            return record(
                Self.demoResult(of: action, identifier: identifier, in: base),
                fetchedAt: now,
                freshness: .demo
            )
        }

        let response = try await client.postAjax(
            route: action.route,
            fields: fields,
            credentials: context.credentials,
            studentId: context.uwcId,
            priority: priority
        )
        return await applyFragment(response.html)
    }

    @discardableResult
    func markRead(id: String, priority: FetchPriority = .important) async throws -> W4Loaded<W4NotificationSnapshot> {
        try await perform(.read, identifier: id, priority: priority)
    }

    @discardableResult
    func markGroupRead(type: String, priority: FetchPriority = .important) async throws -> W4Loaded<W4NotificationSnapshot> {
        try await perform(.readGroup, identifier: type, priority: priority)
    }

    @discardableResult
    func markAllRead(priority: FetchPriority = .important) async throws -> W4Loaded<W4NotificationSnapshot> {
        try await perform(.readAll, priority: priority)
    }

    @discardableResult
    func markAllEmailsRead(priority: FetchPriority = .important) async throws -> W4Loaded<W4NotificationSnapshot> {
        try await perform(.readAllEmails, priority: priority)
    }

    @discardableResult
    func clear(id: String, priority: FetchPriority = .important) async throws -> W4Loaded<W4NotificationSnapshot> {
        try await perform(.clear, identifier: id, priority: priority)
    }

    @discardableResult
    func clearGroup(type: String, priority: FetchPriority = .important) async throws -> W4Loaded<W4NotificationSnapshot> {
        try await perform(.clearGroup, identifier: type, priority: priority)
    }

    @discardableResult
    func clearAll(priority: FetchPriority = .important) async throws -> W4Loaded<W4NotificationSnapshot> {
        try await perform(.clearAll, priority: priority)
    }

    // MARK: - Polling

    /// 60 s, from `CachePolicy` — the same number W4's own `setInterval` uses.
    static var pollInterval: TimeInterval { CachePolicy.ttl(for: Self.surface) }

    /// True only when a poll tick is allowed to fire: foregrounded, sheet closed, signed in, live.
    ///
    /// Exposed so the rule can be tested without waiting a minute for a timer.
    func shouldPoll() -> Bool {
        guard isForegroundActive, !isSheetOpen else { return false }
        guard let context = try? resolveContext() else { return false }
        return !context.isDemo
    }

    /// The sheet is open ⇒ no polling (`notifications.js:52`).
    func setSheetOpen(_ isOpen: Bool) {
        isSheetOpen = isOpen
    }

    func setForegroundActive(_ isActive: Bool) {
        isForegroundActive = isActive
        if !isActive { stopPolling() }
    }

    /// Starts the foreground poll. Idempotent.
    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func pollLoop() async {
        let interval = Self.pollInterval
        guard interval.isFinite, interval > 0 else { return }
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            } catch {
                return // cancelled
            }
            guard !Task.isCancelled else { return }
            guard shouldPoll() else { continue }
            do {
                // Never `.important`: all W4 traffic shares one serial gate, and a background bell
                // refresh must not queue ahead of the screen the student is looking at.
                _ = try await perform(.refresh, priority: .opportunistic)
            } catch {
                // A dead session ends the loop — the app is about to log out, and hammering a
                // dead PHPSESSID every minute helps nobody. Everything else is transient.
                if ChromeFailure.mustPropagate(error) {
                    pollTask = nil
                    return
                }
            }
        }
    }

    // MARK: - Teardown

    /// Logout / "Clear cache". Named `reset` rather than `clear` because "clear" is W4's own word
    /// for dismissing a notification — see ``clear(id:priority:)``.
    func reset() async {
        stopPolling()
        let uwcId = latestUwcId
        latest = nil
        latestFetchedAt = nil
        latestUwcId = nil
        isDemoSession = false
        didReadDisk = false
        isSheetOpen = false
        if let uwcId {
            await cache.remove(surface: Self.surface, key: Self.cacheKey, uwcId: uwcId)
        }
    }

    // MARK: - State plumbing

    private func adopt(_ context: W4RequestContext) {
        isDemoSession = context.isDemo
        guard latestUwcId != context.uwcId else { return }
        latestUwcId = context.uwcId
        latest = nil
        latestFetchedAt = nil
        didReadDisk = false
    }

    @discardableResult
    private func record(
        _ snapshot: W4NotificationSnapshot,
        fetchedAt: Date,
        freshness: W4Freshness
    ) -> W4Loaded<W4NotificationSnapshot> {
        latest = snapshot
        latestFetchedAt = fetchedAt
        let loaded = W4Loaded(snapshot, freshness: freshness)
        updates.send(loaded)
        return loaded
    }

    private func held(now: Date) -> W4Loaded<W4NotificationSnapshot>? {
        guard let snapshot = latest, let fetchedAt = latestFetchedAt else { return nil }
        if isDemoSession { return W4Loaded(snapshot, freshness: .demo) }
        return W4Loaded(
            snapshot,
            freshness: .cached(
                fetchedAt: fetchedAt,
                isStale: !CachePolicy.isFresh(fetchedAt, for: Self.surface, now: now)
            )
        )
    }

    private func heldIfFresh(now: Date) -> W4Loaded<W4NotificationSnapshot>? {
        guard let candidate = held(now: now) else { return nil }
        if case .cached(_, let isStale) = candidate.freshness, isStale { return nil }
        return candidate
    }

    // MARK: - Disk

    private func primeFromDisk(uwcId: String) async {
        guard !didReadDisk else { return }
        didReadDisk = true
        guard latest == nil else { return }
        guard let page = await cache.page(surface: Self.surface, key: Self.cacheKey, uwcId: uwcId),
              let data = page.html.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(W4NotificationSnapshot.self, from: data) else { return }
        latest = snapshot
        latestFetchedAt = page.fetchedAt
    }

    private func persist(_ snapshot: W4NotificationSnapshot, fetchedAt: Date, uwcId: String) async {
        guard let data = try? JSONEncoder().encode(snapshot),
              let json = String(data: data, encoding: .utf8) else { return }
        await cache.store(
            html: json,
            surface: Self.surface,
            key: Self.cacheKey,
            uwcId: uwcId,
            finalURL: nil,
            contentType: Self.cacheContentType,
            fetchedAt: fetchedAt
        )
    }

    // MARK: - Demo

    /// What App Review sees. The real bell is empty at this school (bug B8), but an empty bell is
    /// not a demo of anything, so the demo session carries three plausible rows.
    static let demoSnapshot = W4NotificationSnapshot(
        count: 3,
        severity: .overdue,
        taskGroups: [
            W4NotificationGroup(
                type: "assessment",
                title: "Assessments",
                severity: .overdue,
                items: [
                    W4Notification(
                        id: "demo-assessment-1",
                        title: "Biology IA draft",
                        subtitle: "Due 2 days ago",
                        route: W4Routes.R.assessments,
                        href: "/index.php?r=\(W4Routes.R.assessments)",
                        type: "assessment",
                        section: .task,
                        severity: .overdue
                    ),
                    W4Notification(
                        id: "demo-assessment-2",
                        title: "History essay",
                        subtitle: "Due in 3 days",
                        route: W4Routes.R.assessments,
                        href: "/index.php?r=\(W4Routes.R.assessments)",
                        type: "assessment",
                        section: .task,
                        severity: .new
                    )
                ]
            )
        ],
        emailGroups: [
            W4NotificationGroup(
                type: "email",
                title: "Inbox",
                severity: .new,
                items: [
                    W4Notification(
                        id: "demo-email-1",
                        title: "Kayaking trip briefing",
                        subtitle: "2 days ago",
                        route: W4Routes.R.mailerInbox,
                        href: "/index.php?r=\(W4Routes.R.mailerInbox)",
                        type: "email",
                        section: .email,
                        severity: .new
                    )
                ]
            )
        ]
    )

    /// What a demo session's bell looks like after one action: `read*` downgrades the matched rows
    /// to `.normal`, `clear*` removes them. Pure, so it is testable on its own.
    static func demoResult(
        of action: W4NotificationAction,
        identifier: String?,
        in snapshot: W4NotificationSnapshot
    ) -> W4NotificationSnapshot {
        guard action != .refresh else { return snapshot }
        let removes: Bool
        switch action {
        case .clear, .clearGroup, .clearAll: removes = true
        default: removes = false
        }

        func matches(_ group: W4NotificationGroup, _ item: W4Notification) -> Bool {
            switch action {
            case .read, .clear:
                return item.id == identifier
            case .readGroup, .clearGroup:
                return (item.type ?? group.type) == identifier
            case .readAll, .clearAll:
                return true
            case .readAllEmails:
                return item.section == .email
            case .refresh:
                return false
            }
        }

        func rebuild(_ group: W4NotificationGroup) -> W4NotificationGroup? {
            var items: [W4Notification] = []
            for item in group.items {
                guard matches(group, item) else {
                    items.append(item)
                    continue
                }
                if removes { continue }
                items.append(
                    W4Notification(
                        id: item.id,
                        title: item.title,
                        subtitle: item.subtitle,
                        route: item.route,
                        href: item.href,
                        type: item.type,
                        section: item.section,
                        severity: .normal
                    )
                )
            }
            guard !items.isEmpty else { return nil }
            return W4NotificationGroup(
                type: group.type,
                title: group.title,
                severity: severity(of: items),
                items: items
            )
        }

        let tasks = snapshot.taskGroups.compactMap(rebuild)
        let emails = snapshot.emailGroups.compactMap(rebuild)
        let all = tasks.flatMap(\.items) + emails.flatMap(\.items)
        return W4NotificationSnapshot(
            count: all.filter { $0.severity != .normal }.count,
            severity: severity(of: all),
            taskGroups: tasks,
            emailGroups: emails
        )
    }

    private static func severity(of items: [W4Notification]) -> W4NotificationSeverity {
        if items.contains(where: { $0.severity == .overdue }) { return .overdue }
        if items.contains(where: { $0.severity == .new }) { return .new }
        return .normal
    }
}
