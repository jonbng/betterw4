//
//  SupabaseSchoolService.swift
//  BetterLectio
//

import Foundation
import Supabase

final class SupabaseSchoolService {
    static let shared = SupabaseSchoolService()

    private let manager: SupabaseManager

    init(manager: SupabaseManager = .shared) {
        self.manager = manager
    }

    func fetchAllSchools() async throws -> [School] {
        guard let client = manager.client else { return [] }

        let rows: [SchoolRow] = try await client
            .from("schools")
            .select("id,name")
            .order("name", ascending: true)
            .execute()
            .value

        return rows.map { School(id: Int($0.id), name: $0.name) }
    }
}

private struct SchoolRow: Decodable {
    let id: Int64
    let name: String
}
