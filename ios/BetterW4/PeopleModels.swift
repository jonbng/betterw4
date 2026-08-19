//
//  PeopleModels.swift
//  BetterW4
//
//  Domain models for the W4 people directory: `people/students/*`, `people/staff/*`
//  and the two public profile pages. Produced by `W4PeopleParser`.
//
//  Plan: W4_PORT_PLAN.md Wave 4 item 4.7, decision D-5 (domain models are unprefixed;
//  the `W4` prefix belongs to wire/protocol types and parsers).
//  Spec: docs/spec/parsers.md section 11, docs/spec/features.md section 1.12.
//
//  Evidence status. Only the *photo + href* shape is verified, from the Home birthdays
//  block (`references/pages/UWCRCN W4.html:201-214`): `a[href*=uwc_id] > img.photo` with
//  `alt="Photo of {uwc_id}"` and a `{uwc_id}_thumb.jpg` source. The list markup itself
//  (`ul.user-list`, and the `CGridView` variant with `td.student-name` / `td.entry-name` /
//  `td.status`) has never been captured — the grid cell classes are only known to exist
//  because W4's own `css/main.css` styles them. Every field below is therefore optional
//  where the source is unproven, and the parser degrades to an empty list rather than
//  inventing a row.
//
//  PII: names and UWC ids must never be written to the log.
//

import Foundation

// MARK: - Kind

/// Student or staff.
///
/// **Always decided from the href of the row that produced the person**
/// (`people/staff/staff` vs `people/students/student`) — never from a document-wide
/// substring search, which mislabels everybody on a page that lists both (parsers.md
/// section 11, "Kind detection"; the Kotlin port's `W4PeopleParser.kt:67-73` gets this wrong).
enum DirectoryPersonKind: String, Codable, CaseIterable, Sendable {
    case student
    case staff

    /// The public-profile route for this kind, without the `uwc_id` sibling parameter.
    var profileRoute: String {
        switch self {
        case .student: return W4Routes.R.studentProfile
        case .staff: return W4Routes.R.staffProfile
        }
    }

    var displayName: String {
        switch self {
        case .student: return "Student"
        case .staff: return "Staff"
        }
    }
}

// MARK: - Person

/// One person in the W4 directory.
///
/// `uwcId` is the only globally unique key W4 has (`nc` + two-digit entry year + initials,
/// e.g. `nc26abcd`); there is no numeric id anywhere in W4. Staff use the same scheme.
struct DirectoryPerson: Identifiable, Codable, Equatable, Hashable, Sendable {
    /// `nc26abcd`, always lowercased.
    let uwcId: String
    /// Display name. Falls back to `uwcId` when the markup carries no name at all —
    /// which is exactly what the Home birthdays block does, so check `hasResolvedName`
    /// before showing it as a person's name.
    let name: String
    let kind: DirectoryPersonKind
    /// Only ever filled in from a labelled profile field, never guessed from a list row.
    let preferredName: String?
    /// `"1"` / `"2"` where a row or profile states it (`1st year`, `Year 2`).
    let year: String?
    let house: String?
    let country: String?
    let pronouns: String?
    /// Free text assembled from whatever the row carried below the name,
    /// e.g. `"Italy · 1st year"` or `"Advisor, Teacher"`. Rendered verbatim.
    let subtitle: String?
    /// Raw `td.status` text, rendered verbatim (`"Online"`, `"On leave"`, …).
    let status: String?
    /// From `tr.online` / `tr.offline` (both **[V]** in `css/main.css`).
    /// `nil` means the markup said nothing — never render it as "offline".
    let isOnline: Bool?
    /// `nil` means "no photo": W4 serves `/images/user.png` as its missing-photo
    /// placeholder, and rendering that as if it were a portrait is a bug.
    let photoURL: URL?

    var id: String { uwcId }

    /// Derived, never scraped. README section 6: every account's mail address is
    /// `{uwc_id}@uwcrcn.no`.
    var email: String { "\(uwcId)@uwcrcn.no" }

    /// `people/students/student&uwc_id=nc26abcd` — a Yii route plus a sibling parameter,
    /// ready for `W4Routes.url(_:)` / `W4Routes.resolve(_:)`.
    var profileRoute: String { "\(kind.profileRoute)&uwc_id=\(uwcId)" }

    var profileURL: URL { W4Routes.url(kind.profileRoute, ["uwc_id": uwcId]) }

    /// False when the markup gave us an id but no name (Home birthdays, bare photo grids).
    var hasResolvedName: Bool {
        name.caseInsensitiveCompare(uwcId) != .orderedSame
    }

    /// The name a list row should show: the preferred name when W4 gave us one.
    var displayName: String {
        if let preferredName, !preferredName.isEmpty { return preferredName }
        return name
    }

    init(
        uwcId: String,
        name: String,
        kind: DirectoryPersonKind,
        preferredName: String? = nil,
        year: String? = nil,
        house: String? = nil,
        country: String? = nil,
        pronouns: String? = nil,
        subtitle: String? = nil,
        status: String? = nil,
        isOnline: Bool? = nil,
        photoURL: URL? = nil
    ) {
        self.uwcId = uwcId
        self.name = name
        self.kind = kind
        self.preferredName = preferredName
        self.year = year
        self.house = house
        self.country = country
        self.pronouns = pronouns
        self.subtitle = subtitle
        self.status = status
        self.isOnline = isOnline
        self.photoURL = photoURL
    }
}

// MARK: - Profile

/// One `th` / `td` row of a Yii `CDetailView`, kept verbatim so the UI can render
/// fields we have never seen without the parser having to know them.
struct PersonProfileField: Codable, Equatable, Hashable, Sendable {
    let label: String
    let value: String

    init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

/// A public profile page (`people/students/student&uwc_id=` / `people/staff/staff&uwc_id=`)
/// or the signed-in student's own `site/profile`.
///
/// **[I] — no profile page has ever been captured.** `table.detail-view` is the Yii 1
/// `CDetailView` convention; the field labels come from README section 6. Everything the
/// parser does not recognise still reaches the UI through `fields`.
enum StaffRoles {
    static func parse(_ raw: String?) -> [String] {
        guard let raw, !raw.isEmpty else { return [] }
        let source = raw.split(separator: "·").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.last(where: { $0.contains(",") }) ?? raw
        var seen = Set<String>()
        var result: [String] = []
        for part in source.split(separator: ",") {
            let role = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !role.isEmpty, !isMailingList(role) else { continue }
            let key = role.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(role)
        }
        return result
    }

    static func isMailingList(_ role: String) -> Bool {
        let n = role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return n.contains("mail list") || n.hasSuffix(" mail") || n == "support staff mail"
    }
}

struct StaffActivity: Codable, Equatable, Hashable, Identifiable, Sendable {
    let name: String
    let dates: String?
    let category: String?

    var id: String { "\(name)|\(dates ?? "")" }

    init(name: String, dates: String? = nil, category: String? = nil) {
        self.name = name
        self.dates = dates
        self.category = category
    }
}

struct DirectoryPersonProfile: Codable, Equatable, Hashable, Sendable {
    let person: DirectoryPerson
    let birthday: String?
    let lastLogin: String?
    /// The address printed on the page, when there is one. `person.email` stays derived.
    let scrapedEmail: String?
    let officeTel: String?
    let mobile: String?
    /// Jobs/subjects from the staff Position field, mailing lists already stripped.
    let positions: [String]
    let taughtClasses: [PersonClass]
    let activities: [StaffActivity]
    /// Every labelled row, in document order.
    let fields: [PersonProfileField]

    var uwcId: String { person.uwcId }

    init(
        person: DirectoryPerson,
        birthday: String? = nil,
        lastLogin: String? = nil,
        scrapedEmail: String? = nil,
        officeTel: String? = nil,
        mobile: String? = nil,
        positions: [String] = [],
        taughtClasses: [PersonClass] = [],
        activities: [StaffActivity] = [],
        fields: [PersonProfileField] = []
    ) {
        self.person = person
        self.birthday = birthday
        self.lastLogin = lastLogin
        self.scrapedEmail = scrapedEmail
        self.officeTel = officeTel
        self.mobile = mobile
        self.positions = positions
        self.taughtClasses = taughtClasses
        self.activities = activities
        self.fields = fields
    }

    /// Case- and punctuation-insensitive field lookup (`"UWC id:"` matches `"uwc id"`).
    func value(forLabel label: String) -> String? {
        let wanted = PersonProfileField.normalizedLabel(label)
        guard !wanted.isEmpty else { return nil }
        if let exact = fields.first(where: { PersonProfileField.normalizedLabel($0.label) == wanted }) {
            return exact.value
        }
        return fields.first { PersonProfileField.normalizedLabel($0.label).contains(wanted) }?.value
    }
}

extension PersonProfileField {
    /// `"UWC_id:"` -> `"uwc id"`. Labels are the only join between a parser that has never
    /// seen the page and a page that may spell anything.
    static func normalizedLabel(_ raw: String) -> String {
        let lowered = raw.lowercased().replacingOccurrences(of: "_", with: " ")
        let stripped = lowered.filter { $0.isLetter || $0.isNumber || $0 == " " }
        return stripped.split(separator: " ").joined(separator: " ")
    }
}

// MARK: - A parsed list page

/// The result of parsing one people list page.
///
/// `notice` carries W4's own empty-state text (`div.note` — **[V]**, the real
/// "No users found" body of `references/pages/Current applicants at UWCRCN.html`), and
/// `hasMorePages` reports a Yii pager so the UI can say "more on w4.uwcrcn.no" instead of
/// silently truncating a 200-student directory (parsers.md section 0.4).
struct DirectoryPeoplePage: Codable, Equatable, Sendable {
    let heading: String?
    let people: [DirectoryPerson]
    let notice: String?
    let hasMorePages: Bool

    var isEmpty: Bool { people.isEmpty }

    init(
        heading: String? = nil,
        people: [DirectoryPerson] = [],
        notice: String? = nil,
        hasMorePages: Bool = false
    ) {
        self.heading = heading
        self.people = people
        self.notice = notice
        self.hasMorePages = hasMorePages
    }
}

// MARK: - Directory sources

/// The people lists a student can open, all **[V]** from the School side menu
/// (`references/pages/School info @ UWCRCN.html:77`, mirrored in the `school-menu` fixture).
///
/// The kind of each *person* still comes from that person's own row href — a list route
/// is not evidence about the rows it happens to contain.
enum PeopleDirectorySource: String, Codable, CaseIterable, Sendable {
    case allStudents
    case firstYear
    case secondYear
    case byName
    case byPreferredName
    case byCountry
    case byHouse
    case myTeachers
    case myGroupLeaders
    case currentStaff
    case staffOnLeave

    /// A Yii route, possibly carrying sibling parameters inline; `W4Routes.url(_:)` splits them.
    var route: String {
        switch self {
        case .allStudents: return W4Routes.R.studentsAll
        case .firstYear: return W4Routes.R.studentsFirstYear
        case .secondYear: return W4Routes.R.studentsSecondYear
        case .byName: return "people/students/byname"
        case .byPreferredName: return "people/students/bypreferred"
        case .byCountry: return "people/students/bycountry"
        case .byHouse: return "people/students/byhouse"
        case .myTeachers: return "\(W4Routes.R.staff)&type=teachers"
        case .myGroupLeaders: return "\(W4Routes.R.staff)&type=leaders"
        case .currentStaff: return W4Routes.R.staffCurrent
        case .staffOnLeave: return "people/staff/onleave"
        }
    }

    var title: String {
        switch self {
        case .allStudents: return "All students"
        case .firstYear: return "First year"
        case .secondYear: return "Second year"
        case .byName: return "By name"
        case .byPreferredName: return "By preferred name"
        case .byCountry: return "By country"
        case .byHouse: return "By house"
        case .myTeachers: return "My teachers"
        case .myGroupLeaders: return "My group leaders"
        case .currentStaff: return "Staff"
        case .staffOnLeave: return "Staff on leave"
        }
    }

    var url: URL { W4Routes.url(route) }
}
