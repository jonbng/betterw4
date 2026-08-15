//
//  SupabaseSubjectService.swift
//  BetterLectio
//

import Foundation
import Supabase

final class SupabaseSubjectService {
    static let shared = SupabaseSubjectService()

    private let manager: SupabaseManager

    init(manager: SupabaseManager = .shared) {
        self.manager = manager
    }

    func fetchMappings(studentId: String, schoolId: String) async throws -> [SupabaseSubjectMapping] {
        guard let client = manager.client else { return [] }

        return try await client.rpc(
            "get_student_lesson_mappings_v2",
            params: FetchMappingsParams(p_school_id: schoolId, p_student_id: studentId)
        )
        .execute()
        .value
    }

    func upsertMappingOverride(
        studentId: String,
        schoolId: String,
        mappingId: UUID,
        displayName: String?,
        colorHue: Int?,
        icon: String?
    ) async throws {
        guard let client = manager.client else { return }

        let params = UpsertOverrideParams(
            p_school_id: schoolId,
            p_student_id: studentId,
            p_mapping_id: mappingId.uuidString.lowercased(),
            p_display_name: displayName,
            p_color_hue: colorHue,
            p_icon: icon,
            p_client_updated_at: Self.clientTimestamp(),
            p_last_modified_by: "ios"
        )

        try await client.rpc(
            "upsert_user_lesson_override_v2",
            params: params
        )
        .execute()
    }

    func resetMappingOverride(
        studentId: String,
        schoolId: String,
        mappingId: UUID
    ) async throws {
        guard let client = manager.client else { return }

        let params = ResetOverrideParams(
            p_school_id: schoolId,
            p_student_id: studentId,
            p_mapping_id: mappingId.uuidString.lowercased(),
            p_client_updated_at: Self.clientTimestamp(),
            p_last_modified_by: "ios"
        )

        try await client.rpc(
            "reset_user_lesson_override_v2",
            params: params
        )
        .execute()
    }

    private static func clientTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

private nonisolated struct FetchMappingsParams: Encodable, Sendable {
    let p_school_id: String
    let p_student_id: String
}

private nonisolated struct UpsertOverrideParams: Encodable, Sendable {
    let p_school_id: String
    let p_student_id: String
    let p_mapping_id: String
    let p_display_name: String?
    let p_color_hue: Int?
    let p_icon: String?
    let p_client_updated_at: String
    let p_last_modified_by: String

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(p_school_id, forKey: .p_school_id)
        try container.encode(p_student_id, forKey: .p_student_id)
        try container.encode(p_mapping_id, forKey: .p_mapping_id)
        try container.encode(p_display_name, forKey: .p_display_name)
        try container.encode(p_color_hue, forKey: .p_color_hue)
        try container.encode(p_icon, forKey: .p_icon)
        try container.encode(p_client_updated_at, forKey: .p_client_updated_at)
        try container.encode(p_last_modified_by, forKey: .p_last_modified_by)
    }

    private enum CodingKeys: String, CodingKey {
        case p_school_id, p_student_id, p_mapping_id
        case p_display_name, p_color_hue, p_icon
        case p_client_updated_at, p_last_modified_by
    }
}

private nonisolated struct ResetOverrideParams: Encodable, Sendable {
    let p_school_id: String
    let p_student_id: String
    let p_mapping_id: String
    let p_client_updated_at: String
    let p_last_modified_by: String
}

struct SupabaseSubjectMapping: Decodable {
    let mappingId: UUID
    let canonicalKey: String
    let defaultName: String
    let defaultColorHue: Int
    let icon: String?
    let displayName: String
    let displayColorHue: Int
    let displayIcon: String?
    let deletedAt: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case mapping_id
        case canonical_key
        case default_name
        case default_color_hue
        case icon
        case default_icon
        case display_name
        case display_color_hue
        case display_icon
        case deleted_at
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let mappingId = try container.decodeIfPresent(UUID.self, forKey: .mapping_id) {
            self.mappingId = mappingId
        } else {
            self.mappingId = try container.decode(UUID.self, forKey: .id)
        }

        canonicalKey = try container.decode(String.self, forKey: .canonical_key)
        defaultName = try container.decode(String.self, forKey: .default_name)
        defaultColorHue = try container.decode(Int.self, forKey: .default_color_hue)

        if let icon = try container.decodeIfPresent(String.self, forKey: .icon) {
            self.icon = icon
        } else {
            self.icon = try container.decodeIfPresent(String.self, forKey: .default_icon)
        }

        displayName = try container.decodeIfPresent(String.self, forKey: .display_name) ?? defaultName
        displayColorHue = try container.decodeIfPresent(Int.self, forKey: .display_color_hue) ?? defaultColorHue
        displayIcon = try container.decodeIfPresent(String.self, forKey: .display_icon) ?? icon
        deletedAt = try container.decodeIfPresent(String.self, forKey: .deleted_at)
    }
}
