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
//  `/files/user_photos/{uwc_id}_thumb.jpg` and there is no picture id to look up.
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
    let country: String?
    let pronouns: String?
    let birthday: String?
    let lastLogin: String?
    /// The address printed on the profile page, when there was one.
    let scrapedEmail: String?
    /// Everything the page carried that is not already one of the fields above, in document
    /// order, so a label this port has never seen still reaches the screen.
    let extraFields: [PersonProfileField]

    nonisolated var id: String { uwcId }

    // MARK: - Building

    /// From a directory row — everything the list already knew, nothing more.
    init(person: DirectoryPerson) {
        self.uwcId = person.uwcId
        self.name = person.hasResolvedName ? person.name : ""
        self.preferredName = Self.nonEmpty(person.preferredName)
        self.kind = person.kind
        self.year = Self.nonEmpty(person.year)
        self.house = Self.nonEmpty(person.house)
        self.country = Self.nonEmpty(person.country)
        self.pronouns = Self.nonEmpty(person.pronouns)
        self.birthday = nil
        self.lastLogin = nil
        self.scrapedEmail = nil
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
        self.country = Self.nonEmpty(person.country)
        self.pronouns = Self.nonEmpty(person.pronouns)
        self.birthday = Self.nonEmpty(profile.birthday)
        self.lastLogin = Self.nonEmpty(profile.lastLogin)
        self.scrapedEmail = Self.nonEmpty(profile.scrapedEmail)
        self.extraFields = profile.fields.filter { field in
            let label = PersonProfileField.normalizedLabel(field.label)
            guard !Self.knownLabels.contains(label) else { return false }
            return Self.nonEmpty(field.value) != nil
        }
    }

    /// Labels rendered as their own row, so `extraFields` does not print them twice.
    private static let knownLabels: Set<String> = [
        "uwc id", "uwcid", "id", "name", "full name", "preferred name",
        "year", "ib year", "house", "country", "pronouns", "email",
        "e mail", "birthday", "date of birth", "last login"
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

    /// `Year 1 · Haugland · Norway` — the subtitle shape W4's own people lists use.
    nonisolated var subtitle: String? {
        let parts = [
            year.map { "Year \($0)" },
            house,
            country
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Derived, never scraped: every W4 account's address is `{uwc_id}@uwcrcn.no` (README §6).
    nonisolated var email: String {
        scrapedEmail ?? "\(uwcId)@uwcrcn.no"
    }

    /// The person's public profile page on W4.
    nonisolated var profileURL: URL {
        W4Routes.url(kind.profileRoute, ["uwc_id": uwcId])
    }

    nonisolated var kindLabel: String { kind.displayName }

    /// W4 serves member photos as `{uwc_id}_thumb.jpg`; views fall back to initials.
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
