//
//  SupabaseClientProvider.swift
//  BetterLectio
//

import Foundation
import Supabase

struct SupabaseConfiguration {
    let projectURL: URL
    let publishableKey: String
}

final class SupabaseManager {
    static let shared = SupabaseManager()

    let configuration: SupabaseConfiguration?
    let client: SupabaseClient?

    var isConfigured: Bool { client != nil }

    private init() {
        let config = Self.loadConfiguration()
        self.configuration = config

        if let config {
            self.client = SupabaseClient(
                supabaseURL: config.projectURL,
                supabaseKey: config.publishableKey
            )
        } else {
            self.client = nil
            print("⚠️ [SupabaseManager] Configuration missing (SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY); remote sync disabled.")
        }
    }

    private static func loadConfiguration() -> SupabaseConfiguration? {
        guard
            let urlString = value(for: "SUPABASE_URL"),
            let projectURL = URL(string: urlString),
            let key = value(for: "SUPABASE_PUBLISHABLE_KEY"),
            !key.isEmpty
        else {
            return nil
        }

        return SupabaseConfiguration(projectURL: projectURL, publishableKey: key)
    }

    private static func value(for key: String) -> String? {
        if let processValue = ProcessInfo.processInfo.environment[key], !processValue.isEmpty {
            return processValue
        }

        if let plistValue = Bundle.main.object(forInfoDictionaryKey: key) as? String, !plistValue.isEmpty {
            return plistValue
        }

        return nil
    }
}
