//
//  ClassRoster.swift
//  BetterW4
//
//  Class id on a timetable brick (`academics/classes/class&class_id=`).
//
//  Every real AC class brick links that page. Breakfast / assembly / advisor
//  groups do not, and those have no roster to load.
//

import Foundation

enum ClassRoster {
    /// `class_id` from a brick href, URL-decoded. `nil` when the block is not a class.
    static func classId(from href: String?) -> String? {
        guard let href, !href.isEmpty else { return nil }
        let decoded = href.removingPercentEncoding ?? href
        guard let match = firstCapture(#"(?:^|[?&])class_id=([^&#]+)"#, in: decoded) else {
            return nil
        }
        let id = (match.removingPercentEncoding ?? match)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? nil : id
    }

    private static func firstCapture(_ pattern: String, in source: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        guard let match = regex.firstMatch(in: source, options: [], range: range),
              match.numberOfRanges > 1,
              let capture = Range(match.range(at: 1), in: source) else {
            return nil
        }
        return String(source[capture])
    }
}
