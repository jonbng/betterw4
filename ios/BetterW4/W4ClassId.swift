import Foundation

/// W4 class identifiers as printed on the timetable brick and in My classes.
///
/// Live capture (nc26jban, Aug 2026): `1DA13HMTAA` = 1st year, block D, room A 1.3,
/// Higher, Mathematics Analysis and Approaches. The brick shows only this code;
/// the real name is in `div.period[title]` as `Class: <b>…</b>`.
struct W4ClassId: Equatable, Sendable {
    let raw: String
    let year: Int
    let block: String
    let roomCode: String
    let level: Character
    let subjectCode: String

    var levelLabel: String {
        switch level {
        case "H": return "HL"
        case "S": return "SL"
        case "C": return "C"
        case "X": return "X"
        default: return String(level)
        }
    }

    private static let pattern = #"^(\d)([A-Za-z])([A-Za-z]{1,3}\d{0,2})([HSCXhscx])([A-Za-z]{3,5})$"#

    static func looksLike(_ raw: String) -> Bool { parse(raw) != nil }

    static func parse(_ raw: String) -> W4ClassId? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: trimmed,
                range: NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
              ),
              match.numberOfRanges == 6
        else {
            return nil
        }

        func group(_ index: Int) -> String? {
            guard let range = Range(match.range(at: index), in: trimmed) else { return nil }
            return String(trimmed[range])
        }

        guard let yearText = group(1), let year = Int(yearText),
              let block = group(2),
              let room = group(3),
              let levelText = group(4), let level = levelText.uppercased().first,
              let subject = group(5)
        else {
            return nil
        }

        return W4ClassId(
            raw: trimmed,
            year: year,
            block: block.uppercased(),
            roomCode: room.uppercased(),
            level: level,
            subjectCode: subject.uppercased()
        )
    }
}
