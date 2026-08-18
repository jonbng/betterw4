//
//  DocumentRepository.swift
//  BetterW4
//
//  The W4 Documents CMS as a repository: `documents/index` (School) and
//  `extraacademics/documents` (Extra Academics) — the same renderer behind two entry points, so
//  one repository serves both (features.md §1.10, W4_PORT_PLAN.md Wave 5 item 5.8).
//
//  Documents is the one surface in this wave that is a *tree*. A student opens a folder, reads a
//  page, taps back, opens the next folder. Caching "the documents page" as a single blob would
//  make every one of those taps a network round trip on a school server that serves ~200 students
//  from one small Apache box. So every node — the root, each folder, each page — is cached under
//  its own key, derived from its own route, and a node that is still inside its TTL is returned
//  without touching the network at all.
//
//  THIS FILE ALSO CARRIES THE TRANSPORT SEAM shared by the four Wave 5.8a repositories
//  (`DocumentRepository`, `TripRepository`, `TravelRepository`, `GradeRepository`):
//  `W4SecondaryPage`, `W4SecondaryFetching` and `W4SecondaryPageLoader` are declared below and
//  used by all four. They live here rather than in a fifth file because item 5.8a owns exactly
//  four files; the alternative was copying the same forty lines of cache policy four times, which
//  is how four subtly different cache policies get born.
//

import Foundation

// MARK: - Transport seam

/// One fetched W4 page, reduced to what a repository actually stores.
///
/// The HTTP client hands back `Data` plus a final URL; the cache wants a `String` plus the same
/// final URL. This is that boundary, and it is also the seam a test stubs: no test in this module
/// ever has to build a `URLSession`, a cookie jar or a `W4Credentials` that means anything.
struct W4SecondaryPage: Sendable {
    let html: String
    /// Where the request actually landed, after redirects. Stored in the cache sidecar so a later
    /// reader can tell a folder page from the login page it silently became.
    let finalURL: URL?
    let contentType: String?

    init(html: String, finalURL: URL? = nil, contentType: String? = nil) {
        self.html = html
        self.finalURL = finalURL
        self.contentType = contentType
    }
}

/// The single transport call the secondary repositories make: GET a Yii route, get HTML back.
///
/// Deliberately narrower than `W4HTTPClient`. These four surfaces are read-only in v1
/// (features.md §1.9 for trips and travel; §1.10 for documents), so a repository that could POST
/// would be a repository that might.
protocol W4SecondaryFetching {
    func fetchSecondaryPage(
        route: String,
        query: [String: String],
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority
    ) async throws -> W4SecondaryPage
}

extension W4HTTPClient: W4SecondaryFetching {
    func fetchSecondaryPage(
        route: String,
        query: [String: String],
        credentials: W4Credentials,
        studentId: String?,
        priority: FetchPriority
    ) async throws -> W4SecondaryPage {
        let response = try await get(
            route: route,
            query: query,
            credentials: credentials,
            studentId: studentId,
            priority: priority
        )
        return W4SecondaryPage(
            html: decodeHTML(from: response.data),
            finalURL: response.finalURL,
            contentType: "text/html"
        )
    }
}

// MARK: - Cache-first page loading

/// Cache policy for the secondary surfaces, written once.
///
/// The rules, in the order they are applied:
///
///   1. A cached page still inside its surface's TTL is returned as-is and **no request is made**.
///      That is what makes navigating back into a folder instant.
///   2. Otherwise fetch, store, and report `.fresh`.
///   3. If the fetch fails and there is a cached copy — even a stale one — return the cached copy
///      rather than an error. Offline with a warm cache is a working app (features.md §3 rule 4).
///   4. Except for the errors that must never be swallowed: `W4Error.sessionExpired` has to reach
///      the app so it can re-login, and a cancelled task must stay cancelled. `W4Error.forbidden`
///      is deliberately *not* in that list — 403 without "Login Required" means wrong role, not a
///      dead session, and a student who opens a staff-only page must not be logged out
///      (features.md §3 rule 6).
///
/// No TTL is written here: `CachePolicy.ttl(for:)` is the only place a lifetime exists.
enum W4SecondaryPageLoader {

    /// Loads the HTML for one surface + key, cache-first.
    ///
    /// - Parameter forceRefresh: skips rule 1 only. A failed forced refresh still falls back to
    ///   the cached copy, so pull-to-refresh on a train never blanks the screen.
    static func loadHTML(
        surface: W4Surface,
        key: String,
        route: String,
        query: [String: String] = [:],
        forceRefresh: Bool,
        priority: FetchPriority,
        context: W4RequestContext,
        client: any W4SecondaryFetching,
        cache: W4PageCache
    ) async throws -> W4Loaded<String> {
        let cached = await cache.page(surface: surface, key: key, uwcId: context.uwcId)

        if !forceRefresh, let cached, !cached.isStale {
            return W4Loaded(cached.html, freshness: .cached(fetchedAt: cached.fetchedAt, isStale: false))
        }

        do {
            let page = try await client.fetchSecondaryPage(
                route: route,
                query: query,
                credentials: context.credentials,
                studentId: context.uwcId,
                priority: priority
            )
            let fetchedAt = TimeProvider.now
            await cache.store(
                html: page.html,
                surface: surface,
                key: key,
                uwcId: context.uwcId,
                finalURL: page.finalURL,
                contentType: page.contentType,
                fetchedAt: fetchedAt
            )
            return W4Loaded(page.html, freshness: .fresh)
        } catch {
            if mustPropagate(error) { throw error }
            guard let cached else { throw error }
            return W4Loaded(
                cached.html,
                freshness: .cached(fetchedAt: cached.fetchedAt, isStale: cached.isStale)
            )
        }
    }

    /// The cached HTML for one surface + key, stale copies included, without any network.
    ///
    /// A screen calls this to paint something in the first frame; `loadHTML` then refreshes it.
    static func cachedHTML(
        surface: W4Surface,
        key: String,
        context: W4RequestContext,
        cache: W4PageCache
    ) async -> W4Loaded<String>? {
        guard let cached = await cache.page(surface: surface, key: key, uwcId: context.uwcId) else {
            return nil
        }
        return W4Loaded(
            cached.html,
            freshness: .cached(fetchedAt: cached.fetchedAt, isStale: cached.isStale)
        )
    }

    /// Errors a stale cache must never paper over.
    static func mustPropagate(_ error: Error) -> Bool {
        if let w4 = error as? W4Error {
            // Only this one. `.forbidden`, `.httpError`, `.serverConflict` and every transport
            // failure are all better answered with yesterday's copy than with a red screen.
            if case .sessionExpired = w4 { return true }
            return false
        }
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }
}

// MARK: - Which CMS

/// The two Documents CMS roots. Same renderer, same models, two entry points (features.md §1.10).
enum DocumentLibrary: String, Codable, Sendable, CaseIterable {
    /// `documents/index` — the School CMS. The one page of it that has been captured.
    case school
    /// `extraacademics/documents` — the Extra Academics CMS. Never captured; the Home `#links`
    /// block proves `extraacademics/documents/index&page_id=79` is a real URL.
    case extraAcademics

    var rootRoute: String {
        switch self {
        case .school: return W4Routes.R.documents
        case .extraAcademics: return W4Routes.R.eaDocuments
        }
    }

    var displayName: String {
        switch self {
        case .school: return "Documents"
        case .extraAcademics: return "Extra Academics documents"
        }
    }

    /// The library a route belongs to, so a `DocumentNode.route` handed back by the parser can be
    /// followed without the caller having to remember which tree it came from.
    static func library(forRoute route: String) -> DocumentLibrary {
        let name = W4Routes.splitRouteAndQuery(route).route.lowercased()
        return name.hasPrefix("extraacademics") ? .extraAcademics : .school
    }
}

// MARK: - Repository

/// Reads the Documents CMS, one node at a time, cache-first.
///
/// An `actor` because several screens (a folder list and the page it pushed) can be loading at
/// once, and because `W4PageCache` is an actor underneath — nothing here touches UIKit, so nothing
/// here belongs on the main actor.
actor DocumentRepository {

    private let client: any W4SecondaryFetching
    private let cache: W4PageCache
    private let resolveContext: @Sendable () throws -> W4RequestContext

    /// - Parameter resolveContext: the session lookup, injectable so a test can run against a
    ///   synthetic student without a Keychain. Production resolves the real signed-in session and
    ///   throws `.sessionExpired` / `.missingCookies` when there is none.
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

    // MARK: Navigation

    /// The CMS root of `library`.
    func loadRoot(
        library: DocumentLibrary = .school,
        forceRefresh: Bool = false,
        priority: FetchPriority = .important
    ) async throws -> W4Loaded<DocumentListing> {
        try await load(route: library.rootRoute, forceRefresh: forceRefresh, priority: priority)
    }

    /// One folder, by its `folder_id`.
    func loadFolder(
        id: String,
        library: DocumentLibrary = .school,
        forceRefresh: Bool = false,
        priority: FetchPriority = .important
    ) async throws -> W4Loaded<DocumentListing> {
        try await load(
            route: "\(library.rootRoute)&folder_id=\(id)",
            forceRefresh: forceRefresh,
            priority: priority
        )
    }

    /// One rendered leaf page, by its `page_id`.
    func loadPage(
        id: String,
        library: DocumentLibrary = .school,
        forceRefresh: Bool = false,
        priority: FetchPriority = .important
    ) async throws -> W4Loaded<DocumentListing> {
        try await load(
            route: "\(library.rootRoute)&page_id=\(id)",
            forceRefresh: forceRefresh,
            priority: priority
        )
    }

    /// Follows a node the parser produced.
    ///
    /// Prefers the node's own `route` — that is what W4 linked — and only falls back to rebuilding
    /// a route from `id` + `kind` when the anchor was not a recognisable `index.php?r=…` link.
    /// A node with neither is an external link and is the caller's problem, not this repository's:
    /// it throws rather than inventing a request.
    func load(
        node: DocumentNode,
        library: DocumentLibrary = .school,
        forceRefresh: Bool = false,
        priority: FetchPriority = .important
    ) async throws -> W4Loaded<DocumentListing> {
        if let route = node.route, !route.isEmpty {
            return try await load(route: route, forceRefresh: forceRefresh, priority: priority)
        }
        guard !node.id.isEmpty, node.id != node.href else {
            throw W4Error.notPortedToW4(
                host: URL(string: node.href)?.host ?? "unknown",
                context: "documents node \"\(node.title)\" is not a W4 route"
            )
        }
        switch node.kind {
        case .folder:
            return try await loadFolder(
                id: node.id, library: library, forceRefresh: forceRefresh, priority: priority
            )
        case .page:
            return try await loadPage(
                id: node.id, library: library, forceRefresh: forceRefresh, priority: priority
            )
        }
    }

    /// The general navigator: any `documents/…` or `extraacademics/documents…` route, with its
    /// `folder_id` / `page_id` siblings carried inline exactly as `W4Routes` expects them.
    func load(
        route: String,
        forceRefresh: Bool = false,
        priority: FetchPriority = .important
    ) async throws -> W4Loaded<DocumentListing> {
        let context = try resolveContext()

        // Demo first, before anything that could reach the network. A demo session has no session
        // id at all, so there is nothing to leak even if this branch were ever missed — but it
        // must not be missed, and the ordering is the guarantee.
        if context.isDemo {
            return W4Loaded(Self.demoListing(forRoute: route), freshness: .demo)
        }

        let loaded = try await W4SecondaryPageLoader.loadHTML(
            surface: .documents,
            key: Self.cacheKey(forRoute: route),
            route: route,
            forceRefresh: forceRefresh,
            priority: priority,
            context: context,
            client: client,
            cache: cache
        )
        return loaded.map(W4DocumentsParser.parse)
    }

    // MARK: Cache

    /// The last copy of a node, however old, with no request. `nil` when nothing is stored.
    func cachedListing(forRoute route: String) async -> W4Loaded<DocumentListing>? {
        guard let context = try? resolveContext() else { return nil }
        if context.isDemo {
            return W4Loaded(Self.demoListing(forRoute: route), freshness: .demo)
        }
        let cached = await W4SecondaryPageLoader.cachedHTML(
            surface: .documents,
            key: Self.cacheKey(forRoute: route),
            context: context,
            cache: cache
        )
        return cached?.map(W4DocumentsParser.parse)
    }

    /// Drops one node from the cache, so the next `load` refetches it.
    func invalidate(route: String) async {
        guard let context = try? resolveContext(), !context.isDemo else { return }
        await cache.remove(surface: .documents, key: Self.cacheKey(forRoute: route), uwcId: context.uwcId)
    }

    // MARK: Cache keys

    /// A canonical, order-independent key for one CMS node.
    ///
    /// `documents/index&folder_id=27` and `documents/index?folder_id=27&x=1` must not collide with
    /// each other or with the root, and the same folder reached from two differently-ordered links
    /// must hit the same cache entry — hence the sort.
    static func cacheKey(forRoute route: String) -> String {
        let split = W4Routes.splitRouteAndQuery(route)
        let pairs = split.query
            .filter { !$0.name.isEmpty }
            .map { "\($0.name)=\($0.value)" }
            .sorted()
        let name = split.route.isEmpty ? W4Routes.R.documents : split.route
        return pairs.isEmpty ? name : "\(name)?\(pairs.joined(separator: "&"))"
    }

    // MARK: - Demo (features.md §4)

    /// The demo CMS: the two folders of the real capture, each holding two invented pages.
    ///
    /// Everything here is hard-coded and offline. `W4Routes.url` builds the hrefs so that demo
    /// links have the same shape as real ones and the same navigation code path exercises them.
    static func demoListing(forRoute route: String) -> DocumentListing {
        let split = W4Routes.splitRouteAndQuery(route)
        let library = DocumentLibrary.library(forRoute: route)

        func value(of name: String) -> String? {
            split.query.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
        }

        if let pageID = value(of: "page_id"), let page = demoPages[pageID] {
            return demoPageListing(page, library: library)
        }
        if let folderID = value(of: "folder_id"), let folder = demoFolders[folderID] {
            return demoFolderListing(folder, library: library)
        }
        return demoRootListing(library: library)
    }

    private struct DemoFolder {
        let id: String
        let title: String
        let pageIDs: [String]
    }

    private struct DemoPage {
        let id: String
        let folderID: String
        let title: String
        let details: String
        let bodyHTML: String
    }

    /// The two folders in the real `?r=documents` capture, with their real `folder_id`s.
    private static let demoFolders: [String: DemoFolder] = [
        "27": DemoFolder(id: "27", title: "Internal Information", pageIDs: ["870", "871"]),
        "34": DemoFolder(id: "34", title: "Outdoor Department", pageIDs: ["1004", "1005"])
    ]

    private static let demoFolderOrder = ["27", "34"]

    private static let demoPages: [String: DemoPage] = [
        "870": DemoPage(
            id: "870",
            folderID: "27",
            title: "Fire Drill Procedure",
            details: "Updated by the Operations Office",
            bodyHTML: """
                <p>When the alarm sounds, leave the building by the nearest exit and walk to the \
                assembly point outside the Main Hall. Do not stop to collect belongings.</p>
                <p>Your house leader takes the roll at the assembly point. Stay with your house \
                until you are told the drill is over.</p>
                """
        ),
        "871": DemoPage(
            id: "871",
            folderID: "27",
            title: "Laundry and Housekeeping",
            details: "Updated by the Boarding Office",
            bodyHTML: """
                <p>Each house has two laundry slots per week. The rota is posted inside the \
                laundry room and rotates at the start of every term.</p>
                <ul><li>Wash at 40&deg;C or lower.</li><li>Empty the lint filter after every \
                load.</li><li>Clothes left overnight are moved to the lost property shelf.</li></ul>
                """
        ),
        "1004": DemoPage(
            id: "1004",
            folderID: "34",
            title: "Kayaking Safety Briefing",
            details: "Updated by the Outdoor Department",
            bodyHTML: """
                <p>Buoyancy aids are worn on the water at all times, without exception. Boats go \
                out in pairs and stay within sight of the safety craft.</p>
                <p>The fjord is cold all year. If you capsize, stay with your boat and signal the \
                safety craft with a raised paddle.</p>
                """
        ),
        "1005": DemoPage(
            id: "1005",
            folderID: "34",
            title: "Hiking Kit List",
            details: "Updated by the Outdoor Department",
            bodyHTML: """
                <p>Bring a windproof jacket, a warm mid-layer, gloves, a hat, two litres of water \
                and food for the day. Cotton next to the skin is the one thing to leave behind.</p>
                <p>Boots are checked at the equipment store the afternoon before departure.</p>
                """
        )
    ]

    private static func demoRootListing(library: DocumentLibrary) -> DocumentListing {
        let items = demoFolderOrder.compactMap { demoFolders[$0] }.map { folder in
            demoNode(
                id: folder.id,
                title: folder.title,
                kind: .folder,
                parameter: "folder_id",
                library: library
            )
        }
        return DocumentListing(
            title: library.displayName,
            breadcrumb: [demoHomeCrumb],
            items: items,
            parentRoute: nil,
            page: nil
        )
    }

    private static func demoFolderListing(
        _ folder: DemoFolder,
        library: DocumentLibrary
    ) -> DocumentListing {
        let items = folder.pageIDs.compactMap { demoPages[$0] }.map { page in
            demoNode(
                id: page.id,
                title: page.title,
                kind: .page,
                parameter: "page_id",
                library: library
            )
        }
        return DocumentListing(
            title: folder.title,
            breadcrumb: [demoHomeCrumb, demoRootCrumb(library: library)],
            items: items,
            parentRoute: library.rootRoute,
            page: nil
        )
    }

    private static func demoPageListing(
        _ page: DemoPage,
        library: DocumentLibrary
    ) -> DocumentListing {
        let folder = demoFolders[page.folderID]
        var breadcrumb = [demoHomeCrumb, demoRootCrumb(library: library)]
        if let folder {
            breadcrumb.append(
                DocumentBreadcrumb(
                    title: folder.title,
                    route: "\(library.rootRoute)&folder_id=\(folder.id)",
                    href: demoHref(library: library, parameter: "folder_id", value: folder.id)
                )
            )
        }
        return DocumentListing(
            title: page.title,
            breadcrumb: breadcrumb,
            items: [],
            parentRoute: folder.map { "\(library.rootRoute)&folder_id=\($0.id)" },
            page: DocumentPage(
                title: page.title,
                details: page.details,
                contentHTML: page.bodyHTML
            )
        )
    }

    private static func demoNode(
        id: String,
        title: String,
        kind: DocumentNodeKind,
        parameter: String,
        library: DocumentLibrary
    ) -> DocumentNode {
        DocumentNode(
            id: id,
            title: title,
            kind: kind,
            route: "\(library.rootRoute)&\(parameter)=\(id)",
            href: demoHref(library: library, parameter: parameter, value: id)
        )
    }

    private static func demoHref(
        library: DocumentLibrary,
        parameter: String,
        value: String
    ) -> String {
        W4Routes.url(library.rootRoute, [parameter: value]).absoluteString
    }

    private static let demoHomeCrumb = DocumentBreadcrumb(
        title: "Home",
        route: W4Routes.R.home,
        href: W4Routes.origin + "/"
    )

    private static func demoRootCrumb(library: DocumentLibrary) -> DocumentBreadcrumb {
        DocumentBreadcrumb(
            title: library.displayName,
            route: library.rootRoute,
            href: W4Routes.url(library.rootRoute).absoluteString
        )
    }
}
