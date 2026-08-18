//
//  TripModels.swift
//  BetterW4
//
//  Domain models for W4's two boarding-travel surfaces:
//
//    * `academics/trips`               — My trips (the trip grid)
//    * `academics/travel/travel.list`  — My travel forms (the four fixed
//                                        journeys + "Manage my travel contacts")
//
//  Spec: docs/spec/features.md §1.9, docs/spec/parsers.md §14,
//  W4_PORT_PLAN.md Wave 4 item 4.10.
//
//  NAMING (plan D-5). `parsers.md` §14 spells these `W4Trip` / `W4TripStatus`;
//  `features.md` §1.9 spells them `Trip` / `TripStatus`. D-5 settles it: the
//  `W4` prefix is for wire/protocol types and parsers only, so the parser is
//  `W4TripsParser` and every model here is unprefixed. None of these names was
//  already taken by the legacy Lectio code.
//
//  EVIDENCE — read this before trusting any field.
//
//    [V] The two routes. `Fixtures/W4/academics-menu.html` (a real capture of
//        the Academics side menu) renders a "Trips" group linking
//        `index.php?r=academics/trips` ("My trips") and
//        `index.php?r=academics/travel/travel.list` ("My travel forms"), and the
//        real Home capture links `academics/trips` as "Trip Form".
//
//    [U] Everything else. **No trip grid and no travel-forms page has ever been
//        captured.** The column set (Trip name, outgoing, return, destination,
//        type, participants, status), the status ladder
//        (Planning → Pending confirmation → Approved | Cancelled) and the four
//        journeys come from a live GET *described in prose* in README §6 — not
//        from markup. Consequently:
//
//          * every field except `id`, `name` and `status`/`statusLabel` is
//            optional, because a column that is not in the header simply does
//            not exist and the parser must not invent one;
//          * the raw string W4 printed is always carried next to the parsed
//            value (`statusLabel`, `outgoingLabel`, `participantsLabel`, …), so
//            an unrecognised status is still displayable verbatim;
//          * `TripStatus.unknown` and `TravelForm.journey == nil` are ordinary,
//            expected outcomes, not error states.
//
//  All types are plain `Sendable` value types so `W4TripsParser` can stay
//  `nonisolated`, pure and synchronous.
//

import Foundation

// MARK: - Trip status

/// Where a trip sits in W4's approval ladder.
///
/// README §6: `Planning → Pending confirmation (house leader and/or absences
/// manager) → Approved (pre-arranged absences are auto-registered) | Cancelled`.
///
/// The vocabulary is **[U]** — described in prose, never captured — so matching
/// is deliberately fuzzy and `unknown` is a first-class outcome. The raw label
/// travels with every `Trip` (`statusLabel`) and is what the UI shows; this enum
/// only drives grouping, ordering and icons.
enum TripStatus: String, Codable, Sendable, Hashable, CaseIterable {
    case planning
    case pendingConfirmation
    case approved
    case cancelled
    case unknown

    /// Case- and punctuation-insensitive match on whatever W4 printed.
    /// Unrecognised text becomes `.unknown` — never a crash, never a guess.
    init(label: String?) {
        self = TripStatus.status(forLabel: label) ?? .unknown
    }

    /// Returns `nil` (rather than `.unknown`) when the label carries no
    /// recognisable status, so a caller can tell "W4 said something we do not
    /// know" apart from "W4 said nothing at all".
    static func status(forLabel label: String?) -> TripStatus? {
        let text = normalize(label)
        guard !text.isEmpty else { return nil }

        // Order matters. "Pending confirmation" contains "confirm", and
        // "Not approved" contains "approved" — the narrower reading has to win.
        if text.contains("pending") || text.contains("awaiting")
            || text.contains("for confirmation") || text.contains("submitted") {
            return .pendingConfirmation
        }
        if text.contains("cancel") || text.contains("rejected") || text.contains("declined")
            || text.contains("withdrawn") || text.contains("not approved") {
            return .cancelled
        }
        if text.contains("approved") || text.contains("confirmed") || text.contains("accepted") {
            return .approved
        }
        if text.contains("planning") || text.contains("planned") || text.contains("draft") {
            return .planning
        }
        return nil
    }

    /// English UI label. There is no Danish anywhere in this port.
    var displayName: String {
        switch self {
        case .planning: return "Planning"
        case .pendingConfirmation: return "Pending confirmation"
        case .approved: return "Approved"
        case .cancelled: return "Cancelled"
        case .unknown: return "Unknown"
        }
    }

    /// True once the trip has left the approval ladder in either direction.
    var isSettled: Bool {
        self == .approved || self == .cancelled
    }

    /// README §6: approving a trip auto-registers the participants'
    /// **pre-arranged absences**. Wave 5 uses this to invalidate the attendance
    /// cache after a trip refresh; nothing in Wave 4 acts on it.
    var registersPrearrangedAbsences: Bool {
        self == .approved
    }

    /// Chronological position in the ladder, for stable sorting. `unknown`
    /// sorts last because we cannot place it.
    var ladderOrder: Int {
        switch self {
        case .planning: return 0
        case .pendingConfirmation: return 1
        case .approved: return 2
        case .cancelled: return 3
        case .unknown: return 4
        }
    }

    /// Lowercases, turns every non-alphanumeric into a space and collapses runs
    /// of whitespace, so `"Pending confirmation (house leader)"` and
    /// `"PENDING-CONFIRMATION"` normalise to the same haystack.
    private static func normalize(_ raw: String?) -> String {
        guard let raw else { return "" }
        let mapped = raw.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : " "
        }
        return String(mapped)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }
}

// MARK: - Trip

/// One row of `academics/trips`.
///
/// Every optional field is optional because the grid has never been captured:
/// the parser is header-driven, and a column W4 does not render simply yields
/// `nil` rather than shifting a neighbouring value into the wrong field.
struct Trip: Identifiable, Codable, Equatable, Hashable, Sendable {
    /// `?id=` from the row's own link when there is one, otherwise a content
    /// hash. Never the row index (bug B19) and never `tr[id]` (bug B18) — a Yii
    /// grid can be re-sorted or paged, and both of those reshuffle identity.
    let id: String
    /// The trip name, verbatim.
    let name: String
    /// Parsed in `Europe/Oslo` via `W4Dates`, or `nil` when the cell did not
    /// parse (or the column does not exist).
    let outgoing: Date?
    /// The outgoing cell exactly as W4 wrote it (`"20-Sep-2026 08:00"`), so the
    /// UI can show something even in a format `W4Dates` does not know.
    let outgoingLabel: String?
    let returning: Date?
    let returningLabel: String?
    let destination: String?
    /// W4's own trip type ("Optional", …), verbatim.
    let type: String?
    /// Set **only** when the participants cell is a bare count. `parsers.md` §14
    /// warns the cell may hold a name list instead, which is why
    /// `participantsLabel` is the field the UI should render.
    let participants: Int?
    let participantsLabel: String?
    let status: TripStatus
    /// The raw status string, always retained and always displayable — this is
    /// the field the UI shows, `status` is only for grouping.
    let statusLabel: String
    /// The row link's `href`, verbatim, when the grid rendered one.
    let href: String?
    /// The W4 route of `href` (`academics/trips`), when it resolves to one.
    let route: String?

    init(
        id: String,
        name: String,
        outgoing: Date? = nil,
        outgoingLabel: String? = nil,
        returning: Date? = nil,
        returningLabel: String? = nil,
        destination: String? = nil,
        type: String? = nil,
        participants: Int? = nil,
        participantsLabel: String? = nil,
        status: TripStatus = .unknown,
        statusLabel: String = "",
        href: String? = nil,
        route: String? = nil
    ) {
        self.id = id
        self.name = name
        self.outgoing = outgoing
        self.outgoingLabel = outgoingLabel
        self.returning = returning
        self.returningLabel = returningLabel
        self.destination = destination
        self.type = type
        self.participants = participants
        self.participantsLabel = participantsLabel
        self.status = status
        self.statusLabel = statusLabel
        self.href = href
        self.route = route
    }

    /// What to put on a status chip: W4's own words when it wrote any, and the
    /// enum's English label only as a last resort.
    var statusDisplay: String {
        let trimmed = statusLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? status.displayName : trimmed
    }

    /// True when the trip spans more than one Oslo day. `false` whenever either
    /// end of the trip failed to parse — an unknown span is not a long one.
    var isMultiDay: Bool {
        guard let start = outgoing, let end = returning else { return false }
        return !W4Dates.isSameDay(start, end)
    }
}

extension Trip {
    /// Stable, sort-independent identity for a trip with no `?id=` in its row
    /// (bug B19). Hashes what the row is *about* with a deterministic FNV-1a so
    /// the id survives relaunches — Swift's own `hashValue` is seeded per
    /// process and would not.
    static func identity(
        name: String,
        outgoingLabel: String?,
        destination: String?,
        occurrence: Int = 0
    ) -> String {
        let payload = [name, outgoingLabel ?? "", destination ?? ""].joined(separator: "|")
        let suffix = occurrence > 0 ? "-\(occurrence)" : ""
        return "trip-\(fnv1aHex(payload))\(suffix)"
    }

    /// 64-bit FNV-1a as 16 lowercase hex digits. Deterministic across launches,
    /// platforms and Swift versions.
    static func fnv1aHex(_ string: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        let prime: UInt64 = 0x0000_0100_0000_01b3
        for byte in Array(string.utf8) {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        let hex = String(hash, radix: 16)
        if hex.count >= 16 { return hex }
        return String(repeating: "0", count: 16 - hex.count) + hex
    }
}

// MARK: - A parsed trips page

/// The result of parsing one page of `academics/trips`.
///
/// Empty plus a message for every failure mode — unparseable HTML, no grid, a
/// signed-out page. The parser never throws and never partially fails.
struct TripList: Codable, Equatable, Sendable {
    /// The page's own `<h2>` ("My trips"), when it has one.
    let title: String?
    let trips: [Trip]
    /// True when W4 rendered a Yii pager, or a summary that says there are more
    /// results than this page shows (bug B10). The app surfaces "more on W4"
    /// rather than pretending page 1 is everything.
    let hasMorePages: Bool
    /// The verbatim empty-state text W4 rendered (`td.empty`, `span.empty`,
    /// `No results found.`, `div.note`), when there was one (bug B9).
    let emptyMessage: String?
    /// True when the page offers "Plan new trip". v1 is read-only: the button
    /// opens the W4 page in the in-app `WKWebView` (D-24), it does not POST.
    let canPlanNewTrip: Bool
    /// The "Plan new trip" href when that affordance is an anchor. `nil` when
    /// it is a Yii `<input type="button">` with an onclick, which is the shape
    /// the Android fixture shows.
    let planNewTripHref: String?
    /// False when the grid carried no header row at all and the parser fell
    /// back to the documented **[I]** column order. Every header-driven parse
    /// leaves this `true`.
    let isHeaderDriven: Bool

    init(
        title: String? = nil,
        trips: [Trip] = [],
        hasMorePages: Bool = false,
        emptyMessage: String? = nil,
        canPlanNewTrip: Bool = false,
        planNewTripHref: String? = nil,
        isHeaderDriven: Bool = true
    ) {
        self.title = title
        self.trips = trips
        self.hasMorePages = hasMorePages
        self.emptyMessage = emptyMessage
        self.canPlanNewTrip = canPlanNewTrip
        self.planNewTripHref = planNewTripHref
        self.isHeaderDriven = isHeaderDriven
    }

    static let empty = TripList(isHeaderDriven: false)

    var isEmpty: Bool { trips.isEmpty }

    /// True when at least one trip is approved. README §6: approval
    /// auto-registers pre-arranged absences, so Wave 5 invalidates the
    /// attendance cache when this flips.
    var hasApprovedTrip: Bool {
        trips.contains { $0.status == .approved }
    }

    func trips(withStatus status: TripStatus) -> [Trip] {
        trips.filter { $0.status == status }
    }
}

// MARK: - Travel forms

/// The four fixed journeys of the UWC RCN year (README §6).
///
/// Exactly four cases, so `allCases` really is "the journeys a student must
/// file". A form whose title matches none of them keeps `journey == nil` rather
/// than being forced into a bogus case.
enum TravelJourney: String, Codable, Sendable, Hashable, CaseIterable {
    /// Arriving for the autumn term.
    case toSchoolAutumn
    /// Leaving for the winter break.
    case homeWinter
    /// Coming back after the winter break.
    case backAfterWinter
    /// Leaving at the end of the year.
    case homeSummer

    var displayName: String {
        switch self {
        case .toSchoolAutumn: return "To school in autumn"
        case .homeWinter: return "Home for winter"
        case .backAfterWinter: return "Back after winter"
        case .homeSummer: return "Home for summer"
        }
    }

    /// Chronological position in the academic year, 0...3.
    var order: Int {
        switch self {
        case .toSchoolAutumn: return 0
        case .homeWinter: return 1
        case .backAfterWinter: return 2
        case .homeSummer: return 3
        }
    }

    /// Best-effort classification of a form title.
    ///
    /// **[U] heuristic.** The travel-forms page has never been captured, so the
    /// exact wording of the four rows is unknown; this reads season words first
    /// and direction words second. `nil` means "this does not look like one of
    /// the four", which the UI renders using the raw title.
    static func classify(_ title: String?) -> TravelJourney? {
        let text = normalize(title)
        guard !text.isEmpty else { return nil }

        let winter = text.contains("winter") || text.contains("christmas")
            || text.contains("december") || text.contains("january")
        let summer = text.contains("summer") || text.contains("june")
            || text.contains("july") || text.contains("end of year")
        let autumn = text.contains("autumn") || text.contains("fall")
            || text.contains("august") || text.contains("september")
            || text.contains("start of year") || text.contains("new school year")
        // "back home for winter" must NOT read as a return to school, which is
        // why this looks for "back to" and not for a bare "back".
        let towardsSchool = text.contains("to school") || text.contains("to college")
            || text.contains("back to") || text.contains("returning to")
            || text.contains("arrival") || text.contains("arriving")

        if winter { return towardsSchool ? .backAfterWinter : .homeWinter }
        if summer { return towardsSchool ? .toSchoolAutumn : .homeSummer }
        if autumn { return .toSchoolAutumn }
        return nil
    }

    private static func normalize(_ raw: String?) -> String {
        guard let raw else { return "" }
        let mapped = raw.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : " "
        }
        return String(mapped)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }
}

/// One row / link on `academics/travel/travel.list`.
///
/// v1 is read-only (features.md §1.9): opening a form hands `href` to the
/// in-app `WKWebView` with the session cookie (D-24). No field here is written
/// back to W4.
struct TravelForm: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: String
    /// `nil` when the title matches none of the four fixed journeys — an
    /// ordinary outcome, not an error.
    let journey: TravelJourney?
    /// The title W4 printed, verbatim.
    let title: String
    /// The raw status cell, when the page renders one. Always displayable.
    let statusLabel: String?
    let href: String?
    let route: String?

    init(
        id: String,
        journey: TravelJourney? = nil,
        title: String,
        statusLabel: String? = nil,
        href: String? = nil,
        route: String? = nil
    ) {
        self.id = id
        self.journey = journey
        self.title = title
        self.statusLabel = statusLabel
        self.href = href
        self.route = route
    }

    /// W4's own words when it wrote any, the journey's English name otherwise.
    var displayName: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return journey?.displayName ?? "Travel form"
    }
}

/// The result of parsing `academics/travel/travel.list`.
struct TravelPage: Codable, Equatable, Sendable {
    /// The page's own `<h2>` ("My travel forms"), when it has one.
    let title: String?
    let forms: [TravelForm]
    /// "Manage my travel contacts" — a link, not a form. v1 opens it in the
    /// in-app browser; the contacts page itself has never been captured.
    let manageContactsHref: String?
    let manageContactsRoute: String?
    /// The link's own text, verbatim.
    let manageContactsLabel: String?
    /// The verbatim empty-state text W4 rendered, when there was one (bug B9).
    let emptyMessage: String?

    init(
        title: String? = nil,
        forms: [TravelForm] = [],
        manageContactsHref: String? = nil,
        manageContactsRoute: String? = nil,
        manageContactsLabel: String? = nil,
        emptyMessage: String? = nil
    ) {
        self.title = title
        self.forms = forms
        self.manageContactsHref = manageContactsHref
        self.manageContactsRoute = manageContactsRoute
        self.manageContactsLabel = manageContactsLabel
        self.emptyMessage = emptyMessage
    }

    static let empty = TravelPage()

    var isEmpty: Bool { forms.isEmpty && manageContactsHref == nil }

    var hasContactsLink: Bool { manageContactsHref != nil }

    func form(for journey: TravelJourney) -> TravelForm? {
        forms.first { $0.journey == journey }
    }

    /// Which of the four fixed journeys this page did not render. Useful to the
    /// UI, and a loud signal in tests when a capture finally arrives.
    var missingJourneys: [TravelJourney] {
        TravelJourney.allCases.filter { form(for: $0) == nil }
    }

    /// The known journeys in academic-year order, then everything unclassified
    /// in the order W4 rendered it.
    var sortedForms: [TravelForm] {
        let known = forms
            .filter { $0.journey != nil }
            .sorted { ($0.journey?.order ?? 0) < ($1.journey?.order ?? 0) }
        let rest = forms.filter { $0.journey == nil }
        return known + rest
    }
}

// MARK: - Travel contacts

/// One row of the "Manage my travel contacts" page.
///
/// **[U] — that page has never been captured.** The shape comes from
/// `features.md` §1.9; every field but `id` and `name` is optional.
struct TravelContact: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
    /// "Mother", "Guardian", … verbatim.
    let relation: String?
    let phone: String?
    let email: String?

    init(
        id: String,
        name: String,
        relation: String? = nil,
        phone: String? = nil,
        email: String? = nil
    ) {
        self.id = id
        self.name = name
        self.relation = relation
        self.phone = phone
        self.email = email
    }
}
