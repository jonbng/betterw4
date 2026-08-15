import Foundation

enum MessageSignature {
    static let bbcode = "\n\n[url=\(BetterLectioLinks.downloadURL.absoluteString)]Sendt med BetterLectio[/url]"

    static func shouldShowSignature(participantIDs: [String], enabled: Bool) -> Bool {
        enabled && !participantIDs.contains { id in
            id.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().hasPrefix("T")
        }
    }

    static func appendIfNeeded(
        to body: String,
        recipientIDs: [String],
        enabled: Bool
    ) -> String {
        guard shouldShowSignature(participantIDs: recipientIDs, enabled: enabled) else { return body }
        guard body.range(of: "Sendt med BetterLectio", options: .caseInsensitive) == nil else {
            return body
        }

        return body + bbcode
    }

    static func appendToReplyIfNeeded(
        to body: String,
        participantIDs: [String],
        enabled: Bool
    ) -> String {
        guard !participantIDs.isEmpty else { return body }
        return appendIfNeeded(to: body, recipientIDs: participantIDs, enabled: enabled)
    }
}
