//
//  HomeworkViewModel.swift
//  BetterLectio
//

import Foundation
import Combine
import SwiftUI

private struct PendingHomeworkWrite {
    let isDone: Bool
    let clientUpdatedAt: Date
}

@MainActor
class HomeworkViewModel: ObservableObject {
    @Published var entries: [HomeworkEntry] = [] {
        didSet { rebuildEntryIndexes() }
    }
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lessonContent: [String: LessonContent] = [:] // keyed by entry id
    @Published var doneMap: [String: Bool] = [:]

    private let httpClient = LectioHTTPClient()
    private let keychainManager = KeychainManager.shared
    private let store = ScheduleStore.shared
    private let homeworkStore = HomeworkStore.shared
    private let supabaseHomeworkService = SupabaseHomeworkService()

    private var contentFetchingIds: Set<String> = []
    private var remoteStatusByEntryId: [String: HomeworkSyncStatus] = [:]
    private var pendingWritesByEntryId: [String: PendingHomeworkWrite] = [:]
    private var groupedEntries: [(date: Date, displayDate: String, entries: [HomeworkEntry])] = []
    private var cachedTodayEntries: [HomeworkEntry] = []
    private var cachedTotalItemCount = 0
    private var loadGeneration: UUID?
    private var activeStudentID: String?

    func loadHomework(for student: Student) async {
        let generation = UUID()
        loadGeneration = generation
        if activeStudentID != student.studentId {
            entries = []
            doneMap = [:]
            lessonContent = [:]
            remoteStatusByEntryId = [:]
            pendingWritesByEntryId = [:]
        }
        activeStudentID = student.studentId
        isLoading = true
        errorMessage = nil
        defer {
            if loadGeneration == generation {
                isLoading = false
            }
        }

        if student.isDemo {
            entries = DemoDataProvider.homeworkEntries()
            // Keep doneMap entirely in-memory — no SwiftData writes.
            doneMap = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, false) })
            return
        }

        let cachedEntries = await homeworkStore.loadEntriesAsync(for: student.studentId)
        guard loadGeneration == generation, !Task.isCancelled else { return }
        entries = cachedEntries
        await recalculateDoneMap(for: student.studentId)

        let remoteStatusesTask = Task {
            await supabaseHomeworkService.fetchStatuses(
                schoolId: student.gymId,
                studentId: student.studentId
            )
        }
        defer { remoteStatusesTask.cancel() }

        do {
            guard let credentials = keychainManager.loadCredentials(for: student.studentId) else {
                errorMessage = "Ingen loginoplysninger fundet"
                let remoteStatuses = await remoteStatusesTask.value
                guard loadGeneration == generation, !Task.isCancelled else { return }
                await applyRemoteStatuses(remoteStatuses, for: student.studentId)
                return
            }

            let html = try await httpClient.fetchHomeworkOverview(
                credentials: credentials,
                studentId: student.studentId,
                schoolId: student.gymId
            )

            let freshEntries = try await Task.detached(priority: .userInitiated) {
                try ScheduleParser.parseHomeworkOverview(from: html)
            }.value
            try Task.checkCancellation()
            try await homeworkStore.replaceEntriesAsync(studentId: student.studentId, entries: freshEntries)
            try Task.checkCancellation()
            guard loadGeneration == generation else { return }

            entries = freshEntries
            await recalculateDoneMap(for: student.studentId)
        } catch let error as LectioError {
            if loadGeneration == generation {
                error.notifyIfSessionExpired()
                errorMessage = error.errorDescription
                ReviewPromptCoordinator.shared.reportRecentError()
            }
        } catch {
            if loadGeneration == generation,
               !(error is CancellationError), (error as? URLError)?.code != .cancelled {
                errorMessage = error.localizedDescription
                ReviewPromptCoordinator.shared.reportRecentError()
            }
        }

        let remoteStatuses = await remoteStatusesTask.value
        guard loadGeneration == generation, !Task.isCancelled else { return }
        await applyRemoteStatuses(remoteStatuses, for: student.studentId)
    }

    func isDone(_ entryId: String) -> Bool {
        doneMap[entryId] ?? false
    }

    func toggleDone(entryId: String, student: Student) {
        let wasDone = isDone(entryId)
        let newValue = !wasDone
        let clientUpdatedAt = Date()

        if student.isDemo {
            doneMap[entryId] = newValue
            return
        }

        if let entry = entries.first(where: { $0.id == entryId }), isSyncable(entryId: entry.id) {
            pendingWritesByEntryId[entryId] = PendingHomeworkWrite(
                isDone: newValue,
                clientUpdatedAt: clientUpdatedAt
            )
        }

        doneMap[entryId] = newValue

        if !wasDone {
            ReviewPromptCoordinator.shared.maybePrompt(.homeworkDone)
        }

        guard let entry = entries.first(where: { $0.id == entryId }) else { return }

        Task {
            await homeworkStore.setDoneAsync(
                studentId: student.studentId,
                entryId: entryId,
                isDone: newValue,
                updatedAt: clientUpdatedAt
            )
            guard isSyncable(entryId: entry.id) else { return }
            let didWrite = await supabaseHomeworkService.upsertStatus(
                student: student,
                entry: entry,
                isDone: newValue,
                clientUpdatedAt: clientUpdatedAt
            )

            let refreshedStatuses = await supabaseHomeworkService.fetchStatuses(
                schoolId: student.gymId,
                studentId: student.studentId
            )

            if !didWrite,
               pendingWritesByEntryId[entryId]?.clientUpdatedAt == clientUpdatedAt {
                pendingWritesByEntryId.removeValue(forKey: entryId)
            }
            await applyRemoteStatuses(refreshedStatuses, for: student.studentId)
        }
    }

    /// Entries grouped by date for display
    var entriesByDate: [(date: Date, displayDate: String, entries: [HomeworkEntry])] {
        groupedEntries
    }

    /// Today's homework
    var todayEntries: [HomeworkEntry] {
        cachedTodayEntries
    }

    /// Total number of homework items across all entries
    var totalItemCount: Int {
        cachedTotalItemCount
    }

    private func rebuildEntryIndexes() {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
        groupedEntries = grouped
            .sorted { $0.key < $1.key }
            .map { (date: $0.key, displayDate: $0.value.first?.displayDate ?? "", entries: $0.value) }
        let today = calendar.startOfDay(for: Date())
        cachedTodayEntries = grouped[today] ?? []
        cachedTotalItemCount = entries.reduce(0) { $0 + $1.items.count }
    }

    // MARK: - Homework Lesson Content

    /// Returns cached content (in-memory or local store) without any network request.
    func cachedContent(for entry: HomeworkEntry, student: Student) async -> LessonContent? {
        if let cached = lessonContent[entry.id] {
            return cached
        }
        if let stored = await store.loadContentAsync(for: entry.id, studentId: student.studentId) {
            guard !Task.isCancelled else { return nil }
            lessonContent[entry.id] = stored
            return stored
        }
        return nil
    }

    /// Fetches fresh content from Lectio. Updates in-memory cache, local store, and Supabase.
    @discardableResult
    func refreshContent(for entry: HomeworkEntry, student: Student) async -> LessonContent? {
        return await fetchAndStoreContent(for: entry, student: student)
    }

    /// Fetches lesson content from Lectio, parses it, stores locally, and syncs to Supabase.
    func fetchAndStoreContent(for entry: HomeworkEntry, student: Student) async -> LessonContent? {
        guard !contentFetchingIds.contains(entry.id) else { return nil }
        contentFetchingIds.insert(entry.id)
        defer { contentFetchingIds.remove(entry.id) }

        if student.isDemo {
            let content = LessonContent(
                teacherNote: "Demo-noter for \(entry.hold).",
                items: entry.items.map {
                    LessonContentItem(
                        id: "demo-item-\($0.id)",
                        title: nil,
                        note: nil,
                        blocks: [.paragraph(inlines: [.text($0.text)])],
                        links: [],
                        isHomework: true
                    )
                }
            )
            lessonContent[entry.id] = content
            return content
        }

        do {
            guard let credentials = keychainManager.loadCredentials(for: student.studentId) else {
                return nil
            }

            let html = try await httpClient.fetchLessonContent(
                credentials: credentials,
                studentId: student.studentId,
                schoolId: student.gymId,
                absId: entry.id
            )

            let content = try await Task.detached(priority: .userInitiated) {
                try ScheduleParser.parseLessonContent(from: html)
            }.value
            try Task.checkCancellation()
            await store.saveContentAsync(for: entry.id, studentId: student.studentId, content: content)
            try Task.checkCancellation()
            lessonContent[entry.id] = content
            return content
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return nil }
            print("❌ Failed to fetch lesson content for homework entry: \(error.localizedDescription)")
            return nil
        }
    }

    private func applyRemoteStatuses(_ remoteStatuses: [String: HomeworkSyncStatus], for studentId: String) async {
        guard activeStudentID == studentId else { return }
        remoteStatusByEntryId = remoteStatuses

        for (entryId, pending) in pendingWritesByEntryId {
            guard let remote = remoteStatuses[entryId] else { continue }
            if remote.clientUpdatedAt >= pending.clientUpdatedAt {
                pendingWritesByEntryId.removeValue(forKey: entryId)
            }
        }

        await homeworkStore.mergeRemoteDoneStatesAsync(studentId: studentId, remoteStates: remoteStatuses)
        guard activeStudentID == studentId, !Task.isCancelled else { return }
        await recalculateDoneMap(for: studentId)
    }

    private func recalculateDoneMap(for studentId: String) async {
        let entryIds = entries.map(\.id)
        let localStates = await homeworkStore.getDoneStatesAsync(studentId: studentId, entryIds: entryIds)
        guard !Task.isCancelled else { return }
        var newMap: [String: Bool] = [:]

        for entryId in entryIds {
            if let pending = pendingWritesByEntryId[entryId] {
                newMap[entryId] = pending.isDone
                continue
            }

            let remoteState = remoteStatusByEntryId[entryId]
            let localState = localStates[entryId]

            if let remoteState, let localState {
                newMap[entryId] = remoteState.clientUpdatedAt >= localState.updatedAt
                    ? remoteState.isDone
                    : localState.isDone
            } else if let remoteState {
                newMap[entryId] = remoteState.isDone
            } else if let localState {
                newMap[entryId] = localState.isDone
            } else {
                newMap[entryId] = false
            }
        }

        doneMap = newMap
    }

    private func isSyncable(entryId: String) -> Bool {
        !entryId.isEmpty && entryId.allSatisfy(\.isNumber)
    }
}
