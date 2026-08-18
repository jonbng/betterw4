//
//  AssessmentStore.swift
//  BetterW4
//
//  The structured mirror of `index.php?r=academics/deadlines` plus the one piece of state the
//  app owns that W4 does not: the **optimistic local overlay** (`features.md` §1.3, §2.1).
//
//  W4 owns done-state. Lectio's `donePrefs` (a local "is it done" store that was merged with the
//  server on every read) is deliberately NOT ported: the only local status here is a short-lived
//  overlay written the instant a student taps *Confirm done*, and it is dropped as soon as a
//  server status that is newer than the tap arrives. Nothing about "homework done" is ever synced
//  anywhere else.
//
//  Storage layout follows `ScheduleStore` exactly, including the three-step recovery ladder
//  (open → delete `.store`/`-shm`/`-wal` and reopen → in-memory). `Assessments.store` gets its own
//  file: two stores sharing `default.store` with different schemas is what produced
//  `no such table: ZLESSONRECORD` (`ScheduleStore.swift:96-99`).
//
//  Concurrency: `@MainActor`, because a `ModelContext` is not `Sendable` and must never cross an
//  actor boundary. `AssessmentRepository` is an actor and talks to this class only through
//  `AssessmentOverlayStoring`, whose parameters and results are all value types.
//

import Foundation
import SwiftData

// MARK: - The overlay, as a value

/// One optimistic local status write, waiting for the server to catch up.
///
/// `writtenAt` is the whole point: it is what lets us decide, on the next fetch, whether the
/// server's answer is newer than the student's tap.
struct AssessmentLocalStatus: Sendable, Hashable, Codable {
    /// `Assessment.id` — the kind-prefixed identity (`"class:42"`), not the raw W4 id.
    let assessmentId: String
    let status: AssessmentStatus
    let writtenAt: Date

    init(assessmentId: String, status: AssessmentStatus, writtenAt: Date) {
        self.assessmentId = assessmentId
        self.status = status
        self.writtenAt = writtenAt
    }
}

/// The rules that decide when an optimistic overlay stops being the truth.
///
/// Pure and free-standing so they can be unit-tested without SwiftData, and so the in-memory
/// test double and the on-disk store cannot drift apart.
enum AssessmentOverlayPolicy {

    /// Whether `overlay` should still be shown, given what the server said and when it said it.
    ///
    /// Three cases, in order:
    ///   1. no server observation at all (demo, or a page we have not fetched) → the overlay wins;
    ///   2. the server page is newer than the tap → **the server wins**, drop the overlay. This is
    ///      the "drop the local overlay as soon as a server status that is newer arrives" rule, and
    ///      it is also what surfaces a write W4 silently ignored;
    ///   3. the server already agrees → the overlay is redundant, drop it.
    ///
    /// A server observation with exactly the same timestamp as the tap keeps the overlay: the two
    /// are indistinguishable, and honouring the student's tap is the kinder tie-break.
    static func survives(
        _ overlay: AssessmentLocalStatus,
        serverStatus: AssessmentStatus,
        serverObservedAt: Date?
    ) -> Bool {
        guard let serverObservedAt else { return true }
        if serverObservedAt > overlay.writtenAt { return false }
        if serverStatus == overlay.status { return false }
        return true
    }

    /// Applies a surviving overlay to a freshly parsed item.
    /// Returns the item to show and whether the overlay is still worth keeping.
    static func merge(
        _ item: Assessment,
        overlay: AssessmentLocalStatus?,
        serverObservedAt: Date?
    ) -> (item: Assessment, overlaySurvives: Bool) {
        guard let overlay,
              survives(overlay, serverStatus: item.status, serverObservedAt: serverObservedAt) else {
            return (item, false)
        }
        var merged = item
        merged.status = overlay.status
        return (merged, true)
    }
}

// MARK: - Seam

/// What `AssessmentRepository` needs from persistence, and nothing more.
///
/// It exists so the repository can be unit-tested against an in-memory double without standing up
/// SwiftData — and so the repository never holds a `ModelContext`.
protocol AssessmentOverlayStoring: Sendable {

    /// Records server truth for `items` and returns them with any surviving overlay applied.
    ///
    /// `observedAt` is when W4 produced this page (`fetchedAt` for a cached page, "now" for a live
    /// fetch), *not* when we parsed it — an hour-old cached page must not beat a tap made ten
    /// minutes ago.
    ///
    /// `window` scopes deletion: records whose `dueDate` falls inside it and that are absent from
    /// `items` are removed, because this fetch is the complete truth for that month. Pass `nil` to
    /// delete nothing.
    func persist(
        _ items: [Assessment],
        uwcId: String,
        observedAt: Date?,
        pruning window: DateInterval?
    ) async -> [Assessment]

    /// Read-only counterpart of `persist`: applies overlays without writing server truth.
    func applyOverlays(to items: [Assessment], uwcId: String, observedAt: Date?) async -> [Assessment]

    /// Writes the optimistic overlay for one item, creating a record if this student has none yet.
    func setOverlay(
        _ status: AssessmentStatus,
        for item: Assessment,
        uwcId: String,
        at writtenAt: Date
    ) async

    /// Drops the overlay for one item — the revert half of a failed write.
    func removeOverlay(for assessmentId: String, uwcId: String) async

    /// Everything this student has stored, optionally narrowed to a due-date window,
    /// with overlays applied.
    func cachedItems(uwcId: String, in window: DateInterval?) async -> [Assessment]

    /// Drops one student's records, or every record when `uwcId` is nil.
    func clear(uwcId: String?) async
}

// MARK: - Record

/// One assessment as last seen, plus the local overlay. Replaces `HomeworkRecord`.
///
/// Enums are stored as their raw strings: SwiftData is happier with primitives, and an unknown
/// value read back from disk degrades to a sane default instead of failing to decode.
@Model
final class AssessmentRecord {
    /// `"\(uwcId)|\(assessmentId)"` — the two id spaces are per-student and per-kind.
    @Attribute(.unique) var uniqueKey: String
    var uwcId: String
    /// `Assessment.id`, kind-prefixed (`"class:42"`).
    var assessmentId: String
    /// The bare W4 id that goes on the wire (`"42"`).
    var rawId: String
    var kind: String
    var rawKind: String
    var title: String
    var subject: String?
    var classCode: String?
    var teacher: String?
    var unit: String?
    var dueDate: Date?
    var daysLeft: Int?
    /// What W4 last told us. Never written by a local tap.
    var serverStatus: String
    var rawStatus: String
    var isOverdue: Bool
    var isEditable: Bool
    var href: String?
    /// The optimistic overlay; nil when there is none.
    var localStatus: String?
    /// When the overlay was written. `.distantPast` when there is no overlay.
    var localStatusUpdatedAt: Date
    /// When W4 produced the page this row came from.
    var sourceUpdatedAt: Date
    /// When this row last changed for any reason.
    var updatedAt: Date

    init(
        uniqueKey: String,
        uwcId: String,
        assessmentId: String,
        rawId: String,
        kind: String,
        rawKind: String,
        title: String,
        subject: String? = nil,
        classCode: String? = nil,
        teacher: String? = nil,
        unit: String? = nil,
        dueDate: Date? = nil,
        daysLeft: Int? = nil,
        serverStatus: String,
        rawStatus: String,
        isOverdue: Bool,
        isEditable: Bool,
        href: String? = nil,
        localStatus: String? = nil,
        localStatusUpdatedAt: Date = .distantPast,
        sourceUpdatedAt: Date,
        updatedAt: Date
    ) {
        self.uniqueKey = uniqueKey
        self.uwcId = uwcId
        self.assessmentId = assessmentId
        self.rawId = rawId
        self.kind = kind
        self.rawKind = rawKind
        self.title = title
        self.subject = subject
        self.classCode = classCode
        self.teacher = teacher
        self.unit = unit
        self.dueDate = dueDate
        self.daysLeft = daysLeft
        self.serverStatus = serverStatus
        self.rawStatus = rawStatus
        self.isOverdue = isOverdue
        self.isEditable = isEditable
        self.href = href
        self.localStatus = localStatus
        self.localStatusUpdatedAt = localStatusUpdatedAt
        self.sourceUpdatedAt = sourceUpdatedAt
        self.updatedAt = updatedAt
    }
}

// Kept outside the `@Model` body so the macro never sees them.
extension AssessmentRecord {

    static func uniqueKey(uwcId: String, assessmentId: String) -> String {
        "\(uwcId)|\(assessmentId)"
    }

    /// The overlay as a value, or nil when there is none / the stored string is unreadable.
    var overlay: AssessmentLocalStatus? {
        guard let raw = localStatus, let status = AssessmentStatus(rawValue: raw) else { return nil }
        return AssessmentLocalStatus(assessmentId: assessmentId, status: status, writtenAt: localStatusUpdatedAt)
    }

    /// Server truth as the UI's value type. The overlay is applied by the caller, not here.
    var serverAssessment: Assessment {
        Assessment(
            id: assessmentId,
            rawId: rawId,
            kind: AssessmentKind(rawValue: kind) ?? AssessmentKind.from(rawKind),
            rawKind: rawKind,
            title: title,
            subject: subject,
            classCode: classCode,
            teacher: teacher,
            unit: unit,
            dueDate: dueDate,
            daysLeft: daysLeft,
            status: AssessmentStatus(rawValue: serverStatus) ?? .pending,
            rawStatus: rawStatus,
            isOverdue: isOverdue,
            isEditable: isEditable,
            href: href
        )
    }

    func applyServerTruth(_ item: Assessment, uwcId: String, observedAt: Date?, now: Date) {
        uniqueKey = AssessmentRecord.uniqueKey(uwcId: uwcId, assessmentId: item.id)
        self.uwcId = uwcId
        assessmentId = item.id
        rawId = item.rawId
        kind = item.kind.rawValue
        rawKind = item.rawKind
        title = item.title
        subject = item.subject
        classCode = item.classCode
        teacher = item.teacher
        unit = item.unit
        dueDate = item.dueDate
        daysLeft = item.daysLeft
        serverStatus = item.status.rawValue
        rawStatus = item.rawStatus
        isOverdue = item.isOverdue
        isEditable = item.isEditable
        href = item.href
        if let observedAt { sourceUpdatedAt = observedAt }
        updatedAt = now
    }

    func clearOverlay() {
        localStatus = nil
        localStatusUpdatedAt = .distantPast
    }

    static func make(from item: Assessment, uwcId: String, observedAt: Date?, now: Date) -> AssessmentRecord {
        AssessmentRecord(
            uniqueKey: AssessmentRecord.uniqueKey(uwcId: uwcId, assessmentId: item.id),
            uwcId: uwcId,
            assessmentId: item.id,
            rawId: item.rawId,
            kind: item.kind.rawValue,
            rawKind: item.rawKind,
            title: item.title,
            subject: item.subject,
            classCode: item.classCode,
            teacher: item.teacher,
            unit: item.unit,
            dueDate: item.dueDate,
            daysLeft: item.daysLeft,
            serverStatus: item.status.rawValue,
            rawStatus: item.rawStatus,
            isOverdue: item.isOverdue,
            isEditable: item.isEditable,
            href: item.href,
            localStatus: nil,
            localStatusUpdatedAt: .distantPast,
            sourceUpdatedAt: observedAt ?? now,
            updatedAt: now
        )
    }
}

// MARK: - Store

/// SwiftData-backed assessment mirror. `Assessments.store`, one file of its own.
@MainActor
final class AssessmentStore: AssessmentOverlayStoring {

    static let shared = AssessmentStore()

    private let container: ModelContainer
    private let context: ModelContext

    init(inMemory: Bool = false) {
        let storeDirectory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let storeURL = storeDirectory.appendingPathComponent("Assessments.store")
        let config = inMemory
            ? ModelConfiguration(isStoredInMemoryOnly: true)
            : ModelConfiguration(url: storeURL)

        do {
            container = try ModelContainer(for: AssessmentRecord.self, configurations: config)
            context = ModelContext(container)
            context.autosaveEnabled = true
        } catch {
            print("⚠️ Failed to initialize AssessmentStore, rebuilding cache: \(error)")
            AssessmentStore.removeSQLiteStore(at: storeURL)
            do {
                container = try ModelContainer(for: AssessmentRecord.self, configurations: config)
                context = ModelContext(container)
                context.autosaveEnabled = true
            } catch {
                print("⚠️ AssessmentStore recovery failed; using memory-only cache: \(error)")
                do {
                    let memoryConfig = ModelConfiguration(isStoredInMemoryOnly: true)
                    container = try ModelContainer(for: AssessmentRecord.self, configurations: memoryConfig)
                    context = ModelContext(container)
                    context.autosaveEnabled = true
                } catch {
                    fatalError("Failed to initialize even an in-memory AssessmentStore: \(error)")
                }
            }
        }
    }

    private static func removeSQLiteStore(at url: URL) {
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    // MARK: Reading

    func cachedItems(uwcId: String, in window: DateInterval? = nil) async -> [Assessment] {
        records(uwcId: uwcId).compactMap { record -> Assessment? in
            if let window, !AssessmentStore.contains(window, record.dueDate) { return nil }
            let merged = AssessmentOverlayPolicy.merge(
                record.serverAssessment,
                overlay: record.overlay,
                serverObservedAt: record.sourceUpdatedAt
            )
            return merged.item
        }
    }

    func applyOverlays(to items: [Assessment], uwcId: String, observedAt: Date?) async -> [Assessment] {
        let overlays = overlayMap(uwcId: uwcId)
        guard !overlays.isEmpty else { return items }
        return items.map { item in
            AssessmentOverlayPolicy.merge(
                item,
                overlay: overlays[item.id],
                serverObservedAt: observedAt
            ).item
        }
    }

    // MARK: Writing

    func persist(
        _ items: [Assessment],
        uwcId: String,
        observedAt: Date?,
        pruning window: DateInterval?
    ) async -> [Assessment] {
        let now = TimeProvider.now
        var existing: [String: AssessmentRecord] = [:]
        for record in records(uwcId: uwcId) where existing[record.assessmentId] == nil {
            existing[record.assessmentId] = record
        }

        var result: [Assessment] = []
        result.reserveCapacity(items.count)

        for item in items {
            let record: AssessmentRecord
            if let found = existing[item.id] {
                record = found
            } else {
                record = AssessmentRecord.make(from: item, uwcId: uwcId, observedAt: observedAt, now: now)
                context.insert(record)
            }
            record.applyServerTruth(item, uwcId: uwcId, observedAt: observedAt, now: now)

            let merged = AssessmentOverlayPolicy.merge(
                item,
                overlay: record.overlay,
                serverObservedAt: observedAt
            )
            if !merged.overlaySurvives { record.clearOverlay() }
            result.append(merged.item)
        }

        if let window {
            let keep = Set(items.map(\.id))
            for (assessmentId, record) in existing {
                guard !keep.contains(assessmentId),
                      AssessmentStore.contains(window, record.dueDate) else { continue }
                context.delete(record)
            }
        }

        save()
        return result
    }

    func setOverlay(
        _ status: AssessmentStatus,
        for item: Assessment,
        uwcId: String,
        at writtenAt: Date
    ) async {
        let record: AssessmentRecord
        if let found = existingRecord(uwcId: uwcId, assessmentId: item.id) {
            record = found
        } else {
            let created = AssessmentRecord.make(from: item, uwcId: uwcId, observedAt: nil, now: writtenAt)
            context.insert(created)
            record = created
        }
        record.localStatus = status.rawValue
        record.localStatusUpdatedAt = writtenAt
        record.updatedAt = writtenAt
        save()
    }

    func removeOverlay(for assessmentId: String, uwcId: String) async {
        guard let record = existingRecord(uwcId: uwcId, assessmentId: assessmentId) else { return }
        record.clearOverlay()
        record.updatedAt = TimeProvider.now
        save()
    }

    func clear(uwcId: String?) async {
        do {
            if let uwcId {
                for record in records(uwcId: uwcId) { context.delete(record) }
            } else {
                try context.delete(model: AssessmentRecord.self)
            }
            try context.save()
        } catch {
            print("❌ Failed clearing assessments: \(error)")
        }
    }

    // MARK: Internals

    /// Unsorted on purpose: ordering is a presentation decision and `AssessmentRepository` owns it.
    private func records(uwcId: String) -> [AssessmentRecord] {
        do {
            let descriptor = FetchDescriptor<AssessmentRecord>(
                predicate: #Predicate { $0.uwcId == uwcId }
            )
            return try context.fetch(descriptor)
        } catch {
            print("❌ Failed to load assessments for \(uwcId): \(error)")
            return []
        }
    }

    private func existingRecord(uwcId: String, assessmentId: String) -> AssessmentRecord? {
        let key = AssessmentRecord.uniqueKey(uwcId: uwcId, assessmentId: assessmentId)
        do {
            var descriptor = FetchDescriptor<AssessmentRecord>(
                predicate: #Predicate { $0.uniqueKey == key }
            )
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first
        } catch {
            print("❌ Failed to load assessment \(assessmentId): \(error)")
            return nil
        }
    }

    private func overlayMap(uwcId: String) -> [String: AssessmentLocalStatus] {
        var map: [String: AssessmentLocalStatus] = [:]
        for record in records(uwcId: uwcId) {
            if let overlay = record.overlay { map[record.assessmentId] = overlay }
        }
        return map
    }

    private func save() {
        do {
            try context.save()
        } catch {
            // A failed mirror write must never break a fetch that already succeeded.
            print("❌ Failed to save AssessmentStore: \(error)")
        }
    }

    /// Half-open containment: an item due at 00:00 on the 1st of the next month belongs to that
    /// month, not to this one. `DateInterval.contains` is closed at both ends, which would make
    /// two adjacent months both claim (and both prune) that item.
    private nonisolated static func contains(_ window: DateInterval, _ date: Date?) -> Bool {
        guard let date else { return false }
        return date >= window.start && date < window.end
    }
}

// MARK: - Shared-instance adapter

/// Forwards to `AssessmentStore.shared`.
///
/// `AssessmentStore` is `@MainActor`, so reaching its singleton needs an `await` — which a
/// synchronous `init` cannot do. This adapter is what lets `AssessmentRepository` take a plain
/// default in its initialiser and still hop to the main actor for every call.
struct SharedAssessmentOverlayStore: AssessmentOverlayStoring {

    init() {}

    func persist(
        _ items: [Assessment],
        uwcId: String,
        observedAt: Date?,
        pruning window: DateInterval?
    ) async -> [Assessment] {
        await AssessmentStore.shared.persist(items, uwcId: uwcId, observedAt: observedAt, pruning: window)
    }

    func applyOverlays(to items: [Assessment], uwcId: String, observedAt: Date?) async -> [Assessment] {
        await AssessmentStore.shared.applyOverlays(to: items, uwcId: uwcId, observedAt: observedAt)
    }

    func setOverlay(
        _ status: AssessmentStatus,
        for item: Assessment,
        uwcId: String,
        at writtenAt: Date
    ) async {
        await AssessmentStore.shared.setOverlay(status, for: item, uwcId: uwcId, at: writtenAt)
    }

    func removeOverlay(for assessmentId: String, uwcId: String) async {
        await AssessmentStore.shared.removeOverlay(for: assessmentId, uwcId: uwcId)
    }

    func cachedItems(uwcId: String, in window: DateInterval?) async -> [Assessment] {
        await AssessmentStore.shared.cachedItems(uwcId: uwcId, in: window)
    }

    func clear(uwcId: String?) async {
        await AssessmentStore.shared.clear(uwcId: uwcId)
    }
}
