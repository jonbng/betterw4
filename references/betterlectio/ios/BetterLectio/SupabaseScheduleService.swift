//
//  SupabaseScheduleService.swift
//  BetterLectio
//

import Foundation
import Supabase

final class SupabaseScheduleService {
    private let manager: SupabaseManager

    init(manager: SupabaseManager = .shared) {
        self.manager = manager
    }

    func syncWeek(studentId: String, weekKey: String, events: [ScheduleEvent]) async {
        guard let client = manager.client else {
            print("ℹ️ Supabase not configured, skipping remote sync.")
            return
        }

        do {
            let payload = events.map {
                SupabaseLessonRecord(
                    lesson_key: ScheduleIdentity.lessonKey(for: $0, studentId: studentId),
                    week_key: weekKey,
                    lesson_date: Self.dayFormatter.string(from: $0.date),
                    start_time: $0.startTime,
                    end_time: $0.endTime,
                    title: $0.title,
                    teacher: $0.teacher,
                    room: $0.room,
                    status: $0.status.rawValue,
                    notes: $0.notes,
                    homework: $0.homework,
                    source_updated_at: Self.timestampFormatter.string(from: Date()),
                    updated_at: Self.timestampFormatter.string(from: Date())
                )
            }

            try await upsertLessons(client: client, lessons: payload)
            try await linkStudentToLessons(
                client: client,
                studentId: studentId,
                lessonKeys: payload.map(\.lesson_key)
            )

            let fetchedKeys = Set(payload.map(\.lesson_key))
            try await markMissingLessonsAsCancelled(
                client: client,
                studentId: studentId,
                weekKey: weekKey,
                fetchedLessonKeys: fetchedKeys
            )
            try await upsertWeekSync(client: client, studentId: studentId, weekKey: weekKey)

            print("✅ Synced week \(weekKey) to Supabase (\(events.count) events)")
        } catch {
            print("⚠️ Supabase sync failed for week \(weekKey): \(error.localizedDescription)")
        }
    }

    private func upsertLessons(client: SupabaseClient, lessons: [SupabaseLessonRecord]) async throws {
        try await client
            .from("lessons")
            .upsert(lessons, onConflict: "lesson_key", returning: .minimal)
            .execute()
    }

    private func linkStudentToLessons(
        client: SupabaseClient,
        studentId: String,
        lessonKeys: [String]
    ) async throws {
        guard !lessonKeys.isEmpty else { return }

        let fetched: [SupabaseLessonIdRow] = try await client
            .from("lessons")
            .select("id,lesson_key")
            .in("lesson_key", values: lessonKeys)
            .execute()
            .value

        guard !fetched.isEmpty else { return }

        let junctionRecords = fetched.map {
            StudentLessonRecord(student_id: studentId, lesson_id: $0.id)
        }

        try await client
            .from("student_lessons")
            .upsert(junctionRecords, returning: .minimal)
            .execute()
    }

    private func markMissingLessonsAsCancelled(
        client: SupabaseClient,
        studentId: String,
        weekKey: String,
        fetchedLessonKeys: Set<String>
    ) async throws {
        let keyRows = try await fetchRemoteLessonKeys(
            client: client,
            studentId: studentId,
            weekKey: weekKey
        )
        let remoteKeys = Set(keyRows.map(\.lesson_key))
        let missingKeys = remoteKeys.subtracting(fetchedLessonKeys)
        guard !missingKeys.isEmpty else { return }

        for key in missingKeys {
            let patch = LessonStatusPatch(
                status: EventStatus.cancelled.rawValue,
                updated_at: Self.timestampFormatter.string(from: Date())
            )

            try await client
                .from("lessons")
                .update(patch, returning: .minimal)
                .eq("student_id", value: studentId)
                .eq("week_key", value: weekKey)
                .eq("lesson_key", value: key)
                .execute()
        }
    }

    private func fetchRemoteLessonKeys(
        client: SupabaseClient,
        studentId: String,
        weekKey: String
    ) async throws -> [SupabaseLessonKeyRow] {
        let nestedRows: [SupabaseNestedLessonKeyRow] = try await client
            .from("student_lessons")
            .select("lessons(lesson_key)")
            .eq("student_id", value: studentId)
            .eq("lessons.week_key", value: weekKey)
            .execute()
            .value

        return nestedRows.compactMap(\.lessons)
    }

    /// Syncs lesson content (homework/other content) to the remote `lessons` table.
    func syncLessonContent(studentId: String, lessonKey: String, content: LessonContent) async {
        guard let client = manager.client else { return }

        do {
            let payload = LessonContentPatch(
                content: content,
                updated_at: Self.timestampFormatter.string(from: Date())
            )

            try await client
                .from("lessons")
                .update(payload, returning: .minimal)
                .eq("lesson_key", value: lessonKey)
                .execute()
        } catch {
            print("⚠️ Failed to sync lesson content: \(error.localizedDescription)")
        }
    }

    private func upsertWeekSync(client: SupabaseClient, studentId: String, weekKey: String) async throws {
        let record = SupabaseWeekSyncRecord(
            student_id: studentId,
            week_key: weekKey,
            last_synced_at: Self.timestampFormatter.string(from: Date())
        )

        try await client
            .from("week_sync")
            .upsert(record, onConflict: "student_id,week_key", returning: .minimal)
            .execute()
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private nonisolated struct SupabaseLessonRecord: Encodable, Sendable {
    let lesson_key: String
    let week_key: String
    let lesson_date: String
    let start_time: String
    let end_time: String
    let title: String
    let teacher: String?
    let room: String?
    let status: String
    let notes: String?
    let homework: String?
    let source_updated_at: String
    let updated_at: String

    /// Custom encoding ensures all keys are always present (with null for nil optionals).
    /// PostgREST requires consistent keys across array elements (PGRST102).
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lesson_key, forKey: .lesson_key)
        try container.encode(week_key, forKey: .week_key)
        try container.encode(lesson_date, forKey: .lesson_date)
        try container.encode(start_time, forKey: .start_time)
        try container.encode(end_time, forKey: .end_time)
        try container.encode(title, forKey: .title)
        try container.encode(teacher, forKey: .teacher)
        try container.encode(room, forKey: .room)
        try container.encode(status, forKey: .status)
        try container.encode(notes, forKey: .notes)
        try container.encode(homework, forKey: .homework)
        try container.encode(source_updated_at, forKey: .source_updated_at)
        try container.encode(updated_at, forKey: .updated_at)
    }

    private enum CodingKeys: String, CodingKey {
        case lesson_key, week_key, lesson_date
        case start_time, end_time, title, teacher, room
        case status, notes, homework, source_updated_at, updated_at
    }
}

private nonisolated struct LessonContentPatch: Encodable, Sendable {
    let content: LessonContent
    let updated_at: String
}

private nonisolated struct LessonStatusPatch: Encodable, Sendable {
    let status: String
    let updated_at: String
}

private nonisolated struct StudentLessonRecord: Encodable, Sendable {
    let student_id: String
    let lesson_id: String
}

private nonisolated struct SupabaseLessonKeyRow: Decodable {
    let lesson_key: String
}

private nonisolated struct SupabaseNestedLessonKeyRow: Decodable {
    let lessons: SupabaseLessonKeyRow?
}

private nonisolated struct SupabaseLessonIdRow: Decodable {
    let id: String
    let lesson_key: String
}

private nonisolated struct SupabaseWeekSyncRecord: Encodable, Sendable {
    let student_id: String
    let week_key: String
    let last_synced_at: String
}
