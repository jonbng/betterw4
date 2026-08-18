//
//  ResourceRepository.swift
//  BetterW4
//
//  `r=academics/resources/resources` — room and space bookings (features.md §1.15, §2.5;
//  plan Wave 5 item 5.8).
//
//  Read-only in v1, by decision, not by omission: features.md §1.15 says *"v1: read-only month list;
//  booking is v1.5"*, and the booking form's field names (`day`, `month`, `year`, `reservation_id`,
//  `time_start`, `time_end`, `description`, `resource_id`) are known only from README §5.2 prose —
//  no capture, no `formSelector`, no idea which submit button W4 expects. Posting a booking on a
//  guess would put a real reservation in a real room.
//
//  Same honesty rule as `ExtraAcademicsRepository`: the page has never been captured, so there is
//  no `W4ResourceParser` to call and this repository does not invent one. It resolves the session,
//  refuses the network in demo, fetches the verified route (`references/pages/Academics.html:77`),
//  honours `CachePolicy.ttl(for: .resources)`, caches to disk, survives a failed refresh on the
//  cached copy, and propagates `.sessionExpired`. Callers render `W4PageSnapshot.contentFragmentHTML`
//  until a capture arrives.
//
//  Month paging is deliberately **not** implemented. W4 almost certainly accepts month/year
//  parameters, but "almost certainly" is how you ship a screen that silently shows the wrong month
//  — the same trap D-18 avoids for timetable week paging. v1 fetches the bare route and shows what
//  W4 chose to render.
//

import Foundation

// MARK: - Repository

actor ResourceRepository {

    static let shared = ResourceRepository()

    /// The cache shelf for the resource list. One page, one key.
    static let cacheKey = W4Routes.R.resources

    private let loader: W4PageLoader
    private let cache: W4PageCache
    private let resolveContext: @Sendable () throws -> W4RequestContext

    init(
        client: any W4RouteFetching = W4HTTPClient(),
        cache: W4PageCache = .shared,
        context: @escaping @Sendable () throws -> W4RequestContext = { try W4RequestContext.require() }
    ) {
        self.loader = W4PageLoader(client: client, cache: cache)
        self.cache = cache
        self.resolveContext = context
    }

    private var target: W4PageTarget {
        W4PageTarget(surface: .resources, cacheKey: Self.cacheKey, route: W4Routes.R.resources)
    }

    // MARK: - Reading

    /// The bookable-resources page, cache-first.
    func resources(
        forceRefresh: Bool = false,
        priority: FetchPriority = .important
    ) async throws -> W4Loaded<W4PageSnapshot> {
        let context = try resolveContext()
        if context.isDemo {
            return W4Loaded(Self.demoPage(), freshness: .demo)
        }
        return try await loader.load(
            target,
            context: context,
            forceRefresh: forceRefresh,
            priority: priority
        )
    }

    /// The cached copy only. Never fetches, never throws.
    func cachedResources() async -> W4Loaded<W4PageSnapshot>? {
        guard let context = try? resolveContext() else { return nil }
        if context.isDemo {
            return W4Loaded(Self.demoPage(), freshness: .demo)
        }
        return await loader.cached(target, context: context)
    }

    func invalidate() async {
        guard let context = try? resolveContext() else { return }
        await cache.remove(surface: .resources, key: Self.cacheKey, uwcId: context.uwcId)
    }

    // MARK: - Demo

    /// Named, real rooms would be fabricated school data; a labelled placeholder is not.
    static func demoPage(now: Date = TimeProvider.now) -> W4PageSnapshot {
        let html = """
        <html><body><div id="content_inner">\
        <h2>Resources</h2>\
        <p>Resource bookings are not available in the demo account.</p>\
        </div></body></html>
        """
        return W4PageSnapshot(html: html, fetchedAt: now, finalURL: nil)
    }
}
