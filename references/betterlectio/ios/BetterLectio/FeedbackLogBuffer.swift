import Foundation

/// A deliberately small, redacting diagnostic buffer. Callers must only record metadata;
/// request/response bodies, message text and other scraped content do not belong here.
final class FeedbackLogBuffer: @unchecked Sendable {
    static let shared = FeedbackLogBuffer()
    static let maxSnapshotCharacters = 24_000

    private let lock = NSLock()
    private var lines: [String] = []
    private let capacity: Int
    private let maxLineCharacters = 2_000

    init(capacity: Int = 250) {
        self.capacity = max(1, capacity)
    }

    func record(_ message: String, level: String = "I") {
        let safeMessage = Self.redact(String(message.prefix(maxLineCharacters)))
        lock.lock()
        let timestamp = Self.timestampFormatter.string(from: Date())
        let line = "\(timestamp) \(level): \(safeMessage)"
        lines.append(line)
        if lines.count > capacity {
            lines.removeFirst(lines.count - capacity)
        }
        lock.unlock()
    }

    func snapshot(maxCharacters: Int = FeedbackLogBuffer.maxSnapshotCharacters) -> String {
        lock.lock()
        let value = lines.joined(separator: "\n")
        lock.unlock()

        guard value.count > maxCharacters else { return value }
        return "…[ældre loglinjer udeladt]\n" + String(value.suffix(maxCharacters))
    }

    func clear() {
        lock.lock()
        lines.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    static func redact(_ input: String) -> String {
        var output = input
        let replacements: [(String, String)] = [
            (#"(?i)(ASP\.NET_SessionId|autologinkeyV2)\s*[=:]\s*[^;\s,]+"#, "$1=[REDACTED]"),
            (#"(?i)(authorization\s*[=:]\s*)(bearer\s+)?[^\s,]+"#, "$1[REDACTED]"),
            (#"(?i)((?:access|refresh)[_-]?token\s*[=:]\s*)[^\s,;]+"#, "$1[REDACTED]"),
            (#"(?i)((?:api[_-]?key|apikey|token[_-]?hash|password|passcode|client[_-]?secret)\s*[=:]\s*)[^\s,;]+"#, "$1[REDACTED]"),
            (#"(?i)([?&](?:token|code|key|api[_-]?key|access[_-]?token|refresh[_-]?token)=)[^&#\s]+"#, "$1[REDACTED]"),
            (#"(?i)(cookie|set-cookie)\s*[=:]\s*[^\n]+"#, "$1=[REDACTED]"),
            (#"(?i)((?:message|body|note|absence[_-]?note)\s*[=:]\s*)[^\n]+"#, "$1[REDACTED]"),
            (#"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#, "[EMAIL]"),
            (#"(?i)(/(?:Users|home)/)[^/\s]+/"#, "$1[USER]/")
        ]

        for (pattern, replacement) in replacements {
            output = output.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }
        return output
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}
