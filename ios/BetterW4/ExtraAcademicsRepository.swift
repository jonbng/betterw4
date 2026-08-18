//
//  ExtraAcademicsRepository.swift
//  BetterW4
//
//  Extra Academics: My activities, My EA diary, My portfolio, My CAS interviews, My SafetyNet
//  (features.md §1.11, §2.5; plan Wave 5 item 5.8).
//
//  ── What this repository does NOT do, and why ──────────────────────────────────────────────────
//
//  It does not parse activity rows, diary entries, portfolio items, interview statuses or SafetyNet
//  wellness numbers — because **none of those pages has ever been captured**. features.md §1.11 says
//  so in as many words: *"Every markup detail across this whole section is UNKNOWN — needs live
//  capture."* The only Extra Academics capture in `references/` is the section's landing page, which
//  is a navigation menu and nothing else.
//
//  Writing selectors against markup nobody has seen does not produce a parser; it produces a
//  function that returns `[]` on the real site while every fixture test passes. So this repository
//  does the part that is genuinely knowable now — resolve the session, branch on demo, fetch the
//  right route, respect the TTL in `CachePolicy`, cache to disk, fall back to the cached copy when
//  the network fails, and never swallow `.sessionExpired` — and hands back the page itself.
//
//  Callers get `W4PageSnapshot`, whose `contentFragmentHTML` is the inner HTML of `#content_inner`
//  — W4's per-page content well, verified on 19 of the 20 fixtures. That renders through
//  `HTMLContentRenderer` today and is replaced field-by-field the moment someone captures these
//  five pages — they are on the open-captures list in features.md §7.
//
//  The routes themselves are **[V]**: every one below is copied from the `#dynamic_menu_extraacademics`
//  block of `BetterW4Tests/Fixtures/W4/extraacademics-menu.html`.
//

import Foundation

// MARK: - Pages

/// The five Extra Academics surfaces this repository serves. Routes are **[V]** from the EA menu
/// capture; `W4Routes.R` is the single place they are spelled.
enum ExtraAcademicsPage: String, CaseIterable, Sendable {
    /// `My activities` — the running / past / future list.
    case myActivities
    /// `My EA diary`.
    case diary
    /// `My portfolio`.
    case portfolio
    /// `My CAS interviews` — three per student.
    case interviews
    /// `My SafetyNet` — the weekly wellness report.
    case safetyNet

    var route: String {
        switch self {
        case .myActivities: return W4Routes.R.eaActivities
        case .diary: return W4Routes.R.eaDiary
        case .portfolio: return W4Routes.R.eaPortfolio
        case .interviews: return W4Routes.R.eaInterviews
        case .safetyNet: return W4Routes.R.eaSafetyNet
        }
    }

    /// Matches the label W4's own menu uses **[V]**, so a heading in the app and a heading on the
    /// site never disagree.
    var displayName: String {
        switch self {
        case .myActivities: return "My activities"
        case .diary: return "My EA diary"
        case .portfolio: return "My portfolio"
        case .interviews: return "My CAS interviews"
        case .safetyNet: return "My SafetyNet"
        }
    }
}

// MARK: - Repository

actor ExtraAcademicsRepository {

    static let shared = ExtraAcademicsRepository()

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

    private func target(for page: ExtraAcademicsPage) -> W4PageTarget {
        // One cache key per page. `W4Surface.extraAcademics` owns the TTL for all five.
        W4PageTarget(surface: .extraAcademics, cacheKey: page.route, route: page.route)
    }

    // MARK: - Reading

    /// One Extra Academics page, cache-first.
    ///
    /// Leave `priority` at `.important` only while the user is waiting on this screen; pass
    /// `.opportunistic` for prefetch or background warming. All W4 traffic shares one serial gate,
    /// so a greedy prefetch here delays whatever the user is actually looking at.
    func page(
        _ page: ExtraAcademicsPage,
        forceRefresh: Bool = false,
        priority: FetchPriority = .important
    ) async throws -> W4Loaded<W4PageSnapshot> {
        let context = try resolveContext()
        if context.isDemo {
            return W4Loaded(Self.demoPage(page), freshness: .demo)
        }
        return try await loader.load(
            target(for: page),
            context: context,
            forceRefresh: forceRefresh,
            priority: priority
        )
    }

    /// The cached copy only. Never fetches, never throws.
    func cachedPage(_ page: ExtraAcademicsPage) async -> W4Loaded<W4PageSnapshot>? {
        guard let context = try? resolveContext() else { return nil }
        if context.isDemo {
            return W4Loaded(Self.demoPage(page), freshness: .demo)
        }
        return await loader.cached(target(for: page), context: context)
    }

    /// Drop one cached page, or all five when `page` is nil.
    func invalidate(_ page: ExtraAcademicsPage? = nil) async {
        guard let context = try? resolveContext() else { return }
        let pages = page.map { [$0] } ?? ExtraAcademicsPage.allCases
        for one in pages {
            await cache.remove(surface: .extraAcademics, key: one.route, uwcId: context.uwcId)
        }
    }

    // MARK: - Demo

    /// A demo session gets a plainly-labelled placeholder rather than fabricated activity rows.
    /// An App Review account can see the screen exists; it is not shown invented school data.
    static func demoPage(
        _ page: ExtraAcademicsPage,
        now: Date = TimeProvider.now
    ) -> W4PageSnapshot {
        let html = """
        <html><body><div id="content_inner">\
        <h2>\(page.displayName)</h2>\
        <p>Extra Academics is not available in the demo account.</p>\
        </div></body></html>
        """
        return W4PageSnapshot(html: html, fetchedAt: now, finalURL: nil)
    }
}
