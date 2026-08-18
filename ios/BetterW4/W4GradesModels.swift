//
//  W4GradesModels.swift
//  BetterW4
//
//  Domain models for the W4 grades table (`academics/grades/grades` and
//  `academics/grades/grades/sat`). Spec: docs/spec/parsers.md §10,
//  docs/spec/features.md §1.6, W4_PORT_PLAN.md D-14 and OQ-12.
//
//  NAMING. Every type here is W4-prefixed because the LEGACY Lectio grades code
//  still owns the unprefixed names: `GradesReport`, `GradeColumn`, `GradeEntry`,
//  `GradeCellValue` and `GradeNoteEntry` live in `GradeModels.swift` and
//  `GradesView` / `GradesViewModel` / `SubjectGradeDetailView` still compile
//  against them. Nothing in this file touches those; a later wave deletes them.
//
//  SCALE. These are **IB** grades, not the Danish 7-point scale. Every Lectio
//  assumption is wrong here: there is no 12/10/7/4/02/00/-3, no "standpunkt"
//  column, no XPRS subject and — per D-14 — **no weight**. `Vægt` was Lectio's;
//  W4 has no such concept, and what W4 does have instead is an *effort grade*
//  with its own three-level vocabulary.
//
//  EVIDENCE.
//    [V] W4's own `css/main.css` styles `table.grades th.anticipated`,
//        `table.grades tr.table_1_bg td.anticipated`,
//        `.effort-grade-meets-expectations`,
//        `.effort-grade-almost-meets-expectations` and
//        `.effort-grade-does-not-meet-expectations`. So an anticipated
//        (predicted) column and a three-level effort grade both exist, and the
//        grades page is `table.grades`, not the generic `table.items` (bug B13).
//    [U] **The grades page itself has never been captured.** Not one header, not
//        one row. Which columns exist, what they are called and in what order
//        they appear is unknown — which is exactly why columns here are dynamic,
//        derived from the server's own header row, and keyed by slug.
//
//  All types are plain `Sendable` value types so the parser can stay
//  `nonisolated` and synchronous.
//

import Foundation

// MARK: - Effort grade

/// W4's effort vocabulary, taken from the three `.effort-grade-*` classes the
/// server's stylesheet defines **[V]**.
///
/// This is deliberately *not* a number: an effort grade is a judgement, it is
/// never averaged with an IB grade, and it never shares a scale with one.
enum W4EffortGrade: String, Codable, Sendable, Hashable, CaseIterable {
    case meets = "meets"
    case almostMeets = "almost-meets"
    case doesNotMeet = "does-not-meet"

    /// Maps a single CSS class token onto an effort level.
    ///
    /// The three exact class names are matched first; the tolerant branch below
    /// only exists so that a wording change on the server ("meets-expectation")
    /// degrades to the right level instead of to `nil`.
    init?(className raw: String) {
        let token = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let prefix = "effort-grade-"
        guard token.hasPrefix(prefix) else { return nil }

        let suffix = String(token.dropFirst(prefix.count))
        switch suffix {
        case "meets-expectations":
            self = .meets
        case "almost-meets-expectations":
            self = .almostMeets
        case "does-not-meet-expectations":
            self = .doesNotMeet
        default:
            if suffix.contains("almost") {
                self = .almostMeets
            } else if suffix.contains("not") {
                self = .doesNotMeet
            } else if suffix.contains("meet") {
                self = .meets
            } else {
                return nil
            }
        }
    }

    /// The English label W4 uses for this level. No Danish anywhere in this port.
    var displayName: String {
        switch self {
        case .meets: return "Meets expectations"
        case .almostMeets: return "Almost meets expectations"
        case .doesNotMeet: return "Does not meet expectations"
        }
    }

    /// Best-to-worst ordering for sorting and tinting. Not a score, and never
    /// mixed into an average.
    var rank: Int {
        switch self {
        case .meets: return 2
        case .almostMeets: return 1
        case .doesNotMeet: return 0
        }
    }
}

// MARK: - Column

/// One column of the grades table, identified by a slug of the server's own
/// header text.
///
/// Columns are dynamic on purpose (OQ-12): W4 decides which columns exist and in
/// which order, and the parser must never assume a fixed layout. `id` is what
/// cells are keyed by, so a missing or re-ordered column drops out of the report
/// instead of shifting somebody else's grade into the wrong place.
struct W4GradeColumn: Identifiable, Codable, Hashable, Sendable {
    /// Slug of `label`, de-duplicated with a `-2`, `-3`… suffix on collision.
    let id: String
    /// The header text verbatim, for display.
    let label: String
    /// `th.anticipated` (or `td.anticipated` on this column's cells) **[V]** —
    /// W4's word for a predicted grade.
    let isAnticipated: Bool

    init(id: String, label: String, isAnticipated: Bool = false) {
        self.id = id
        self.label = label
        self.isAnticipated = isAnticipated
    }
}

// MARK: - Cell

/// One grade cell: what W4 printed, plus the effort grade carried by the cell's
/// CSS class when there is one (D-14).
///
/// A cell only exists when W4 had something to say. An un-graded subject renders
/// an en dash or a hyphen, and that becomes **no cell at all** — never a cell
/// whose value is the dash, and never a cell whose value is `""`. The single
/// exception is a cell that carries an `.effort-grade-*` class but no text: the
/// effort grade is real information, so the cell survives with an empty `value`.
struct W4GradeCell: Codable, Hashable, Sendable {
    /// Exactly what the cell said, whitespace-collapsed. Never coerced to a
    /// number: IB grades are 1–7 but predicted and effort columns are free text.
    let value: String
    /// From `.effort-grade-meets-expectations` and friends **[V]**.
    let effort: W4EffortGrade?

    init(value: String, effort: W4EffortGrade? = nil) {
        self.value = value
        self.effort = effort
    }

    var hasValue: Bool { !value.isEmpty }

    /// The value as an IB grade, and *only* when it is unambiguously one.
    ///
    /// Strict on purpose: `"7"` is 7, while `"7 (predicted)"`, `"A"`, `"Pass"`
    /// and `"N/A"` are all `nil`. features.md §1.6 is explicit that predicted and
    /// effort columns are free text and must never be coerced.
    var ibGrade: Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 1, let grade = Int(trimmed), (1...7).contains(grade) else {
            return nil
        }
        return grade
    }

    /// `(n - 1) / 6` on the IB branch — the one piece of Lectio's grade maths
    /// that survives the port (features.md §1.6). `nil` for anything that is not
    /// an IB grade, so a progress bar simply is not drawn.
    var ibProgress: Double? {
        guard let grade = ibGrade else { return nil }
        return Double(grade - 1) / 6.0
    }
}

// MARK: - Row

/// One subject row: identity on the left, one cell per dynamic column.
struct W4GradeRow: Identifiable, Codable, Hashable, Sendable {
    /// Slug of subject + level, de-duplicated so two rows for the same subject
    /// stay distinct in a `ForEach`.
    let id: String
    /// `"Mathematics"`. The IB level is split off into `level` when W4 puts it
    /// in the subject text.
    let subject: String
    /// `"HL"` / `"SL"` when W4 said so, `nil` when it did not. Never guessed
    /// from the subject name itself.
    let level: String?
    let teacher: String?
    /// Keyed by `W4GradeColumn.id`. A column with no grade for this row has **no
    /// entry** — look-ups return `nil`, never `""`.
    let cells: [String: W4GradeCell]

    init(
        id: String,
        subject: String,
        level: String? = nil,
        teacher: String? = nil,
        cells: [String: W4GradeCell] = [:]
    ) {
        self.id = id
        self.subject = subject
        self.level = level
        self.teacher = teacher
        self.cells = cells
    }

    func cell(for columnID: String) -> W4GradeCell? {
        cells[columnID]
    }

    /// `"Mathematics HL"` — the two identity fields joined for display.
    var displaySubject: String {
        guard let level, !level.isEmpty else { return subject }
        return subject.isEmpty ? level : "\(subject) \(level)"
    }
}

// MARK: - Report

/// One parsed grades page.
struct W4GradesReport: Codable, Equatable, Sendable {
    /// The page heading verbatim, when it has one.
    let title: String?
    /// In the server's own order, identity columns removed.
    let columns: [W4GradeColumn]
    let rows: [W4GradeRow]
    /// `div.errorMessage`, `div.error`, `div.warning`, `div.note` **[V]**, in
    /// document order.
    let alerts: [String]
    /// The Yii empty-state sentence ("No results found.") or the page's own
    /// `div.note`, when there are no rows to show.
    let emptyMessage: String?
    /// Set by whoever fetched the page, never by the parser: parsers are pure
    /// and must not read a clock.
    let fetchedAt: Date?

    init(
        title: String? = nil,
        columns: [W4GradeColumn] = [],
        rows: [W4GradeRow] = [],
        alerts: [String] = [],
        emptyMessage: String? = nil,
        fetchedAt: Date? = nil
    ) {
        self.title = title
        self.columns = columns
        self.rows = rows
        self.alerts = alerts
        self.emptyMessage = emptyMessage
        self.fetchedAt = fetchedAt
    }

    /// The honest empty result: no columns, no rows, nothing invented.
    static let empty = W4GradesReport()

    var isEmpty: Bool { rows.isEmpty }

    func column(withID id: String) -> W4GradeColumn? {
        columns.first { $0.id == id }
    }

    /// The anticipated (predicted) columns, in server order.
    var anticipatedColumns: [W4GradeColumn] {
        columns.filter(\.isAnticipated)
    }

    func withFetchedAt(_ date: Date?) -> W4GradesReport {
        W4GradesReport(
            title: title,
            columns: columns,
            rows: rows,
            alerts: alerts,
            emptyMessage: emptyMessage,
            fetchedAt: date
        )
    }

    /// Column-id preference for "the one column to show when there is only room
    /// for one" — ported from Android's `GradeAverage.defaultColumnKey`
    /// (features.md §1.6), with the Danish entries removed.
    static let preferredColumnIDs = ["final", "awarded", "predicted", "term-2", "term-1"]

    /// The column a summary view should lead with, or `nil` when there are none.
    var defaultColumnID: String? {
        for candidate in Self.preferredColumnIDs where columns.contains(where: { $0.id == candidate }) {
            return candidate
        }
        return columns.first?.id
    }

    /// Mean IB grade of one column, or `nil` when that column holds no IB grades.
    ///
    /// Never mixes columns (features.md §1.6) and never averages free text: only
    /// cells whose value is a bare 1–7 count. There is no weighting, because
    /// W4 has no weights (D-14).
    func average(forColumnID id: String) -> Double? {
        let grades = rows.compactMap { $0.cells[id]?.ibGrade }
        guard !grades.isEmpty else { return nil }
        return Double(grades.reduce(0, +)) / Double(grades.count)
    }
}
