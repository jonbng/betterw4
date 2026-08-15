import Foundation
import SwiftSoup

enum MessageEditAudit {
    struct Result: Sendable {
        let html: String
        let editedAt: Date?
    }

    private static let pattern = try! NSRegularExpression(
        pattern: #"^Redigeret af (.+?),\s*d\.\s*(\d{1,2})/(\d{1,2})-(\d{4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?$"#,
        options: [.caseInsensitive]
    )
    private static let suffixPattern = try! NSRegularExpression(
        pattern: #"\s*Redigeret af .+?,\s*d\.\s*\d{1,2}/\d{1,2}-\d{4}\s+\d{1,2}:\d{2}(?::\d{2})?\s*$"#,
        options: [.caseInsensitive]
    )
    static let copenhagenTimeZone = TimeZone(identifier: "Europe/Copenhagen")!

    static func extract(from html: String) -> Result {
        guard !html.isEmpty,
              let document = try? SwiftSoup.parseBodyFragment(html),
              let body = document.body() else { return Result(html: html, editedAt: nil) }

        var candidate: Node?
        for node in body.getChildNodes().reversed() {
            if let textNode = node as? TextNode,
               textNode.getWholeText().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try? node.remove()
                continue
            }
            candidate = node
            break
        }

        guard let candidate else { return Result(html: html, editedAt: nil) }
        let candidateText: String
        if let element = candidate as? Element {
            candidateText = (try? element.text()) ?? ""
        } else if let textNode = candidate as? TextNode {
            candidateText = textNode.getWholeText()
        } else {
            return Result(html: html, editedAt: nil)
        }
        let normalized = candidateText
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let nsRange = NSRange(normalized.startIndex..., in: normalized)
        guard let match = pattern.firstMatch(in: normalized, range: nsRange),
              match.range == nsRange,
              let editedAt = date(from: match, in: normalized) else {
            return Result(html: html, editedAt: nil)
        }

        try? candidate.remove()
        return Result(html: ((try? body.html()) ?? html).trimmingCharacters(in: .whitespacesAndNewlines), editedAt: editedAt)
    }

    static func strippingTerminalAudit(from text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return suffixPattern.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func date(from match: NSTextCheckingResult, in text: String) -> Date? {
        func integer(_ index: Int, default defaultValue: Int? = nil) -> Int? {
            guard match.range(at: index).location != NSNotFound,
                  let range = Range(match.range(at: index), in: text) else { return defaultValue }
            return Int(text[range])
        }
        guard let day = integer(2), let month = integer(3), let year = integer(4),
              let hour = integer(5), let minute = integer(6), let second = integer(7, default: 0) else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = copenhagenTimeZone
        let components = DateComponents(
            timeZone: copenhagenTimeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        )
        guard let date = calendar.date(from: components) else { return nil }
        let verified = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard verified.year == year, verified.month == month, verified.day == day,
              verified.hour == hour, verified.minute == minute, verified.second == second else { return nil }
        return date
    }
}

enum MessageEditedTimeLabel: Equatable {
    case justNow
    case value(String)
}

enum MessageEditedTimeFormatter {
    static func label(for editedAt: Date, now: Date, locale: Locale = .current) -> MessageEditedTimeLabel {
        let elapsed = max(0, Int(now.timeIntervalSince(editedAt)))
        if elapsed < 60 { return .justNow }

        if elapsed < 7 * 24 * 60 * 60 {
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = locale
            formatter.dateTimeStyle = .numeric
            formatter.unitsStyle = .full
            let components: DateComponents
            if elapsed < 60 * 60 {
                components = DateComponents(minute: -(elapsed / 60))
            } else if elapsed < 24 * 60 * 60 {
                components = DateComponents(hour: -(elapsed / 3_600))
            } else {
                components = DateComponents(day: -(elapsed / 86_400))
            }
            return .value(formatter.localizedString(from: components))
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = MessageEditAudit.copenhagenTimeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return .value(formatter.string(from: editedAt))
    }
}
