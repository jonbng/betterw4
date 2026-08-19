//
//  OnDutyModels.swift
//  BetterW4
//
//  Who is on duty today — `people/onduty` plus the month calendar at
//  `people/onduty/schedule` (features.md §1.12).
//
//  Evidence: live capture 19 Aug 2026. Today's page prints one card per
//  person under an `<h3>` role (`House Leader on Call`), with photo, name,
//  Phone, E-mail and Location. The calendar prints `.onduty-group-name` +
//  `.onduty-group` inside `td.day`.
//

import Foundation

struct OnDutyPerson: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let role: String
    let uwcId: String?
    let phone: String?
    let email: String?
    let location: String?
    let photoURL: URL?

    var hasContact: Bool {
        !(phone ?? "").isEmpty || !(email ?? "").isEmpty
    }
}

struct OnDutyGroup: Identifiable, Hashable, Sendable {
    var id: String { role }
    let role: String
    let people: [OnDutyPerson]
}

struct OnDutyPage: Hashable, Sendable {
    var title: String?
    var date: Date?
    var dateLabel: String?
    var groups: [OnDutyGroup]

    var people: [OnDutyPerson] { groups.flatMap(\.people) }
    var isEmpty: Bool { people.isEmpty }

    init(
        title: String? = nil,
        date: Date? = nil,
        dateLabel: String? = nil,
        groups: [OnDutyGroup] = []
    ) {
        self.title = title
        self.date = date
        self.dateLabel = dateLabel
        self.groups = groups
    }
}

struct OnDutyDay: Identifiable, Hashable, Sendable {
    let id: String
    let date: Date?
    let dateLabel: String
    let isToday: Bool
    let groups: [OnDutyGroup]

    var people: [OnDutyPerson] { groups.flatMap(\.people) }
}

struct OnDutySchedule: Hashable, Sendable {
    var monthLabel: String?
    var year: Int?
    var month: Int?
    var days: [OnDutyDay]

    init(
        monthLabel: String? = nil,
        year: Int? = nil,
        month: Int? = nil,
        days: [OnDutyDay] = []
    ) {
        self.monthLabel = monthLabel
        self.year = year
        self.month = month
        self.days = days
    }
}

struct OnDutySnapshot: Hashable, Sendable {
    var today: OnDutyPage
    var upcoming: [OnDutyDay]
}

enum OnDutyContact {
    static func telephoneURL(_ phone: String) -> URL? {
        guard let digits = digitsForDialing(phone) else { return nil }
        return URL(string: "tel:\(digits)")
    }

    static func smsURL(_ phone: String) -> URL? {
        guard let digits = digitsForDialing(phone) else { return nil }
        return URL(string: "sms:\(digits)")
    }

    static func mailtoURL(_ email: String) -> URL? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("@"), !trimmed.isEmpty else { return nil }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmed
        return URL(string: "mailto:\(encoded)")
    }

    static func digitsForDialing(_ phone: String) -> String? {
        var digits = ""
        for character in phone {
            if character.isNumber {
                digits.append(character)
            } else if character == "+", digits.isEmpty {
                digits.append(character)
            }
        }
        let digitCount = digits.filter(\.isNumber).count
        return digitCount >= 5 ? digits : nil
    }
}
