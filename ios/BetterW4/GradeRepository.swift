//
//  GradeRepository.swift
//  BetterW4
//
//  `academics/grades/grades` and `academics/grades/grades/sat` — the IB grades table and the
//  SAT/ACT page beside it (features.md §1.6 and §0.2, W4_PORT_PLAN.md Wave 5 item 5.8).
//
//  This repository replaces the fetches `GradesViewModel` makes today against the Lectio stack;
//  Wave 6 rewires that view model. Nothing here reads `GradeModels.swift` — the legacy Lectio
//  `GradesReport` with its Danish 7-point scale and its `Vægt` column is a different type that
//  dies with its view model. What this returns is `W4GradesReport`: IB 1–7, dynamic columns keyed
//  by a slug of W4's own header text, and an effort grade instead of a weight (D-14).
//
//  The transport seam and the cache-first loader live in `DocumentRepository.swift`.
//

import Foundation

/// Which grades page. Two routes, one parser, one surface, two cache entries.
enum GradeReportKind: String, Codable, Sendable, CaseIterable {
    /// `academics/grades/grades` — the IB grades table.
    case academic
    /// `academics/grades/grades/sat` — SAT / ACT results.
    case satACT

    var route: String {
        switch self {
        case .academic: return W4Routes.R.grades
        case .satACT: return W4Routes.R.satACT
        }
    }

    /// Distinct keys, because the two pages share the `.grades` surface and would otherwise
    /// overwrite each other in the page cache.
    var cacheKey: String {
        switch self {
        case .academic: return "grades"
        case .satACT: return "grades-sat"
        }
    }

    var displayName: String {
        switch self {
        case .academic: return "Grades"
        case .satACT: return "SAT / ACT"
        }
    }
}

/// Reads a grades page, cache-first, and stamps the report with when W4 actually produced it.
actor GradeRepository {

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

    /// One grades page.
    ///
    /// `W4GradesReport.fetchedAt` is filled in here rather than by the parser — parsers are pure
    /// and must not read a clock — and it is filled in from the *cache* timestamp when the report
    /// came from disk, so "Updated 4 h ago" tells the truth after a relaunch.
    func loadReport(
        _ kind: GradeReportKind = .academic,
        forceRefresh: Bool = false,
        priority: FetchPriority = .important
    ) async throws -> W4Loaded<W4GradesReport> {
        let context = try resolveContext()
        if context.isDemo {
            return W4Loaded(Self.demoReport(kind), freshness: .demo)
        }

        let loaded = try await W4SecondaryPageLoader.loadHTML(
            surface: .grades,
            key: kind.cacheKey,
            route: kind.route,
            forceRefresh: forceRefresh,
            priority: priority,
            context: context,
            client: client,
            cache: cache
        )
        return Self.report(from: loaded)
    }

    /// The last report we stored, however old, with no request.
    func cachedReport(_ kind: GradeReportKind = .academic) async -> W4Loaded<W4GradesReport>? {
        guard let context = try? resolveContext() else { return nil }
        if context.isDemo {
            return W4Loaded(Self.demoReport(kind), freshness: .demo)
        }
        guard let cached = await W4SecondaryPageLoader.cachedHTML(
            surface: .grades,
            key: kind.cacheKey,
            context: context,
            cache: cache
        ) else { return nil }
        return Self.report(from: cached)
    }

    func invalidate(_ kind: GradeReportKind = .academic) async {
        guard let context = try? resolveContext(), !context.isDemo else { return }
        await cache.remove(surface: .grades, key: kind.cacheKey, uwcId: context.uwcId)
    }

    /// Drops both grades pages — the "Clear cache" and sign-out path for this surface.
    func invalidateAll() async {
        for kind in GradeReportKind.allCases {
            await invalidate(kind)
        }
    }

    // MARK: - Parsing

    /// Parses the loaded HTML and stamps the report with the moment W4 produced it.
    private static func report(from loaded: W4Loaded<String>) -> W4Loaded<W4GradesReport> {
        let fetchedAt = loaded.freshness.fetchedAt ?? TimeProvider.now
        return loaded.map { html in
            W4GradeParser.parse(html).withFetchedAt(fetchedAt)
        }
    }

    // MARK: - Demo (features.md §4)

    static func demoReport(_ kind: GradeReportKind) -> W4GradesReport {
        switch kind {
        case .academic: return demoAcademicReport()
        case .satACT: return demoSATReport()
        }
    }

    /// IB columns Predicted / Final over four subjects, exactly as features.md §4 specifies.
    ///
    /// "Predicted" is the anticipated column — on the real page that is a `th.anticipated` class
    /// rather than a label, which is why `isAnticipated` is set explicitly here instead of being
    /// inferred from the word.
    private static func demoAcademicReport() -> W4GradesReport {
        let columns = [
            W4GradeColumn(id: "predicted", label: "Predicted", isAnticipated: true),
            W4GradeColumn(id: "final", label: "Final", isAnticipated: false)
        ]

        func row(
            _ id: String,
            _ subject: String,
            _ level: String,
            _ teacher: String,
            predicted: String,
            final: String,
            effort: W4EffortGrade
        ) -> W4GradeRow {
            W4GradeRow(
                id: id,
                subject: subject,
                level: level,
                teacher: teacher,
                cells: [
                    "predicted": W4GradeCell(value: predicted),
                    "final": W4GradeCell(value: final, effort: effort)
                ]
            )
        }

        return W4GradesReport(
            title: "My Grades",
            columns: columns,
            rows: [
                row("demo-mathematics-hl", "Mathematics", "HL", "A. Newton",
                    predicted: "6", final: "7", effort: .meets),
                row("demo-english-a-hl", "English A", "HL", "B. Woolf",
                    predicted: "6", final: "6", effort: .meets),
                row("demo-biology-sl", "Biology", "SL", "C. Darwin",
                    predicted: "5", final: "5", effort: .almostMeets),
                row("demo-history-hl", "History", "HL", "D. Tuchman",
                    predicted: "4", final: "5", effort: .meets)
            ],
            alerts: ["Demo data. Not connected to W4."],
            emptyMessage: nil,
            fetchedAt: TimeProvider.now
        )
    }

    /// The SAT/ACT page has never been captured, so demo shows the honest empty state rather than
    /// invented scores — a reviewer seeing a fabricated SAT table would be seeing a table this app
    /// has never proven it can render.
    private static func demoSATReport() -> W4GradesReport {
        W4GradesReport(
            title: "SAT / ACT",
            columns: [],
            rows: [],
            alerts: ["Demo data. Not connected to W4."],
            emptyMessage: "No SAT or ACT results recorded.",
            fetchedAt: TimeProvider.now
        )
    }
}
