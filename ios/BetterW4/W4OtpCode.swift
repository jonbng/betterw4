//
//  W4OtpCode.swift
//  BetterW4
//
//  W4 emails an 8-character mixed-case code (`5Z4IccMB`, `w3RSqC6f`).
//  Clipboard auto-fill only accepts the whole copied string so a username
//  (`nc` + two-digit year, e.g. `nc26abcd`) or a longer password is never
//  treated as a code.
//

import Foundation

enum W4OtpCode {
    static let length = 8

    static func extract(_ raw: String?) -> String? {
        guard var trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        trimmed = unquote(trimmed).trimmingCharacters(in: .whitespacesAndNewlines)
        trimmed = trimmed.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        return looksLike(trimmed) ? trimmed : nil
    }

    static func looksLike(_ code: String) -> Bool {
        guard code.count == length else { return false }
        guard code.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return false }
        if looksLikeUsername(code) { return false }
        return code.contains { $0.isASCII && $0.isUppercase }
    }

    /// W4 ids are `nc` + two-digit year + letters (`nc26abcd`). Never treat those as a code.
    private static func looksLikeUsername(_ code: String) -> Bool {
        guard code.count >= 4 else { return false }
        let chars = Array(code)
        let n = chars[0]
        let c = chars[1]
        return (n == "n" || n == "N") && (c == "c" || c == "C")
            && chars[2].isASCII && chars[2].isNumber
            && chars[3].isASCII && chars[3].isNumber
    }

    static func sanitizeInput(_ value: String) -> String {
        String(value.filter { !$0.isWhitespace }.prefix(length))
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2,
              let first = value.first,
              let last = value.last else { return value }
        if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}
