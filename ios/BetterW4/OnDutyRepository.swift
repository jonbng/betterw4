//
//  OnDutyRepository.swift
//  BetterW4
//
//  `people/onduty` (who is on duty today) and `people/onduty/schedule` (the
//  rest of the month). Today's page is the one a student opens to call someone;
//  the calendar is best-effort context for the next few days.
//
//  Cache: `W4Surface.onDuty`, TTL 15 minutes — duty rotas change by the day.
//  A failed schedule fetch never blanks the today list.
//

import Foundation

actor OnDutyRepository {

    static let todayCacheKey = "on-duty-today"
    static let scheduleCacheKey = "on-duty-schedule"

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

    func load(
        forceRefresh: Bool = false,
        priority: FetchPriority = .important
    ) async throws -> W4Loaded<OnDutySnapshot> {
        let context = try resolveContext()
        if context.isDemo {
            return W4Loaded(Self.demoSnapshot(), freshness: .demo)
        }

        let today = try await loadToday(forceRefresh: forceRefresh, priority: priority, context: context)
        let upcoming: [OnDutyDay]
        if let schedule = try? await loadSchedule(
            forceRefresh: forceRefresh,
            priority: .opportunistic,
            context: context
        ) {
            upcoming = W4OnDutyParser.upcomingDays(in: schedule.value).map {
                W4OnDutyParser.enrich($0, with: today.value.people)
            }
        } else {
            upcoming = []
        }
        return W4Loaded(
            OnDutySnapshot(today: today.value, upcoming: upcoming),
            freshness: today.freshness
        )
    }

    func cachedSnapshot() async -> W4Loaded<OnDutySnapshot>? {
        guard let context = try? resolveContext() else { return nil }
        if context.isDemo {
            return W4Loaded(Self.demoSnapshot(), freshness: .demo)
        }
        guard let cached = await W4SecondaryPageLoader.cachedHTML(
            surface: .onDuty,
            key: Self.todayCacheKey,
            context: context,
            cache: cache
        ) else {
            return nil
        }
        let today = W4OnDutyParser.parseToday(cached.value)
        var upcoming: [OnDutyDay] = []
        if let scheduleHTML = await W4SecondaryPageLoader.cachedHTML(
            surface: .onDuty,
            key: Self.scheduleCacheKey,
            context: context,
            cache: cache
        ) {
            upcoming = W4OnDutyParser.upcomingDays(in: W4OnDutyParser.parseSchedule(scheduleHTML.value)).map {
                W4OnDutyParser.enrich($0, with: today.people)
            }
        }
        return W4Loaded(
            OnDutySnapshot(today: today, upcoming: upcoming),
            freshness: cached.freshness
        )
    }

    private func loadToday(
        forceRefresh: Bool,
        priority: FetchPriority,
        context: W4RequestContext
    ) async throws -> W4Loaded<OnDutyPage> {
        let loaded = try await W4SecondaryPageLoader.loadHTML(
            surface: .onDuty,
            key: Self.todayCacheKey,
            route: W4Routes.R.onDuty,
            forceRefresh: forceRefresh,
            priority: priority,
            context: context,
            client: client,
            cache: cache
        )
        return loaded.map(W4OnDutyParser.parseToday)
    }

    private func loadSchedule(
        forceRefresh: Bool,
        priority: FetchPriority,
        context: W4RequestContext
    ) async throws -> W4Loaded<OnDutySchedule> {
        let loaded = try await W4SecondaryPageLoader.loadHTML(
            surface: .onDuty,
            key: Self.scheduleCacheKey,
            route: W4Routes.R.onDutySchedule,
            forceRefresh: forceRefresh,
            priority: priority,
            context: context,
            client: client,
            cache: cache
        )
        return loaded.map(W4OnDutyParser.parseSchedule)
    }

    static func demoSnapshot(now: Date = TimeProvider.now) -> OnDutySnapshot {
        let today = W4Dates.startOfDay(now)
        let houseLeader = OnDutyPerson(
            id: "nc00fff",
            name: "Frankie Fossum",
            role: "House Leader on Call",
            uwcId: "nc00fff",
            phone: "+47 12 34 56 78",
            email: "nc00fff@uwcrcn.no",
            location: "Haugland",
            photoURL: nil
        )
        let nurse = OnDutyPerson(
            id: "nc00ccc",
            name: "Chris Chen",
            role: "Nurse on Call",
            uwcId: "nc00ccc",
            phone: "+47 98 76 54 32",
            email: "nc00ccc@uwcrcn.no",
            location: nil,
            photoURL: nil
        )
        return OnDutySnapshot(
            today: OnDutyPage(
                title: "People on duty \(W4Dates.format(today))",
                date: today,
                dateLabel: W4Dates.format(today),
                groups: [
                    OnDutyGroup(role: "House Leader on Call", people: [houseLeader]),
                    OnDutyGroup(role: "Nurse on Call", people: [nurse])
                ]
            ),
            upcoming: [
                OnDutyDay(
                    id: W4Dates.format(W4Dates.adding(days: 1, to: today)),
                    date: W4Dates.adding(days: 1, to: today),
                    dateLabel: "Tomorrow",
                    isToday: false,
                    groups: [
                        OnDutyGroup(
                            role: "House Leader on call 15.00-23.00",
                            people: [
                                OnDutyPerson(
                                    id: "upcoming-house",
                                    name: houseLeader.name,
                                    role: "House Leader on call 15.00-23.00",
                                    uwcId: houseLeader.uwcId,
                                    phone: houseLeader.phone,
                                    email: houseLeader.email,
                                    location: houseLeader.location,
                                    photoURL: nil
                                )
                            ]
                        )
                    ]
                )
            ]
        )
    }
}
