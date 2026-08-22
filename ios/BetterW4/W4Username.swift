//
//  W4Username.swift
//  BetterW4
//
//  W4 usernames are the UWC id (`nc26jban`). People often paste the school
//  email (`nc26jban@uwcrcn.no`) instead — keep the local part only.
//

import Foundation

enum W4Username {
    static func normalize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let at = trimmed.firstIndex(of: "@") else { return trimmed }
        return trimmed[..<at].trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
