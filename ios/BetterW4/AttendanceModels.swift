//
//  AttendanceModels.swift
//  BetterW4
//
//  Domain models for W4 attendance: the two Home meters and the AC / EA
//  registration lists. Spec: docs/spec/features.md §1.5, docs/spec/parsers.md §8,
//  W4_PORT_PLAN.md D-13.
//
//  W4 counts *events*, not percentages: "You have 0 absences and 0 latenesses so
//  far". Nothing in this file computes a percentage, and nothing in this file
//  derives a meter from a list of rows — per D-13 meter counts come from the
//  meter prose only. Lectio's percentage-shaped models (`AbsenceSummary`,
//  `SubjectAbsence`, `AbsenceEntry`…) live on in AbsenceModels.swift until a
//  later wave deletes them; nothing here touches them.
//
//  All types are plain `Sendable` value types so the parser can stay
//  `nonisolated` and synchronous.
//

import Foundation

// MARK: - Source

/// Which of W4's two attendance ledgers a meter or a record belongs to.
///
/// Raw values are the two-letter tags `features.md` §1.5 uses for cache keys.
enum AttendanceSource: String, Codable, Sendable, Hashable, CaseIterable {
    case academics = "ac"
    case extraAcademics = "ea"

    /// Yii `…/list` page — the real registrations table.
    var listRoute: String {
        switch self {
        case .academics: return W4Routes.R.absencesList
        case .extraAcademics: return W4Routes.R.eaAbsencesList
        }
    }

    /// Every route W4 writes for this source. Home links the bare route, the
    /// week grid is `…/index` and the registrations table is `…/list`; all
    /// three are this ledger. `…/absences/register` is the form — a different
    /// page, and deliberately absent.
    var routes: [String] {
        switch self {
        case .academics:
            return [W4Routes.R.absences, W4Routes.R.absencesIndex, W4Routes.R.absencesList]
        case .extraAcademics:
            return [W4Routes.R.eaAbsences, W4Routes.R.eaAbsencesIndex, W4Routes.R.eaAbsencesList]
        }
    }

    /// Exact match against any of `routes`, case-insensitively.
    func owns(route: String) -> Bool {
        let normalized = route
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return routes.contains { $0.lowercased() == normalized }
    }

    /// Default week grid (`people/students/absences` / `eaabsences`).
    var weekRoute: String {
        switch self {
        case .academics: return W4Routes.R.absencesIndex
        case .extraAcademics: return W4Routes.R.eaAbsencesIndex
        }
    }

    /// English UI label. There is no Danish anywhere in this port.
    var displayName: String {
        switch self {
        case .academics: return "Academics"
        case .extraAcademics: return "Extra Academics"
        }
    }

    /// The meter heading W4 renders on Home, for reference in tests and UI.
    var meterTitle: String {
        switch self {
        case .academics: return "Academics Attendance Meter"
        case .extraAcademics: return "EA Attendance Meter"
        }
    }

    /// Maps a W4 route back to its source. Exact match only — note that
    /// `people/students/absences/register` is a *different* page and must not
    /// resolve to `.academics`.
    static func source(forRoute route: String) -> AttendanceSource? {
        AttendanceSource.allCases.first { $0.owns(route: route) }
    }
}

enum AttendanceFeatureFlags {
    static let writesEnabled = true
}

// MARK: - Kind

/// What a single attendance row records.
///
/// D-13: one taxonomy, six cases, and the **raw** `status` string is carried
/// alongside it and rendered verbatim — the enum is for grouping and icons, the
/// string is for telling the student what W4 actually said.
///
/// `prearranged` and `medical` are here because W4's own `css/tables.css` styles
/// `tr.prearranged_1`, `tr.prearranged_2`, `tr.medical_1` and `tr.medical_2`
/// **[V]**, and `display_full_timetable.css` uses the same vocabulary
/// (`.present` / `.normal` / `.prearranged` / `.absence`). `unknown` is the
/// honest answer for everything else: no absence list has ever been captured.
enum AttendanceKind: String, Codable, Sendable, Hashable, CaseIterable {
    case absence
    case lateness
    case prearranged
    case medical
    case present
    case unknown

    var displayName: String {
        switch self {
        case .absence: return "Absence"
        case .lateness: return "Lateness"
        case .prearranged: return "Prearranged"
        case .medical: return "Medical"
        case .present: return "Present"
        case .unknown: return "Registration"
        }
    }

    /// True for the kinds the Home meters count. Informational only — the app
    /// never derives a meter from rows (D-13).
    var countsTowardsMeter: Bool {
        self == .absence || self == .lateness
    }

    /// Row classes → kind (bug B14). Yii's own `odd` / `even` / `selected`
    /// classes and the `_1` / `_2` striping suffixes are ignored.
    ///
    /// Returns `nil` when no class carries a category, so the caller can fall
    /// back to the "Type" column text.
    static func kind(forRowClasses classes: [String]) -> AttendanceKind? {
        for raw in classes {
            let token = stripStripeSuffix(raw.lowercased())
            switch token {
            case "prearranged": return .prearranged
            case "medical": return .medical
            case "lateness", "late": return .lateness
            case "absence", "absent": return .absence
            case "present": return .present
            default: continue
            }
        }
        return nil
    }

    /// Free text ("Prearranged absence", "Lateness", "Medical") → kind.
    ///
    /// Order matters: `prearranged` and `medical` win over `absence` so that a
    /// row typed "Prearranged absence" is not filed as a plain absence, and
    /// "Not present" is not filed as `.present`.
    static func kind(forLabel label: String?) -> AttendanceKind? {
        guard let text = label?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !text.isEmpty else { return nil }

        if text.contains("prearranged") || text.contains("pre-arranged") { return .prearranged }
        if text.contains("medical") { return .medical }
        if text.contains("lateness") || text.contains("late") { return .lateness }
        if text.contains("absence") || text.contains("absent") { return .absence }
        if text.contains("not present") { return .absence }
        if text.contains("present") { return .present }
        return nil
    }

    /// `prearranged_1` → `prearranged`; `medical_2` → `medical`.
    private static func stripStripeSuffix(_ token: String) -> String {
        guard let underscore = token.lastIndex(of: "_") else { return token }
        let suffix = token[token.index(after: underscore)...]
        guard !suffix.isEmpty, suffix.allSatisfy({ $0.isNumber }) else { return token }
        return String(token[token.startIndex..<underscore])
    }
}

// MARK: - Meters

/// One Home attendance meter: "You have N absences and M latenesses so far".
///
/// Both numbers come from that sentence and from nowhere else (D-13).
struct AttendanceMeter: Codable, Equatable, Hashable, Sendable {
    let absences: Int
    let latenesses: Int

    var total: Int { absences + latenesses }
    var isClean: Bool { absences == 0 && latenesses == 0 }

    static let zero = AttendanceMeter(absences: 0, latenesses: 0)
}

/// Both Home meters. Either may be `nil`: a meter W4 did not render is *absent*,
/// which is a different fact from a meter that reads zero, and the UI must be
/// able to tell them apart.
struct AttendanceMeters: Codable, Equatable, Hashable, Sendable {
    let academic: AttendanceMeter?
    let extraAcademic: AttendanceMeter?

    static let empty = AttendanceMeters(academic: nil, extraAcademic: nil)

    var isEmpty: Bool { academic == nil && extraAcademic == nil }

    func meter(for source: AttendanceSource) -> AttendanceMeter? {
        switch source {
        case .academics: return academic
        case .extraAcademics: return extraAcademic
        }
    }
}

// MARK: - Records

/// One row of `people/students/absences` or `people/students/eaabsences`.
///
/// Every field except `id`, `source`, `displayDate`, `kind` and `status` is
/// optional because **the list page has never been captured**: a column that is
/// not in the header simply does not appear, and the parser must not invent one.
struct AttendanceRecord: Identifiable, Codable, Equatable, Hashable, Sendable {
    /// Content hash, never the row index (bug B19): a Yii grid can be re-sorted
    /// (`a.sort_asc` / `a.sort_desc` are **[V]**) or paged, and an index-derived
    /// id would silently reassign every row's identity when it is.
    let id: String
    let source: AttendanceSource
    /// Parsed in `Europe/Oslo` via `W4Dates`, or `nil` when the cell did not parse.
    let date: Date?
    /// The date cell exactly as W4 wrote it, so the UI can show something even
    /// when the format is one `W4Dates` does not know.
    let displayDate: String
    let period: String?
    /// Class / activity / group label, verbatim.
    let subject: String?
    let kind: AttendanceKind
    /// The raw status W4 printed, rendered verbatim (D-13). Falls back to the
    /// "Type" column when the grid has no status column, and is `""` when the
    /// grid has neither.
    let status: String
    let teacher: String?
    let note: String?
    /// "Added by" / "Student was" only exist on some grids, so both stay
    /// defaulted in the memberwise init for the rows that lack them.
    var addedBy: String? = nil
    var studentWas: String? = nil

    /// W4 absence rows are read-only for students; there is no edit affordance.
    var isEditable: Bool { false }
}

extension AttendanceRecord {
    /// Stable, sort-independent identity for a row (bug B19).
    ///
    /// Hashes the content the row is *about* — source, the raw date text, the
    /// period, the subject and the kind — with a deterministic FNV-1a so the id
    /// survives app relaunches (Swift's own `hashValue` is seeded per process
    /// and would not). `occurrence` disambiguates rows whose content is byte
    /// identical, which keeps `Identifiable` ids unique in a SwiftUI list.
    static func identity(
        source: AttendanceSource,
        dateRaw: String,
        period: String?,
        subject: String?,
        kind: AttendanceKind,
        occurrence: Int = 0
    ) -> String {
        let payload = [
            source.rawValue,
            dateRaw,
            period ?? "",
            subject ?? "",
            kind.rawValue
        ].joined(separator: "|")
        let suffix = occurrence > 0 ? "-\(occurrence)" : ""
        return "\(source.rawValue)-\(fnv1aHex(payload))\(suffix)"
    }

    /// 64-bit FNV-1a, rendered as 16 lowercase hex digits. Deterministic across
    /// launches, platforms and Swift versions.
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

// MARK: - A parsed list page

/// The result of parsing one absence list page.
///
/// `records` is empty and `meter` is `nil` for every failure mode — a page that
/// did not parse, a page with no grid, a signed-out page. The parser never
/// throws and never partially fails; it degrades.
struct AttendanceList: Codable, Equatable, Sendable {
    let source: AttendanceSource
    /// Scraped from the list page's own meter prose when it has one; `nil`
    /// otherwise. Never counted from `records` (D-13).
    let meter: AttendanceMeter?
    let records: [AttendanceRecord]
    /// True when W4 rendered a Yii pager or a summary that says there are more
    /// results than this page shows (bug B10). The app shows "more on W4"
    /// rather than pretending page 1 is everything.
    let hasMorePages: Bool
    /// The verbatim empty-state text W4 rendered (`td.empty`, `span.empty`,
    /// `No results found.`, `div.note`), when there was one (bug B9).
    let emptyMessage: String?

    var isEmpty: Bool { records.isEmpty }

    static func empty(
        source: AttendanceSource,
        meter: AttendanceMeter? = nil,
        message: String? = nil
    ) -> AttendanceList {
        AttendanceList(
            source: source,
            meter: meter,
            records: [],
            hasMorePages: false,
            emptyMessage: message
        )
    }
}

// MARK: - Aggregates for the UI

/// What the attendance screen shows: both meters plus whatever rows have been
/// fetched. Assembled by the repository (Wave 5), never by the parser — the
/// parser has no clock.
struct AttendanceOverview: Codable, Equatable, Sendable {
    let academic: AttendanceMeter
    let extraAcademic: AttendanceMeter
    let records: [AttendanceRecord]
    let fetchedAt: Date

    init(
        academic: AttendanceMeter? = nil,
        extraAcademic: AttendanceMeter? = nil,
        records: [AttendanceRecord] = [],
        fetchedAt: Date
    ) {
        self.academic = academic ?? .zero
        self.extraAcademic = extraAcademic ?? .zero
        self.records = records
        self.fetchedAt = fetchedAt
    }

    func meter(for source: AttendanceSource) -> AttendanceMeter {
        switch source {
        case .academics: return academic
        case .extraAcademics: return extraAcademic
        }
    }

    func records(for source: AttendanceSource) -> [AttendanceRecord] {
        records.filter { $0.source == source }
    }
}

/// Per-class breakdown by **count** — W4 has no percentages, so neither do we.
///
/// Replaces Lectio's `SubjectAbsence` (which averaged percentages). The label is
/// whatever W4 wrote in the class / activity column, verbatim; subject naming
/// and colouring is `SubjectMapper`'s job, not this type's.
struct SubjectAttendance: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: String { label }
    let label: String
    let absences: Int
    let latenesses: Int
    let prearranged: Int
    let medical: Int
    let total: Int

    /// Groups records by class label, most registrations first, ties broken
    /// alphabetically so the order is stable between parses. Rows with no
    /// subject label are grouped under `unlabelled`.
    static func breakdown(
        of records: [AttendanceRecord],
        unlabelled: String = "Unspecified"
    ) -> [SubjectAttendance] {
        var order: [String] = []
        var grouped: [String: [AttendanceRecord]] = [:]
        for record in records {
            let trimmed = record.subject?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let label = trimmed.isEmpty ? unlabelled : trimmed
            if grouped[label] == nil {
                order.append(label)
                grouped[label] = []
            }
            grouped[label]?.append(record)
        }

        let rows: [SubjectAttendance] = order.compactMap { label in
            guard let bucket = grouped[label] else { return nil }
            return SubjectAttendance(
                label: label,
                absences: bucket.filter { $0.kind == .absence }.count,
                latenesses: bucket.filter { $0.kind == .lateness }.count,
                prearranged: bucket.filter { $0.kind == .prearranged }.count,
                medical: bucket.filter { $0.kind == .medical }.count,
                total: bucket.count
            )
        }

        return rows.sorted { left, right in
            if left.total != right.total { return left.total > right.total }
            return left.label.localizedCaseInsensitiveCompare(right.label) == .orderedAscending
        }
    }
}
