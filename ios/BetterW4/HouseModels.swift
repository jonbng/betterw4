//
//  HouseModels.swift
//  BetterW4
//
//  Boarding houses from `people/students/byhouse` — house leader, rooms, and who lives
//  in each room. Produced by `W4HouseParser`.
//

import Foundation

/// One boarding house (`house_id=denmark` …).
struct House: Identifiable, Equatable, Hashable, Sendable {
    /// W4 slug: `denmark`, `finland`, `iceland`, `norway`, `sweden`, `grad`.
    let id: String
    let name: String
    let leaders: [HouseResident]
    let rooms: [HouseRoom]
    /// `Students with no room`, plus any leftover list that was not under a room heading.
    let unassigned: [HouseResident]
    /// False while the house page is still being fetched.
    let loaded: Bool

    var studentCount: Int {
        rooms.reduce(0) { $0 + $1.residents.count } + unassigned.count
    }

    var roomCount: Int { rooms.count }

    init(
        id: String,
        name: String,
        leaders: [HouseResident] = [],
        rooms: [HouseRoom] = [],
        unassigned: [HouseResident] = [],
        loaded: Bool = false
    ) {
        self.id = id
        self.name = name
        self.leaders = leaders
        self.rooms = rooms
        self.unassigned = unassigned
        self.loaded = loaded
    }
}

struct HouseRoom: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
    let residents: [HouseResident]

    init(id: String, name: String, residents: [HouseResident] = []) {
        self.id = id
        self.name = name
        self.residents = residents
    }
}

/// A person listed under a house — student in a room, or the house leader.
struct HouseResident: Identifiable, Equatable, Hashable, Sendable {
    let person: DirectoryPerson
    let country: String?
    let year: String?
    let status: String?

    var id: String { person.uwcId }

    var detailLine: String? {
        var parts: [String] = []
        if let country, !country.isEmpty { parts.append(country) }
        if let yearLabel { parts.append(yearLabel) }
        if let status, !status.isEmpty { parts.append(status) }
        if parts.isEmpty { return person.subtitle }
        return parts.joined(separator: " · ")
    }

    private var yearLabel: String? {
        guard let year, !year.isEmpty else { return nil }
        switch year {
        case "1": return "1st year"
        case "2": return "2nd year"
        default: return year
        }
    }

    init(
        person: DirectoryPerson,
        country: String? = nil,
        year: String? = nil,
        status: String? = nil
    ) {
        self.person = person
        self.country = country
        self.year = year
        self.status = status
    }

    func withHouse(_ houseName: String) -> HouseResident {
        let stamped = DirectoryPerson(
            uwcId: person.uwcId,
            name: person.name,
            kind: person.kind,
            preferredName: person.preferredName,
            year: person.year ?? year,
            house: houseName,
            country: person.country ?? country,
            pronouns: person.pronouns,
            subtitle: person.subtitle,
            status: person.status ?? status,
            isOnline: person.isOnline,
            photoURL: person.photoURL
        )
        return HouseResident(person: stamped, country: country, year: year, status: status)
    }
}

/// The full `byhouse` overview: every house W4 listed, in document order.
struct HouseOverview: Equatable, Sendable {
    let houses: [House]

    var isEmpty: Bool { houses.isEmpty }

    init(houses: [House] = []) {
        self.houses = houses
    }
}

/// Where a student lives: boarding house plus the room heading, when they have one.
struct HousePlacement: Equatable, Hashable, Sendable {
    let house: House
    let room: HouseRoom?
    let resident: HouseResident
}

extension House {
    func placement(of uwcId: String) -> HousePlacement? {
        let id = uwcId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !id.isEmpty else { return nil }
        for room in rooms {
            if let resident = room.residents.first(where: { $0.id.lowercased() == id }) {
                return HousePlacement(house: self, room: room, resident: resident)
            }
        }
        if let resident = unassigned.first(where: { $0.id.lowercased() == id }) {
            return HousePlacement(house: self, room: nil, resident: resident)
        }
        return nil
    }
}

extension Sequence where Element == House {
    func placement(of uwcId: String) -> HousePlacement? {
        for house in self {
            if let placement = house.placement(of: uwcId) {
                return placement
            }
        }
        return nil
    }
}
