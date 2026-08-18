//
//  BaseParser.swift
//  BetterW4
//
//  Created by Elliott Friedrich on 03/02/2026.
//

import Foundation
import SwiftSoup

/// Common utilities and shared logic for all W4 parsers.
enum BaseParser {
    
    /// Checks if HTML page is a robot detection or error page
    static func isRobotDetectionPage(_ html: String) -> Bool {
        return html.contains("RobotDetection") ||
               html.contains("Du er blevet logget ud") ||
               html.contains("Fejl")
    }

    /// Extracts ALL form field name/value pairs from the page.
    /// ASP.NET postback requires every field to be sent back.
    static func parseAllFormFields(from html: String) throws -> [(name: String, value: String)] {
        let doc = try SwiftSoup.parse(html)
        var fields: [(name: String, value: String)] = []

        // All <input> elements with a name (hidden, text, etc.)
        let inputs = try doc.select("input[name]")
        for input in inputs {
            let name = try input.attr("name")
            let type = try input.attr("type").lowercased()

            // Skip checkboxes — we handle them separately based on desired state
            if type == "checkbox" { continue }
            // Skip submit buttons
            if type == "submit" { continue }

            let value = try input.attr("value")
            fields.append((name: name, value: value))
        }

        // <select> elements
        let selects = try doc.select("select[name]")
        for select in selects {
            let name = try select.attr("name")
            // Get the selected option's value
            if let selected = try select.select("option[selected]").first() {
                fields.append((name: name, value: try selected.attr("value")))
            } else {
                fields.append((name: name, value: ""))
            }
        }

        // <textarea> elements
        let textareas = try doc.select("textarea[name]")
        for textarea in textareas {
            let name = try textarea.attr("name")
            let value = try textarea.text()
            fields.append((name: name, value: value))
        }

        return fields
    }
}

// MARK: - String Extensions

extension String {
    /// Returns nil if the string is empty after trimming
    nonisolated var nilIfEmpty: String? {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
