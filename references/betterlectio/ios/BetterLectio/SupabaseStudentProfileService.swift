//
//  SupabaseStudentProfileService.swift
//  BetterLectio
//

import Foundation
import Supabase

/// Fetches school-scoped profile fields through RPCs that enforce row access and
/// birthday visibility on the server.
@MainActor
final class SupabaseStudentProfileService {
    static let shared = SupabaseStudentProfileService()

    private struct CacheEntry {
        let profile: StudentProfile?
        let fetchedAt: Date
    }

    private static let cacheLifetime: TimeInterval = 5 * 60

    private let manager: SupabaseManager
    private var cache: [String: CacheEntry] = [:]

    init(manager: SupabaseManager = .shared) {
        self.manager = manager
    }

    func profile(
        studentID: String,
        viewer: Student,
        forceRefresh: Bool = false
    ) async throws -> StudentProfile? {
        let id = studentID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }
        guard let client = manager.client else { throw StudentProfileServiceError.notConfigured }

        if client.auth.currentSession == nil {
            guard let credentials = KeychainManager.shared.loadCredentials(for: viewer.studentId) else {
                throw StudentProfileServiceError.sessionUnavailable
            }
            let sessionReady = await SupabaseAuthService.shared.ensureSession(
                credentials: credentials,
                studentId: viewer.studentId,
                gymId: viewer.gymId
            )
            guard sessionReady else { throw StudentProfileServiceError.sessionUnavailable }
        }
        guard client.auth.currentSession != nil else { throw StudentProfileServiceError.sessionUnavailable }

        // School and viewer identity are part of the key because profile visibility is viewer-specific.
        let cacheKey = "\(viewer.gymId)|\(viewer.studentId)|\(id)"

        if !forceRefresh,
           let cached = cache[cacheKey],
           Date().timeIntervalSince(cached.fetchedAt) < Self.cacheLifetime {
            return cached.profile
        }

        let rows: [StudentProfile] = try await client
            .rpc("get_student_profile", params: StudentProfileParams(p_student_id: id))
            .execute()
            .value
        let profile = rows.first
        cache[cacheKey] = CacheEntry(profile: profile, fetchedAt: Date())
        return profile
    }

    /// Batch avatar/profile lookup for lists such as messages. Cached rows are reused and
    /// missing IDs are fetched in one PostgREST request to avoid row-by-row network traffic.
    func profiles(
        studentIDs: [String],
        viewerStudentID: String,
        gymID: Int,
        forceRefresh: Bool = false
    ) async -> [String: StudentProfile] {
        let viewerID = viewerStudentID.trimmingCharacters(in: .whitespacesAndNewlines)
        let ids = Array(Set(studentIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
        guard !viewerID.isEmpty, !ids.isEmpty, let client = manager.client else { return [:] }

        if client.auth.currentSession == nil {
            guard let credentials = KeychainManager.shared.loadCredentials(for: viewerID),
                  await SupabaseAuthService.shared.ensureSession(
                    credentials: credentials,
                    studentId: viewerID,
                    gymId: gymID
                  ),
                  client.auth.currentSession != nil else { return [:] }
        }

        var result: [String: StudentProfile] = [:]
        var missing: [String] = []
        for id in ids {
            let key = "\(gymID)|\(viewerID)|\(id)"
            if !forceRefresh,
               let cached = cache[key],
               Date().timeIntervalSince(cached.fetchedAt) < Self.cacheLifetime {
                if let profile = cached.profile { result[id] = profile }
            } else {
                missing.append(id)
            }
        }

        guard !missing.isEmpty else { return result }
        do {
            let rows: [StudentProfile] = try await client
                .rpc("get_student_profiles", params: StudentProfilesParams(p_student_ids: missing))
                .execute()
                .value
            let fetched = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
            for id in missing {
                let profile = fetched[id]
                cache["\(gymID)|\(viewerID)|\(id)"] = CacheEntry(profile: profile, fetchedAt: Date())
                if let profile { result[id] = profile }
            }
        } catch {
            print("⚠️ [StudentProfile] Batch profiles unavailable: \(error.localizedDescription)")
        }
        return result
    }

    func clearCache() {
        cache.removeAll()
    }
}

enum StudentProfileServiceError: LocalizedError {
    case notConfigured
    case sessionUnavailable

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "BetterLectio-profiler er ikke konfigureret."
        case .sessionUnavailable:
            return "Din BetterLectio-session er ikke klar endnu."
        }
    }
}

private nonisolated struct StudentProfileParams: Encodable, Sendable {
    let p_student_id: String
}

private nonisolated struct StudentProfilesParams: Encodable, Sendable {
    let p_student_ids: [String]
}
