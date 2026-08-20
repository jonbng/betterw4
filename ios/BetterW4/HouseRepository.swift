//
//  HouseRepository.swift
//  BetterW4
//
//  `people/students/byhouse` — boarding houses, rooms, and who lives in each one.
//
//  Cache: `W4Surface.people`, TTL 7 days. Each house page is its own cache key so opening
//  Denmark does not refetch Finland. Requests stay sequential: W4 is one Apache box.
//

import Foundation

actor HouseRepository {

    static let shared = HouseRepository()

    static let indexCacheKey = "byhouse-index"

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

    func loadIndex(
        forceRefresh: Bool = false,
        priority: FetchPriority = .important
    ) async throws -> W4Loaded<[House]> {
        let context = try resolveContext()
        if context.isDemo {
            return W4Loaded(Self.demoHouses.map { House(id: $0.id, name: $0.name) }, freshness: .demo)
        }
        let loaded = try await W4SecondaryPageLoader.loadHTML(
            surface: .people,
            key: Self.indexCacheKey,
            route: W4Routes.R.studentsByHouse,
            forceRefresh: forceRefresh,
            priority: priority,
            context: context,
            client: client,
            cache: cache
        )
        return loaded.map(W4HouseParser.parseIndex)
    }

    func loadHouse(
        id houseId: String,
        forceRefresh: Bool = false,
        priority: FetchPriority = .important
    ) async throws -> W4Loaded<House> {
        let context = try resolveContext()
        if context.isDemo {
            let house = Self.demoHouses.first { $0.id == houseId }
                ?? House(id: houseId, name: W4HouseParser.displayName(forId: houseId), loaded: true)
            return W4Loaded(house, freshness: .demo)
        }
        let loaded = try await W4SecondaryPageLoader.loadHTML(
            surface: .people,
            key: Self.houseCacheKey(houseId),
            route: W4Routes.R.studentsByHouseIndex,
            query: ["house_id": houseId],
            forceRefresh: forceRefresh,
            priority: priority,
            context: context,
            client: client,
            cache: cache
        )
        return loaded.map { W4HouseParser.parseHouse($0, houseId: houseId) }
    }

    func cachedIndex() async -> W4Loaded<[House]>? {
        guard let context = try? resolveContext() else { return nil }
        if context.isDemo {
            return W4Loaded(Self.demoHouses.map { House(id: $0.id, name: $0.name) }, freshness: .demo)
        }
        let cached = await W4SecondaryPageLoader.cachedHTML(
            surface: .people,
            key: Self.indexCacheKey,
            context: context,
            cache: cache
        )
        return cached?.map(W4HouseParser.parseIndex)
    }

    func cachedHouse(id houseId: String) async -> W4Loaded<House>? {
        guard let context = try? resolveContext() else { return nil }
        if context.isDemo {
            let house = Self.demoHouses.first { $0.id == houseId }
                ?? House(id: houseId, name: W4HouseParser.displayName(forId: houseId), loaded: true)
            return W4Loaded(house, freshness: .demo)
        }
        let cached = await W4SecondaryPageLoader.cachedHTML(
            surface: .people,
            key: Self.houseCacheKey(houseId),
            context: context,
            cache: cache
        )
        return cached?.map { W4HouseParser.parseHouse($0, houseId: houseId) }
    }

    static func houseCacheKey(_ houseId: String) -> String {
        "byhouse-\(houseId.lowercased())"
    }

    /// Walk every boarding-house page until `uwcId` is found.
    /// Pages are cache-first, so a second lookup after More ▸ Houses is free.
    func findPlacement(uwcId: String) async -> HousePlacement? {
        let id = DirectoryRepository.normalizedUwcId(uwcId)
        guard !id.isEmpty else { return nil }
        if let context = try? resolveContext(), context.isDemo {
            return Self.demoHouses.placement(of: id)
        }
        do {
            let index = try await loadIndex(priority: .opportunistic)
            for (offset, stub) in index.value.enumerated() {
                let priority: FetchPriority = offset == 0 ? .important : .opportunistic
                let house = try await loadHouse(id: stub.id, priority: priority)
                if let placement = house.value.placement(of: id) {
                    return placement
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    // MARK: - Demo

    static let demoHouses: [House] = {
        func student(
            _ id: String,
            _ name: String,
            country: String,
            year: String,
            status: String = "On campus"
        ) -> HouseResident {
            HouseResident(
                person: DirectoryPerson(
                    uwcId: id,
                    name: name,
                    kind: .student,
                    year: year,
                    country: country,
                    subtitle: "\(country) · Year \(year)",
                    status: status
                ),
                country: country,
                year: year,
                status: status
            )
        }

        let leader = HouseResident(
            person: DirectoryPerson(
                uwcId: "nc00ccc",
                name: "Chris Chen",
                kind: .staff,
                subtitle: "House leader"
            )
        )

        return [
            House(
                id: "denmark",
                name: "Denmark",
                leaders: [leader],
                rooms: [
                    HouseRoom(
                        id: "denmark-room101",
                        name: "Room 101",
                        residents: [
                            student("nc00aaa", "Alex Andersen", country: "Denmark", year: "1"),
                            student("nc00bbb", "Bea Beltran", country: "Italy", year: "2"),
                        ]
                    ),
                    HouseRoom(
                        id: "denmark-room102",
                        name: "Room 102",
                        residents: [
                            student("nc00ddd", "Dana Dlamini", country: "South Africa", year: "1"),
                            student("nc00lll", "Noor Haddad", country: "Jordan", year: "1"),
                        ]
                    ),
                ],
                loaded: true
            ),
            House(
                id: "finland",
                name: "Finland",
                leaders: [],
                rooms: [
                    HouseRoom(
                        id: "finland-room101",
                        name: "Room 101",
                        residents: [
                            student("nc00eee", "Eli Eriksen", country: "Norway", year: "2"),
                            student("nc00hhh", "Cara Cole", country: "Canada", year: "2"),
                        ]
                    ),
                    HouseRoom(
                        id: "finland-room102",
                        name: "Room 102",
                        residents: [
                            student("nc00iii", "Mei Nakamura", country: "Japan", year: "1"),
                        ]
                    ),
                ],
                unassigned: [
                    student(
                        "nc00ggg",
                        "Gita Ghosh",
                        country: "India",
                        year: "1",
                        status: "Off campus"
                    ),
                ],
                loaded: true
            ),
            House(
                id: "iceland",
                name: "Iceland",
                rooms: [
                    HouseRoom(
                        id: "iceland-room101",
                        name: "Room 101",
                        residents: [
                            student("nc00jjj", "Luis Ortega", country: "Mexico", year: "2"),
                            student("nc00kkk", "Amara Okonkwo", country: "Nigeria", year: "1"),
                        ]
                    ),
                ],
                loaded: true
            ),
            House(
                id: "norway",
                name: "Norway",
                rooms: [
                    HouseRoom(
                        id: "norway-room101",
                        name: "Room 101",
                        residents: [
                            student("nc00mmm", "Sofia Alvarez", country: "Argentina", year: "2"),
                            student("nc00nnn", "Tomas Novak", country: "Czechia", year: "1"),
                        ]
                    ),
                    HouseRoom(
                        id: "norway-room102",
                        name: "Room 102",
                        residents: [
                            student("nc00ppp", "Linh Nguyen", country: "Vietnam", year: "1"),
                        ]
                    ),
                ],
                loaded: true
            ),
            House(
                id: "sweden",
                name: "Sweden",
                rooms: [
                    HouseRoom(
                        id: "sweden-room101",
                        name: "Room 101",
                        residents: [
                            student("nc00qqq", "Amina Diallo", country: "Senegal", year: "2"),
                            student("nc00rrr", "Hana Kim", country: "South Korea", year: "1"),
                        ]
                    ),
                    HouseRoom(
                        id: "sweden-room102",
                        name: "Room 102",
                        residents: [
                            student("nc00sss", "Mateo Silva", country: "Brazil", year: "2"),
                            student("nc00ttt", "Jamal Farouk", country: "Egypt", year: "2"),
                        ]
                    ),
                ],
                loaded: true
            ),
        ]
    }()
}
