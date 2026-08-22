//
//  StudentProfile.swift
//  BetterW4
//
//  The presentation model behind the two profile screens.
//
//  `DirectoryPerson` is a directory row and `DirectoryPersonProfile` is a parsed profile page;
//  `StudentProfile` is what the UI actually draws, built from either. It exists so
//  `StudentProfileView` and `StudentCardView` render the same fields, in the same order, whether
//  all we have is a list row or a full `people/students/student&uwc_id=` page.
//
//  Nothing here fetches. The photo is derived from the UWC id — W4 serves
//  `/files/user_photos/{uwc_id}_photo.jpg` and there is no picture id to look up.
//

import Foundation

struct StudentProfile: Equatable, Identifiable, Sendable {

    /// UWC id, lowercase — `nc` + two-digit entry year + letters, e.g. `nc26abcd`.
    let uwcId: String
    let name: String
    let preferredName: String?
    let kind: DirectoryPersonKind
    /// `"1"` / `"2"` where W4 states it.
    let year: String?
    let house: String?
    /// W4 `house_id` slug (`denmark`) so the About tab can open the house page.
    let houseId: String?
    /// Boarding-house room from the profile page, or `people/students/byhouse`.
    let room: String?
    /// Academic classes from the person's public profile page.
    let classes: [PersonClass]
    let country: String?
    let pronouns: String?
    let birthday: String?
    let graduationYear: String?
    let advisor: ProfileAdvisor?
    let lastLogin: String?
    /// The address printed on the profile page, when there was one.
    let scrapedEmail: String?
    let officeTel: String?
    let mobile: String?
    let positions: [String]
    let activities: [StaffActivity]
    /// Everything the page carried that is not already one of the fields above, in document
    /// order, so a label this port has never seen still reaches the screen.
    let extraFields: [PersonProfileField]

    nonisolated var id: String { uwcId }

    // MARK: - Building

    init(
        uwcId: String,
        name: String,
        preferredName: String?,
        kind: DirectoryPersonKind,
        year: String?,
        house: String?,
        houseId: String?,
        room: String?,
        classes: [PersonClass],
        country: String?,
        pronouns: String?,
        birthday: String?,
        graduationYear: String?,
        advisor: ProfileAdvisor?,
        lastLogin: String?,
        scrapedEmail: String?,
        officeTel: String?,
        mobile: String?,
        positions: [String],
        activities: [StaffActivity],
        extraFields: [PersonProfileField]
    ) {
        self.uwcId = uwcId
        self.name = name
        self.preferredName = preferredName
        self.kind = kind
        self.year = year
        self.house = house
        self.houseId = houseId
        self.room = room
        self.classes = classes
        self.country = country
        self.pronouns = pronouns
        self.birthday = birthday
        self.graduationYear = graduationYear
        self.advisor = advisor
        self.lastLogin = lastLogin
        self.scrapedEmail = scrapedEmail
        self.officeTel = officeTel
        self.mobile = mobile
        self.positions = positions
        self.activities = activities
        self.extraFields = extraFields
    }

    /// From a directory row — everything the list already knew, nothing more.
    init(person: DirectoryPerson) {
        self.uwcId = person.uwcId
        self.name = person.hasResolvedName ? person.name : ""
        self.preferredName = Self.nonEmpty(person.preferredName)
        self.kind = person.kind
        self.year = Self.nonEmpty(person.year)
        self.house = Self.nonEmpty(person.house)
        self.houseId = nil
        self.room = nil
        self.classes = []
        self.country = Self.nonEmpty(person.country)
        self.pronouns = Self.nonEmpty(person.pronouns)
        self.birthday = nil
        self.graduationYear = nil
        self.advisor = nil
        self.lastLogin = nil
        self.scrapedEmail = nil
        self.officeTel = nil
        self.mobile = nil
        self.positions = person.kind == .staff ? StaffRoles.parse(person.subtitle) : []
        self.activities = []
        self.extraFields = []
    }

    /// From a parsed profile page. Fields already shown as their own row are not repeated in
    /// `extraFields`.
    init(profile: DirectoryPersonProfile) {
        let person = profile.person
        self.uwcId = person.uwcId
        self.name = person.hasResolvedName ? person.name : ""
        self.preferredName = Self.nonEmpty(person.preferredName)
        self.kind = person.kind
        self.year = Self.nonEmpty(person.year)
        self.house = Self.nonEmpty(person.house)
        self.houseId = Self.nonEmpty(profile.houseId)
        self.room = Self.nonEmpty(profile.room)
        self.classes = profile.taughtClasses
        self.country = Self.nonEmpty(person.country)
        self.pronouns = Self.nonEmpty(person.pronouns)
        self.birthday = Self.nonEmpty(profile.birthday)
        self.graduationYear = Self.nonEmpty(profile.graduationYear)
        self.advisor = profile.advisor
        self.lastLogin = Self.nonEmpty(profile.lastLogin)
        self.scrapedEmail = Self.nonEmpty(profile.scrapedEmail)
        self.officeTel = Self.nonEmpty(profile.officeTel)
        self.mobile = Self.nonEmpty(profile.mobile)
        self.positions = profile.positions
        self.activities = profile.activities
        self.extraFields = profile.fields.filter { field in
            let label = PersonProfileField.normalizedLabel(field.label)
            guard !Self.knownLabels.contains(label) else { return false }
            guard !label.contains("timetable") else { return false }
            guard field.value.caseInsensitiveCompare("View") != .orderedSame else { return false }
            return Self.nonEmpty(field.value) != nil
        }
    }

    /// Labels rendered as their own row, so `extraFields` does not print them twice.
    private static let knownLabels: Set<String> = [
        "uwc id", "uwcid", "id", "name", "full name", "preferred name",
        "year", "ib year", "study year", "house", "room", "country", "pronouns",
        "pronoun", "personal pronoun", "email", "e mail", "birthday",
        "date of birth", "birth date", "last login", "position", "positions",
        "office tel", "office telephone", "mobile", "advisees", "advisor",
        "graduation year", "ac timetable", "ea timetable", "assessments",
        "teachers leaders", "teachersleaders"
    ]

    // MARK: - Display

    /// The preferred name when W4 gave us one, then the full name, then the UWC id.
    nonisolated var displayName: String {
        if let preferredName, !preferredName.isEmpty { return preferredName }
        if !name.isEmpty { return name }
        return uwcId
    }

    /// The full name when it differs from what the header already shows.
    nonisolated var secondaryName: String? {
        guard !name.isEmpty, name != displayName else { return nil }
        return name
    }

    /// Staff: `Teacher · Advisor · China`. Students: `Year 1 · Denmark · Room 101`.
    nonisolated var subtitle: String? {
        if kind == .staff {
            let parts = [
                positions.prefix(3).joined(separator: " · ").nilIfEmpty,
                country
            ].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
        let parts = [
            year.map { $0.hasPrefix("Year") ? $0 : "Year \($0)" },
            house,
            room,
            country
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    func applying(placement: HousePlacement?) -> StudentProfile {
        let placedHouse = kind == .staff ? house : (placement?.house.name ?? house)
        let placedHouseId = kind == .staff ? houseId : (placement?.house.id ?? houseId)
        let placedRoom = kind == .staff ? room : (placement?.room?.name ?? room)
        let placedYear = kind == .staff ? year : (year ?? placement?.resident.year)
        return StudentProfile(
            uwcId: uwcId,
            name: name,
            preferredName: preferredName,
            kind: kind,
            year: placedYear,
            house: placedHouse,
            houseId: placedHouseId,
            room: placedRoom,
            classes: classes,
            country: country ?? placement?.resident.country,
            pronouns: pronouns,
            birthday: birthday,
            graduationYear: graduationYear,
            advisor: advisor,
            lastLogin: lastLogin,
            scrapedEmail: scrapedEmail,
            officeTel: officeTel,
            mobile: mobile,
            positions: positions,
            activities: activities,
            extraFields: extraFields
        )
    }

    var parsedBirthday: PersonBirthday? { PersonBirthday.parse(birthday) }

    /// Derived, never scraped: every W4 account's address is `{uwc_id}@uwcrcn.no` (README §6).
    nonisolated var email: String {
        scrapedEmail ?? "\(uwcId)@uwcrcn.no"
    }

    /// The person's public profile page on W4.
    nonisolated var profileURL: URL {
        W4Routes.url(kind.profileRoute, ["uwc_id": uwcId])
    }

    nonisolated var kindLabel: String { kind.displayName }

    /// W4 serves member photos as `{uwc_id}.jpg`; views fall back to initials.
    nonisolated var photoURL: URL? {
        guard let id = Self.normalizedUWCID(uwcId) else { return nil }
        return W4PeopleParser.photoURL(forUWCId: id)
    }

    /// Lowercased UWC id, or `nil` when the value is not one — so a stray token can never be
    /// turned into a photo request.
    nonisolated static func normalizedUWCID(_ value: String) -> String? {
        let id = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard (3...16).contains(id.count),
              let first = id.first,
              first.isLetter,
              id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return id
    }

    private nonisolated static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

// `String.nilIfEmpty` lives in BaseParser.swift. A second, file-private copy here was an
// invalid redeclaration rather than a shadow — Swift rejects it outright. The surviving one
// trims before testing for empty, which is what the rest of this file already does by hand.
