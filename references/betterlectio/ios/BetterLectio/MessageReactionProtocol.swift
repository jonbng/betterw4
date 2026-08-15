import Foundation
import SwiftSoup

enum MessageReactionEmoji: String, CaseIterable, Codable, Sendable {
    case thumbsUp = "👍"
    case heart = "❤️"
    case laugh = "😂"
    case surprised = "😮"
    case sad = "😢"
    case thumbsDown = "👎"
}

struct MessageLocator: Codable, Equatable, Hashable, Sendable {
    let senderKey: String
    let sentAt: String
    let occurrence: Int
}

struct MessageReactionParticipant: Codable, Equatable, Sendable {
    let key: String
    let name: String
    let isOwn: Bool
}

struct MessageReactionGroup: Codable, Equatable, Identifiable, Sendable {
    let emoji: MessageReactionEmoji
    let reactors: [MessageReactionParticipant]
    var id: MessageReactionEmoji { emoji }
}

enum MessageReactionEnvelope: Equatable, Sendable {
    case set(emoji: MessageReactionEmoji, target: MessageLocator)
    case clear(target: MessageLocator)

    var target: MessageLocator {
        switch self {
        case .set(_, let target), .clear(let target): target
        }
    }
}

enum MessageReactionProtocol {
    static let downloadURL = "https://betterlectio.dk/download"
    static let fragmentPrefix = "blr1."
    private static let maxURLLength = 2_048

    struct RawMessage: Sendable {
        let message: Message
        let rawContentHTML: String
        let editPostbackTarget: String
    }

    struct Carrier: Sendable {
        let envelope: MessageReactionEnvelope
        let actor: MessageReactionParticipant
        let editPostbackTarget: String
        let index: Int
    }

    struct ResolvedThread: Sendable {
        let messages: [Message]
        let ownCarriersByTarget: [MessageLocator: Carrier]
        let hiddenCarrierCount: Int
    }

    static func encode(_ envelope: MessageReactionEnvelope) -> String {
        let target = envelope.target
        var object: [String: Any] = [
            "v": 1,
            "target": [
                "senderKey": target.senderKey,
                "sentAt": target.sentAt,
                "occurrence": target.occurrence
            ]
        ]
        switch envelope {
        case .set(let emoji, _):
            object["op"] = "set"
            object["emoji"] = emoji.rawValue
        case .clear:
            object["op"] = "clear"
            object["emoji"] = NSNull()
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return ""
        }
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ encoded: String) -> MessageReactionEnvelope? {
        guard encoded.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else { return nil }
        var base64 = encoded.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["v"] as? Int == 1,
              let targetObject = object["target"] as? [String: Any],
              let senderKey = targetObject["senderKey"] as? String,
              let sentAt = targetObject["sentAt"] as? String,
              let occurrence = targetObject["occurrence"] as? Int else { return nil }
        let target = MessageLocator(senderKey: senderKey, sentAt: sentAt, occurrence: occurrence)
        guard valid(target) else { return nil }
        switch object["op"] as? String {
        case "set":
            guard let glyph = object["emoji"] as? String,
                  let emoji = MessageReactionEmoji(rawValue: glyph) else { return nil }
            return .set(emoji: emoji, target: target)
        case "clear":
            guard object["emoji"] is NSNull else { return nil }
            return .clear(target: target)
        default:
            return nil
        }
    }

    static func carrierURL(for envelope: MessageReactionEnvelope) -> String {
        "\(downloadURL)#\(fragmentPrefix)\(encode(envelope))"
    }

    static func carrierBody(for envelope: MessageReactionEnvelope, showSignature: Bool) -> String {
        let sentence: String
        switch envelope {
        case .set(let emoji, _): sentence = "Reagerede med “\(emoji.rawValue)”"
        case .clear: sentence = "Fjernede sin reaktion"
        }
        let label = showSignature ? "Sendt med BetterLectio" : "#"
        return "\(sentence)\n\n[url=\(carrierURL(for: envelope))]\(label)[/url]"
    }

    static func parseCarrierURL(_ rawURL: String) -> MessageReactionEnvelope? {
        guard !rawURL.isEmpty, rawURL.count <= maxURLLength,
              let components = URLComponents(string: rawURL),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == "betterlectio.dk",
              components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "download",
              components.query == nil,
              let fragment = components.fragment,
              fragment.hasPrefix(fragmentPrefix) else { return nil }
        return decode(String(fragment.dropFirst(fragmentPrefix.count)))
    }

    static func parseCarrierHTML(_ html: String) -> MessageReactionEnvelope? {
        guard !html.isEmpty,
              let document = try? SwiftSoup.parseBodyFragment(html),
              let body = document.body(),
              let anchors = try? body.select("a[href]").array() else { return nil }
        let matches = anchors.compactMap { anchor -> (Element, MessageReactionEnvelope)? in
            guard let href = try? anchor.attr("href"), let envelope = parseCarrierURL(href) else { return nil }
            return (anchor, envelope)
        }
        guard matches.count == 1 else { return nil }
        let (anchor, envelope) = matches[0]
        let label = ((try? anchor.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard label == "Sendt med BetterLectio" || label == "#" else { return nil }
        let expected: String
        switch envelope {
        case .set(let emoji, _): expected = "Reagerede med “\(emoji.rawValue)”"
        case .clear: expected = "Fjernede sin reaktion"
        }
        let fullText = MessageEditAudit.strippingTerminalAudit(from: ((try? body.text()) ?? ""))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return fullText == "\(expected) \(label)" ? envelope : nil
    }

    static func resolve(_ rawMessages: [RawMessage]) -> ResolvedThread {
        let candidates: [Carrier?] = rawMessages.enumerated().map { index, raw in
            guard raw.message.attachments.isEmpty,
                  let envelope = parseCarrierHTML(raw.rawContentHTML) else { return nil }
            let key = senderKey(entityID: raw.message.senderEntityID, senderName: raw.message.senderName)
            guard !key.isEmpty else { return nil }
            return Carrier(
                envelope: envelope,
                actor: MessageReactionParticipant(
                    key: key,
                    name: raw.message.senderName,
                    isOwn: !raw.editPostbackTarget.isEmpty
                ),
                editPostbackTarget: raw.editPostbackTarget,
                index: index
            )
        }

        var occurrences: [String: Int] = [:]
        var locators: [Int: MessageLocator] = [:]
        var targetIndexes: [String: Int] = [:]
        for (index, raw) in rawMessages.enumerated() where candidates[index] == nil {
            guard let locator = deriveLocator(raw.message, occurrences: &occurrences) else { continue }
            locators[index] = locator
            targetIndexes[locatorKey(locator)] = index
        }

        var carriersByTarget: [Int: [String: Carrier]] = [:]
        var hidden = Set<Int>()
        for carrier in candidates.compactMap({ $0 }) {
            guard let targetIndex = targetIndexes[locatorKey(carrier.envelope.target)],
                  targetIndex < carrier.index else { continue }
            hidden.insert(carrier.index)
            carriersByTarget[targetIndex, default: [:]][carrier.actor.key] = carrier
        }

        var ownCarriers: [MessageLocator: Carrier] = [:]
        var output: [Message] = []
        for (index, raw) in rawMessages.enumerated() where !hidden.contains(index) {
            let locator = locators[index]
            var grouped: [MessageReactionEmoji: [MessageReactionParticipant]] = [:]
            var ownReaction: MessageReactionEmoji?
            for carrier in (carriersByTarget[index] ?? [:]).values {
                if carrier.actor.isOwn, let locator { ownCarriers[locator] = carrier }
                if case .set(let emoji, _) = carrier.envelope {
                    grouped[emoji, default: []].append(carrier.actor)
                    if carrier.actor.isOwn { ownReaction = emoji }
                }
            }
            output.append(raw.message.with(
                locator: locator,
                reactions: MessageReactionEmoji.allCases.compactMap { emoji in
                    grouped[emoji].map { MessageReactionGroup(emoji: emoji, reactors: $0) }
                },
                ownReaction: ownReaction
            ))
        }
        return ResolvedThread(messages: output, ownCarriersByTarget: ownCarriers, hiddenCarrierCount: hidden.count)
    }

    static func senderKey(entityID: String?, senderName: String) -> String {
        let id = entityID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !id.isEmpty { return "id:\(id)" }
        let normalized = senderName.precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "da_DK"))
        return normalized.isEmpty ? "" : "name:\(normalized)"
    }

    static func locatorKey(_ locator: MessageLocator) -> String {
        "\(locator.senderKey)\u{001F}\(locator.sentAt)\u{001F}\(locator.occurrence)"
    }

    private static func deriveLocator(_ message: Message, occurrences: inout [String: Int]) -> MessageLocator? {
        let key = senderKey(entityID: message.senderEntityID, senderName: message.senderName)
        guard !key.isEmpty, let sentAt = normalizedTimestamp(message.date) else { return nil }
        let base = "\(key)\u{001F}\(sentAt)"
        let occurrence = occurrences[base, default: 0]
        occurrences[base] = occurrence + 1
        return MessageLocator(senderKey: key, sentAt: sentAt, occurrence: occurrence)
    }

    static func normalizedTimestamp(_ value: String) -> String? {
        let regex = try? NSRegularExpression(pattern: #"(\d{1,2})-(\d{1,2})-(\d{4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?"#)
        let range = NSRange(value.startIndex..., in: value)
        guard let match = regex?.firstMatch(in: value, range: range) else { return nil }
        func capture(_ index: Int) -> String? {
            guard let range = Range(match.range(at: index), in: value) else { return nil }
            return String(value[range])
        }
        guard let day = capture(1), let month = capture(2), let year = capture(3),
              let hour = capture(4), let minute = capture(5) else { return nil }
        let second = capture(6) ?? "00"
        return "\(year)-\(month.leftPadded)-\(day.leftPadded)T\(hour.leftPadded):\(minute):\(second)"
    }

    private static func valid(_ locator: MessageLocator) -> Bool {
        !locator.senderKey.isEmpty && locator.senderKey.count <= 256 &&
            locator.sentAt.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$"#, options: .regularExpression) != nil &&
            (0..<10).contains(locator.occurrence)
    }
}

private extension String {
    var leftPadded: String { count >= 2 ? self : "0" + self }
}
