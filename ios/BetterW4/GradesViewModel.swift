//
//  GradesViewModel.swift
//  BetterW4
//
//  The Grades screen's view model, reading `academics/grades/grades` through `GradeRepository`
//  (`features.md` §1.6, §0 rule 2). No HTTP client, no parser, no Keychain.
//
//  These are **IB** grades. Everything the Lectio version assumed is wrong here and is gone: the
//  Danish 7-point scale (12/10/7/4/02/00/-3) and its red→green colour ramp, the fixed
//  `1.standpunkt` / `årskarakter` / `eksamenskarakter` axes, `Vægt` (W4 has no weights at all), the
//  `", Mundtlig"` → `(M)` subject suffix, and the Danish decimal comma. The columns W4 renders are
//  discovered from its own header row and keyed by slug, so a school that adds or reorders a column
//  simply gets a different table rather than a wrong one.
//
//  The average this exposes is the plain mean of a *single* column's IB 1–7 cells, formatted with a
//  point and one decimal. Columns are never mixed, free text is never coerced to a number, and a
//  column with no IB grades in it has no average — a predicted column full of "A"s does not average.
//
//  `features.md` §3 behaviours preserved: generation guard on every published mutation, cache-first
//  then always refresh, spinner only when there is nothing to show, error only when there is
//  nothing to show, in-memory reset on student switch, cancellation swallowed, and only
//  `.sessionExpired` logs out (`GradeRepository` degrades `.forbidden` to a cached copy or throws it
//  as a plain failure — it never reaches `notifyIfSessionExpired`).
//

import Foundation
import SwiftUI
import Combine

/// One column's mean IB grade, ready for a `ForEach`.
struct GradeColumnAverage: Identifiable, Equatable, Sendable {
    let column: W4GradeColumn
    /// Already formatted: one decimal, a point, English.
    let value: String

    var id: String { column.id }
}

@MainActor
final class GradesViewModel: ObservableObject {

    // MARK: - Published state

    @Published private(set) var report: W4GradesReport?
    @Published private(set) var freshness: W4Freshness?

    /// Blocking spinner: only with nothing rendered yet.
    @Published private(set) var isLoading = false
    /// Subtle indicator over content that is already on screen.
    @Published private(set) var isRefreshing = false

    @Published private(set) var errorMessage: String?

    /// `nil` means "All columns"; otherwise a `W4GradeColumn.id`.
    @Published var selectedColumnID: String?

    // MARK: - Dependencies

    private let repository: GradeRepository
    private let now: @Sendable () -> Date

    private var loadGeneration: UUID?
    private var activeStudentID: String?

    init(
        repository: GradeRepository = GradeRepository(),
        now: @escaping @Sendable () -> Date = { TimeProvider.now }
    ) {
        self.repository = repository
        self.now = now
    }

    // MARK: - Loading

    /// Cache-first render, then a refresh. `forceRefresh` is `false` when the screen opens (a
    /// grades page inside its 30-minute TTL is served from disk with no request) and `true` on
    /// pull-to-refresh.
    func load(for student: Student, forceRefresh: Bool = false) async {
        let generation = UUID()
        loadGeneration = generation

        if activeStudentID != student.studentId {
            activeStudentID = student.studentId
            report = nil
            freshness = nil
            errorMessage = nil
            selectedColumnID = nil
        }

        // Cache-first: paint the stored copy, then refresh regardless of its age.
        if report == nil, let cached = await repository.cachedReport(.academic) {
            guard loadGeneration == generation else { return }
            apply(cached)
        }

        if hasContent {
            isRefreshing = true
        } else {
            isLoading = true
        }

        defer {
            if loadGeneration == generation {
                isLoading = false
                isRefreshing = false
            }
        }

        do {
            let loaded = try await repository.loadReport(.academic, forceRefresh: forceRefresh)
            try Task.checkCancellation()
            guard loadGeneration == generation else { return }
            apply(loaded)
            errorMessage = nil
        } catch let error as W4Error {
            error.notifyIfSessionExpired()
            guard loadGeneration == generation else { return }
            // Never wipe what is already on screen: a failed refresh over a warm cache is a notice,
            // not an error screen.
            if !hasContent { errorMessage = error.errorDescription }
        } catch {
            guard loadGeneration == generation else { return }
            guard !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
            if !hasContent { errorMessage = error.localizedDescription }
        }
    }

    /// Pull-to-refresh: the same path, with the cache TTL bypassed.
    func refresh(for student: Student) async {
        await load(for: student, forceRefresh: true)
    }

    // MARK: - Reading the report

    var hasContent: Bool { !(report?.rows.isEmpty ?? true) }

    /// W4's columns, in W4's order.
    var columns: [W4GradeColumn] { report?.columns ?? [] }

    /// Rows that have at least one grade in them. A subject W4 lists with an en dash in every
    /// column is a subject with no grades yet, and it does not belong in a grades table.
    var gradedRows: [W4GradeRow] {
        (report?.rows ?? []).filter { !$0.cells.isEmpty }
    }

    /// The rows the table shows for the current column selection.
    var visibleRows: [W4GradeRow] {
        guard let selectedColumnID else { return gradedRows }
        return gradedRows.filter { $0.cell(for: selectedColumnID) != nil }
    }

    var selectedColumn: W4GradeColumn? {
        guard let selectedColumnID else { return nil }
        return report?.column(withID: selectedColumnID)
    }

    /// "All" or the selected column's own header text.
    var selectionLabel: String { selectedColumn?.label ?? "All" }

    /// `div.errorMessage` / `div.warning` / `div.note`, verbatim, in document order.
    var alerts: [String] { report?.alerts ?? [] }

    /// W4's empty-state sentence, when the table had no rows at all.
    var emptyMessage: String? {
        guard let report, report.rows.isEmpty else { return nil }
        return report.emptyMessage ?? "No grades found."
    }

    /// Mean IB grade for one column, one decimal, English formatting. `nil` when that column holds
    /// no 1–7 grades — a predicted column of free text has no average, and faking one would be a lie
    /// on the only number a student reads closely.
    func average(forColumnID id: String) -> String? {
        guard let average = report?.average(forColumnID: id) else { return nil }
        return String(format: "%.1f", average)
    }

    /// Every column that actually has an IB average, in W4's order.
    var columnAverages: [GradeColumnAverage] {
        columns.compactMap { column in
            average(forColumnID: column.id).map { GradeColumnAverage(column: column, value: $0) }
        }
    }

    /// The column a one-number summary should lead with (`final` → `awarded` → `predicted` →
    /// `term-2` → `term-1`, then W4's first column).
    var defaultColumn: W4GradeColumn? {
        guard let id = report?.defaultColumnID else { return nil }
        return report?.column(withID: id)
    }

    var freshnessLabel: String? {
        guard let freshness else { return nil }
        switch freshness {
        case .fresh:
            return nil
        case .demo:
            return "Demo data"
        case .cached(let fetchedAt, _):
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = Locale(identifier: "en_GB")
            formatter.unitsStyle = .full
            return "Updated \(formatter.localizedString(for: fetchedAt, relativeTo: now()))"
        }
    }

    var isShowingCachedCopy: Bool {
        if case .cached(_, let isStale) = freshness { return isStale }
        return false
    }

    // MARK: - Internals

    private func apply(_ loaded: W4Loaded<W4GradesReport>) {
        report = loaded.value
        freshness = loaded.freshness
        // A column that vanished from W4's header must not stay selected, or the table would filter
        // on a key nothing carries and show an empty screen full of grades.
        if let selectedColumnID, !loaded.value.columns.contains(where: { $0.id == selectedColumnID }) {
            self.selectedColumnID = nil
        }
    }
}
