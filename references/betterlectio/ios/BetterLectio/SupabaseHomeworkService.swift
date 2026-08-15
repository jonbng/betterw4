//
//  SupabaseHomeworkService.swift
//  BetterLectio
//

import Foundation
import Supabase

struct HomeworkSyncStatus: Equatable {
    let entryId: String
    let homeworkId: String?
    let schoolId: Int?
    let studentId: String?
    let isDone: Bool
    let clientUpdatedAt: Date
    let lastModifiedBy: String?
    let doneUpdatedAt: Date?
    let updatedAt: Date?
    let lessonDate: Date?
}

final class SupabaseHomeworkService {
    private let manager: SupabaseManager

    init(manager: SupabaseManager = .shared) {
        self.manager = manager
    }

    func fetchStatuses(schoolId: Int, studentId: String) async -> [String: HomeworkSyncStatus] {
        guard let client = manager.client else {
            print("🟡 [homework] fetchStatuses skipped: Supabase client unavailable")
            return [:]
        }

        await Self.logAuthState(client: client, context: "fetchStatuses")
        print("🔎 [homework] fetchStatuses start school=\(schoolId) student=\(studentId)")

        do {
            let rows: [HomeworkStatusRow] = try await client.rpc(
                "get_student_homework_statuses",
                params: GetStatusesParams(p_school_id: schoolId, p_student_id: studentId)
            )
            .execute()
            .value

            var result: [String: HomeworkSyncStatus] = [:]
            for row in rows {
                guard let status = row.asStatus else { continue }
                result[status.entryId] = status
            }
            print("✅ [homework] fetchStatuses returned \(result.count) statuses (raw rows=\(rows.count))")
            return result
        } catch {
            Self.logSupabaseError(context: "fetchStatuses school=\(schoolId) student=\(studentId)", error: error)
            return [:]
        }
    }

    func upsertStatus(
        student: Student,
        entry: HomeworkEntry,
        isDone: Bool,
        clientUpdatedAt: Date
    ) async -> Bool {
        guard let client = manager.client else {
            print("🟡 [homework] upsertStatus skipped: Supabase client unavailable")
            return false
        }

        await Self.logAuthState(client: client, context: "upsertStatus entry=\(entry.id)")
        print("🔎 [homework] upsertStatus start entry=\(entry.id) student=\(student.studentId) school=\(student.gymId) isDone=\(isDone)")

        let params = UpsertStatusParams(
            p_school_id: student.gymId,
            p_student_id: student.studentId,
            p_entry_id: entry.id,
            p_is_done: isDone,
            p_client_updated_at: Self.timestampFormatter.string(from: clientUpdatedAt),
            p_last_modified_by: "ios",
            p_lesson_date: Self.dayFormatter.string(from: entry.date),
            p_display_date: entry.displayDate,
            p_hold: entry.hold,
            p_title: entry.title,
            p_teacher: entry.teacher,
            p_room: entry.room,
            p_note: entry.note,
            p_items_json: entry.items.map { item in
                HomeworkItemPayload(
                    id: item.id,
                    text: item.text,
                    file_url: nil,
                    activity_url: item.url,
                    note: nil
                )
            }
        )

        do {
            try await client.rpc(
                "upsert_student_homework_status",
                params: params
            )
            .execute()
        } catch {
            Self.logSupabaseError(
                context: "upsertStatus entry=\(entry.id) student=\(student.studentId) school=\(student.gymId)",
                error: error
            )
            return false
        }

        print("✅ [homework] upsertStatus done entry=\(entry.id)")
        return true
    }

    private static func logAuthState(client: SupabaseClient, context: String) async {
        do {
            let session = try await client.auth.session
            let expiresAt = Date(timeIntervalSince1970: session.expiresAt)
            let expired = expiresAt < Date()
            print("🔐 [homework] auth(\(context)) sessionPresent=true expired=\(expired)")
        } catch {
            print("🔐 [homework] auth(\(context)) NO SESSION: \(error.localizedDescription)")
        }
    }

    private static func logSupabaseError(context: String, error: Error) {
        if let postgrest = error as? PostgrestError {
            print("""
                ⚠️ [homework] PostgrestError in \(context)
                   code: \(postgrest.code ?? "<nil>")
                   message: \(postgrest.message)
                   hint: \(postgrest.hint ?? "<nil>")
                   detail: \(postgrest.detail ?? "<nil>")
                """)
        } else {
            print("⚠️ [homework] Error in \(context): \(type(of: error)) — \(error.localizedDescription)")
            print("   debugDescription: \(String(reflecting: error))")
        }
    }

    fileprivate static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

// MARK: - RPC parameter types

private nonisolated struct GetStatusesParams: Encodable, Sendable {
    let p_school_id: Int
    let p_student_id: String
}

private nonisolated struct UpsertStatusParams: Encodable, Sendable {
    let p_school_id: Int
    let p_student_id: String
    let p_entry_id: String
    let p_is_done: Bool
    let p_client_updated_at: String
    let p_last_modified_by: String
    let p_lesson_date: String
    let p_display_date: String
    let p_hold: String
    let p_title: String?
    let p_teacher: String?
    let p_room: String?
    let p_note: String?
    let p_items_json: [HomeworkItemPayload]

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(p_school_id, forKey: .p_school_id)
        try container.encode(p_student_id, forKey: .p_student_id)
        try container.encode(p_entry_id, forKey: .p_entry_id)
        try container.encode(p_is_done, forKey: .p_is_done)
        try container.encode(p_client_updated_at, forKey: .p_client_updated_at)
        try container.encode(p_last_modified_by, forKey: .p_last_modified_by)
        try container.encode(p_lesson_date, forKey: .p_lesson_date)
        try container.encode(p_display_date, forKey: .p_display_date)
        try container.encode(p_hold, forKey: .p_hold)
        try container.encode(p_title, forKey: .p_title)
        try container.encode(p_teacher, forKey: .p_teacher)
        try container.encode(p_room, forKey: .p_room)
        try container.encode(p_note, forKey: .p_note)
        try container.encode(p_items_json, forKey: .p_items_json)
    }

    private enum CodingKeys: String, CodingKey {
        case p_school_id, p_student_id, p_entry_id, p_is_done
        case p_client_updated_at, p_last_modified_by
        case p_lesson_date, p_display_date, p_hold
        case p_title, p_teacher, p_room, p_note, p_items_json
    }
}

private nonisolated struct HomeworkItemPayload: Encodable, Sendable {
    let id: String
    let text: String
    let file_url: String?
    let activity_url: String?
    let note: String?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(file_url, forKey: .file_url)
        try container.encode(activity_url, forKey: .activity_url)
        try container.encode(note, forKey: .note)
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, file_url, activity_url, note
    }
}

// MARK: - RPC return row

private nonisolated struct HomeworkStatusRow: Decodable {
    let entryId: String?
    let homeworkId: String?
    let schoolId: Int?
    let studentId: String?
    let isDone: Bool
    let clientUpdatedAt: String?
    let lastModifiedBy: String?
    let doneUpdatedAt: String?
    let updatedAt: String?
    let lessonDate: String?

    var asStatus: HomeworkSyncStatus? {
        guard let entryId = normalized(entryId),
              let clientUpdatedAt = Self.parseTimestamp(clientUpdatedAt) else {
            return nil
        }

        return HomeworkSyncStatus(
            entryId: entryId,
            homeworkId: normalized(homeworkId),
            schoolId: schoolId,
            studentId: normalized(studentId),
            isDone: isDone,
            clientUpdatedAt: clientUpdatedAt,
            lastModifiedBy: normalized(lastModifiedBy),
            doneUpdatedAt: Self.parseTimestamp(doneUpdatedAt),
            updatedAt: Self.parseTimestamp(updatedAt),
            lessonDate: Self.parseDay(lessonDate)
        )
    }

    private func normalized(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func parseTimestamp(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return ISO8601DateFormatter.withFractionalSeconds.date(from: value)
            ?? ISO8601DateFormatter().date(from: value)
    }

    private static func parseDay(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return SupabaseHomeworkService.dayFormatter.date(from: value)
    }

    private enum CodingKeys: String, CodingKey {
        case entryId = "entry_id"
        case homeworkId = "homework_id"
        case schoolId = "school_id"
        case studentId = "student_id"
        case isDone = "is_done"
        case clientUpdatedAt = "client_updated_at"
        case lastModifiedBy = "last_modified_by"
        case doneUpdatedAt = "done_updated_at"
        case updatedAt = "updated_at"
        case lessonDate = "lesson_date"
    }
}

extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
