//
//  TravelRepository.swift
//  BetterW4
//
//  `academics/travel/travel.list` — "My travel forms": the four fixed journeys of the UWC RCN year
//  plus the "Manage my travel contacts" link (features.md §1.9, W4_PORT_PLAN.md Wave 5 item 5.8).
//
//  Separate from `TripRepository` on purpose. A trip is a thing a student plans; a travel form is
//  one of four fixed journeys they must file. They have different routes, different models,
//  different lifecycles and — once the contacts page is finally captured — different write paths.
//  features.md §0.2 lists them as two repositories, and this is that.
//
//  v1 is read-only: opening a form hands its `href` to the in-app browser with the session cookie
//  (D-24). Nothing here POSTs.
//
//  The transport seam and the cache-first loader live in `DocumentRepository.swift`.
//

import Foundation

/// Reads the travel-forms page and, when W4 links one, the travel-contacts page behind it.
actor TravelRepository {

    /// The travel-forms page itself. Contacts are cached under their own key, below, because the
    /// contacts page is a *different* page — caching them together would mean refetching four
    /// journey rows every time somebody checks a phone number.
    static let formsCacheKey = "travel-forms"

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

    // MARK: - Travel forms

    func loadTravelForms(
        forceRefresh: Bool = false,
        priority: FetchPriority = .important
    ) async throws -> W4Loaded<TravelPage> {
        let context = try resolveContext()
        if context.isDemo {
            return W4Loaded(Self.demoTravelPage(), freshness: .demo)
        }

        let loaded = try await W4SecondaryPageLoader.loadHTML(
            surface: .travel,
            key: Self.formsCacheKey,
            route: W4Routes.R.travel,
            forceRefresh: forceRefresh,
            priority: priority,
            context: context,
            client: client,
            cache: cache
        )
        return loaded.map(W4TripsParser.parseTravel)
    }

    /// The last travel-forms page we stored, however old, with no request.
    func cachedTravelForms() async -> W4Loaded<TravelPage>? {
        guard let context = try? resolveContext() else { return nil }
        if context.isDemo {
            return W4Loaded(Self.demoTravelPage(), freshness: .demo)
        }
        let cached = await W4SecondaryPageLoader.cachedHTML(
            surface: .travel,
            key: Self.formsCacheKey,
            context: context,
            cache: cache
        )
        return cached?.map(W4TripsParser.parseTravel)
    }

    // MARK: - Travel contacts

    /// The "Manage my travel contacts" page.
    ///
    /// The route is a parameter rather than a constant because that page has **never been
    /// captured** and `W4Routes.R` therefore has no name for it. `TravelPage.manageContactsRoute`
    /// is where the route comes from: W4 links it, we follow it, we never guess it. A caller
    /// holding only the raw `href` should pass `W4Routes.route(ofURLString:)` of it.
    func loadContacts(
        route: String,
        forceRefresh: Bool = false,
        priority: FetchPriority = .important
    ) async throws -> W4Loaded<[TravelContact]> {
        let context = try resolveContext()
        if context.isDemo {
            return W4Loaded(Self.demoContacts(), freshness: .demo)
        }

        let trimmed = route.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw W4Error.invalidURL
        }

        let loaded = try await W4SecondaryPageLoader.loadHTML(
            surface: .travel,
            key: Self.contactsCacheKey(forRoute: trimmed),
            route: trimmed,
            forceRefresh: forceRefresh,
            priority: priority,
            context: context,
            client: client,
            cache: cache
        )
        return loaded.map(W4TripsParser.parseTravelContacts)
    }

    /// Convenience: load the forms page, then its contacts link in the same call.
    ///
    /// Returns `nil` contacts — not an error — when W4 rendered no contacts link, which is the
    /// expected shape on a page we have never seen. The contacts fetch is `.opportunistic`: the
    /// student is looking at the forms list, not at the contacts page.
    func loadTravelFormsWithContacts(
        forceRefresh: Bool = false,
        priority: FetchPriority = .important
    ) async throws -> (forms: W4Loaded<TravelPage>, contacts: W4Loaded<[TravelContact]>?) {
        let context = try resolveContext()
        if context.isDemo {
            // Demo carries no contacts *link* — inventing one would be inventing a W4 route, and
            // a UI that opened it would make a network call in demo mode. The contacts themselves
            // are handed over directly instead.
            return (
                W4Loaded(Self.demoTravelPage(), freshness: .demo),
                W4Loaded(Self.demoContacts(), freshness: .demo)
            )
        }

        let forms = try await loadTravelForms(forceRefresh: forceRefresh, priority: priority)
        guard let route = forms.value.manageContactsRoute, !route.isEmpty else {
            return (forms, nil)
        }
        // A failure here must not fail the forms list the student actually asked for — except for
        // a dead session, which has to reach the app.
        do {
            let contacts = try await loadContacts(
                route: route,
                forceRefresh: forceRefresh,
                priority: .opportunistic
            )
            return (forms, contacts)
        } catch {
            if W4SecondaryPageLoader.mustPropagate(error) { throw error }
            return (forms, nil)
        }
    }

    // MARK: - Cache

    /// Drops the cached forms page. Contacts keep their own entry and are dropped by
    /// `invalidateContacts(route:)`.
    func invalidate() async {
        guard let context = try? resolveContext(), !context.isDemo else { return }
        await cache.remove(surface: .travel, key: Self.formsCacheKey, uwcId: context.uwcId)
    }

    func invalidateContacts(route: String) async {
        guard let context = try? resolveContext(), !context.isDemo else { return }
        await cache.remove(
            surface: .travel,
            key: Self.contactsCacheKey(forRoute: route),
            uwcId: context.uwcId
        )
    }

    /// Namespaced so a contacts page can never collide with the forms page, and canonicalised so
    /// the same page reached through two differently-ordered links hits one entry.
    static func contactsCacheKey(forRoute route: String) -> String {
        let split = W4Routes.splitRouteAndQuery(route)
        let pairs = split.query
            .filter { !$0.name.isEmpty }
            .map { "\($0.name)=\($0.value)" }
            .sorted()
        let name = split.route.isEmpty ? W4Routes.R.travel : split.route
        return pairs.isEmpty ? "travel-contacts|\(name)" : "travel-contacts|\(name)?\(pairs.joined(separator: "&"))"
    }

    // MARK: - Demo (features.md §4)

    /// The four journeys, with the statuses features.md §4 specifies:
    /// submitted / not started / not started / not started.
    static func demoTravelPage() -> TravelPage {
        let statuses: [TravelJourney: String] = [
            .toSchoolAutumn: "Submitted",
            .homeWinter: "Not started",
            .backAfterWinter: "Not started",
            .homeSummer: "Not started"
        ]

        let forms = TravelJourney.allCases
            .sorted { $0.order < $1.order }
            .map { journey in
                TravelForm(
                    id: "demo-travel-\(journey.rawValue)",
                    journey: journey,
                    title: journey.displayName,
                    statusLabel: statuses[journey],
                    href: nil,
                    route: nil
                )
            }

        // No contacts link: see `loadTravelFormsWithContacts`. `hasContactsLink` is therefore
        // `false` in demo, which is exactly what a UI should read it as — there is nothing to open.
        return TravelPage(
            title: "My travel forms",
            forms: forms,
            manageContactsHref: nil,
            manageContactsRoute: nil,
            manageContactsLabel: nil,
            emptyMessage: nil
        )
    }

    /// Two invented contacts. The contacts page has never been captured, so this is shaped by
    /// `TravelContact` and nothing else — it is sample data, not a claim about W4.
    static func demoContacts() -> [TravelContact] {
        [
            TravelContact(
                id: "demo-contact-1",
                name: "Maria Lindqvist",
                relation: "Mother",
                phone: "+47 55 00 11 22",
                email: "maria.lindqvist@example.org"
            ),
            TravelContact(
                id: "demo-contact-2",
                name: "Tomas Lindqvist",
                relation: "Father",
                phone: "+47 55 00 33 44",
                email: "tomas.lindqvist@example.org"
            )
        ]
    }
}
