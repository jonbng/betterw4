//
//  TripRepository.swift
//  BetterW4
//
//  `academics/trips` — "My trips", the boarding-college surface Lectio had no equivalent for
//  (features.md §1.9, W4_PORT_PLAN.md Wave 5 item 5.8).
//
//  v1 is read-only. "Plan new trip" opens the W4 page in the in-app browser with the session
//  cookie (D-24); nothing here POSTs, which is why this repository only ever needs a GET.
//
//  The transport seam (`W4SecondaryFetching`), the cache-first loader (`W4SecondaryPageLoader`)
//  and their reasoning live in `DocumentRepository.swift`; this file only chooses a route, a
//  surface and a parser.
//

import Foundation

/// Reads the trip grid, cache-first, with a `.trips` TTL from `CachePolicy`.
actor TripRepository {

    /// One cache entry: the trip grid is a single page, and bug B10 (nobody paginates) means the
    /// pager is surfaced as `TripList.hasMorePages` rather than followed.
    static let tripsCacheKey = "my-trips"

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

    // MARK: - Reading

    /// The student's trips.
    ///
    /// Returns the cached grid untouched while it is inside its TTL, so opening the tab twice in a
    /// row costs one request, not two.
    func loadTrips(
        forceRefresh: Bool = false,
        priority: FetchPriority = .important
    ) async throws -> W4Loaded<TripList> {
        let context = try resolveContext()
        if context.isDemo {
            return W4Loaded(Self.demoTripList(), freshness: .demo)
        }

        let loaded = try await W4SecondaryPageLoader.loadHTML(
            surface: .trips,
            key: Self.tripsCacheKey,
            route: W4Routes.R.trips,
            forceRefresh: forceRefresh,
            priority: priority,
            context: context,
            client: client,
            cache: cache
        )
        return loaded.map(W4TripsParser.parse)
    }

    /// The last grid we stored, however old, with no request — for the first frame of the screen.
    func cachedTrips() async -> W4Loaded<TripList>? {
        guard let context = try? resolveContext() else { return nil }
        if context.isDemo {
            return W4Loaded(Self.demoTripList(), freshness: .demo)
        }
        let cached = await W4SecondaryPageLoader.cachedHTML(
            surface: .trips,
            key: Self.tripsCacheKey,
            context: context,
            cache: cache
        )
        return cached?.map(W4TripsParser.parse)
    }

    /// Drops the cached grid.
    ///
    /// Call this after anything that can change a trip — most importantly after the student
    /// submits or cancels a trip in the in-app browser, because approval auto-registers
    /// pre-arranged absences (README §6) and the grid the app is holding is then a lie.
    func invalidate() async {
        guard let context = try? resolveContext(), !context.isDemo else { return }
        await cache.remove(surface: .trips, key: Self.tripsCacheKey, uwcId: context.uwcId)
    }

    // MARK: - Demo (features.md §4)

    /// One trip: "Bergen weekend", a Saturday to Sunday, status Planning.
    ///
    /// features.md §4 pins the name and the status; the dates are computed from `TimeProvider.now`
    /// rather than hard-coded to the 20–21 September of the spec, because a demo build lives for
    /// years and a trip stamped with a date two years in the past reads as a broken app rather
    /// than as sample data.
    static func demoTripList() -> TripList {
        let saturday = demoSaturday()
        let outgoing = W4Dates.date(onDayOf: saturday, minutesFromMidnight: 8 * 60)
        let returning = W4Dates.date(
            onDayOf: W4Dates.adding(days: 1, to: saturday),
            minutesFromMidnight: 18 * 60
        )

        let trip = Trip(
            id: "demo-trip-bergen",
            name: "Bergen weekend",
            outgoing: outgoing,
            outgoingLabel: W4Dates.formatDateTime(outgoing),
            returning: returning,
            returningLabel: W4Dates.formatDateTime(returning),
            destination: "Bergen",
            type: "Optional",
            participants: 12,
            participantsLabel: "12",
            status: .planning,
            statusLabel: "Planning",
            href: nil,
            route: nil
        )

        return TripList(
            title: "My trips",
            trips: [trip],
            hasMorePages: false,
            emptyMessage: nil,
            canPlanNewTrip: true,
            planNewTripHref: nil,
            isHeaderDriven: true
        )
    }

    /// The next Saturday at or after today, in Oslo wall clock.
    private static func demoSaturday() -> Date {
        let today = W4Dates.startOfDay(TimeProvider.now)
        // `.weekday` is 1 = Sunday … 7 = Saturday in every Gregorian calendar, independent of
        // `firstWeekday` — which `W4Dates.calendar` sets to Monday for its ISO week maths.
        let weekday = W4Dates.calendar.component(.weekday, from: today)
        return W4Dates.adding(days: (7 - weekday) % 7, to: today)
    }
}
