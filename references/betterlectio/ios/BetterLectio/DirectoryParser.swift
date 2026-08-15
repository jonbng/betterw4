//
//  DirectoryParser.swift
//  BetterLectio
//

import Foundation
import SwiftSoup

enum DirectoryParser {

    nonisolated static func parseRawDirectoryItems(from data: Data, gymId: Int) throws -> [RawDirectoryItem] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[Any]] else {
            throw LectioError.parsingError("Invalid dropdown JSON structure")
        }

        return items.compactMap { item in
            guard item.count >= 2,
                  let rawLabel = item[0] as? String,
                  let rawPrefixedID = item[1] as? String,
                  !rawPrefixedID.isEmpty else {
                return nil
            }

            let prefix = String(rawPrefixedID.prefix { !$0.isNumber })
            let numericID = String(rawPrefixedID.drop { !$0.isNumber })
            guard !prefix.isEmpty, !numericID.isEmpty else { return nil }

            let isActive = (item.count > 2 ? (item[2] as? String) != "i" : true)
            let rawTypeMarker = (item.count > 4 ? item[4] as? String : nil)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty

            return RawDirectoryItem(
                gymId: gymId,
                rawLabel: rawLabel.trimmingCharacters(in: .whitespacesAndNewlines),
                rawPrefixedID: rawPrefixedID,
                prefix: prefix,
                numericID: numericID,
                isActive: isActive,
                rawTypeMarker: rawTypeMarker
            )
        }
    }

    nonisolated static func buildDirectoryEntities(from rawItems: [RawDirectoryItem], gymId: Int) -> [DirectoryEntity] {
        let baseEntities: [DirectoryEntity] = rawItems.map { buildEntity(from: $0, gymId: gymId) }
        let syntheticClasses: [DirectoryEntity] = deriveSyntheticClasses(from: baseEntities, gymId: gymId)

        let syntheticPairs: [(String, DirectoryEntity)] = syntheticClasses.compactMap { entity in
            guard let classCode = entity.metadata.classCode else { return nil }
            return (classCode.lowercased(), entity)
        }
        let syntheticByClass = Dictionary(syntheticPairs, uniquingKeysWith: { first, _ in first })

        let groupPairs: [(String, String)] = baseEntities.compactMap { entity in
            guard entity.kind == .group,
                  entity.metadata.groupSubtype == .classStudents,
                  let classCode = classCodeFromClassStudentGroup(entity.name) else { return nil }
            return (classCode.lowercased(), entity.rawPrefixedID)
        }
        let geByClass = Dictionary(groupPairs, uniquingKeysWith: { first, _ in first })

        let lectioClassPairs: [(String, String)] = baseEntities.compactMap { entity in
            guard entity.kind == .classLectio,
                  let classCode = classCodeFromLectioClass(entity.name) else { return nil }
            return (classCode.lowercased(), entity.rawPrefixedID)
        }
        let scByClass = Dictionary(lectioClassPairs, uniquingKeysWith: { first, _ in first })

        let linkedSyntheticClasses: [DirectoryEntity] = syntheticClasses.map { entity in
            guard let classCode = entity.metadata.classCode else { return entity }
            let lowered = classCode.lowercased()
            var metadata = entity.metadata
            metadata.linkedBuiltinGroupID = geByClass[lowered]
            metadata.linkedLectioClassID = scByClass[lowered]

            return DirectoryEntity(
                entityID: entity.entityID,
                gymId: entity.gymId,
                kind: entity.kind,
                rawPrefixedID: entity.rawPrefixedID,
                rawPrefix: entity.rawPrefix,
                numericID: entity.numericID,
                name: entity.name,
                subtitle: entity.subtitle,
                rawLabel: entity.rawLabel,
                normalizedName: entity.normalizedName,
                searchTokens: entity.searchTokens,
                isActive: entity.isActive,
                rawTypeMarker: entity.rawTypeMarker,
                metadata: metadata
            )
        }

        let linkedBaseEntities: [DirectoryEntity] = baseEntities.map { entity in
            guard entity.kind == .group,
                  let classCode = classCodeFromClassStudentGroup(entity.name),
                  let synthetic = syntheticByClass[classCode.lowercased()] else {
                return entity
            }

            var metadata = entity.metadata
            metadata.linkedBuiltinGroupID = entity.rawPrefixedID
            metadata.linkedLectioClassID = synthetic.metadata.linkedLectioClassID
            metadata.classCode = classCode

            return DirectoryEntity(
                entityID: entity.entityID,
                gymId: entity.gymId,
                kind: entity.kind,
                rawPrefixedID: entity.rawPrefixedID,
                rawPrefix: entity.rawPrefix,
                numericID: entity.numericID,
                name: entity.name,
                subtitle: entity.subtitle,
                rawLabel: entity.rawLabel,
                normalizedName: entity.normalizedName,
                searchTokens: entity.searchTokens,
                isActive: entity.isActive,
                rawTypeMarker: entity.rawTypeMarker,
                metadata: metadata
            )
        }

        return linkedBaseEntities + linkedSyntheticClasses
    }

    nonisolated static func parseHoldMembers(from html: String, gymId: Int) -> [ParsedHoldMember] {
        do {
            let doc = try SwiftSoup.parse(html)
            let rows = try doc.select("table#s_m_Content_Content_laerereleverpanel_alm_gv tr")

            var members: [ParsedHoldMember] = []

            for row in rows {
                guard let contextTd = try row.select("td[data-lectiocontextcard]").first() else {
                    continue
                }

                let rawPrefixedID = try contextTd.attr("data-lectiocontextcard")
                let prefix = String(rawPrefixedID.prefix { !$0.isNumber })
                let numericID = String(rawPrefixedID.drop { !$0.isNumber })
                guard !prefix.isEmpty, !numericID.isEmpty else { continue }

                let rawLabel = try contextTd.text().trimmingCharacters(in: .whitespacesAndNewlines)
                let item = RawDirectoryItem(
                    gymId: gymId,
                    rawLabel: rawLabel,
                    rawPrefixedID: rawPrefixedID,
                    prefix: prefix,
                    numericID: numericID,
                    isActive: true,
                    rawTypeMarker: nil
                )
                let entity = buildEntity(from: item, gymId: gymId)

                let pictureID: String?
                if let img = try row.select("img[src*=pictureid]").first() {
                    let src = try img.attr("src")
                    if let range = src.range(of: #"pictureid=(\d+)"#, options: .regularExpression) {
                        pictureID = src[range]
                            .replacingOccurrences(of: "pictureid=", with: "")
                    } else {
                        pictureID = nil
                    }
                } else {
                    pictureID = nil
                }

                members.append(ParsedHoldMember(entity: entity, pictureID: pictureID))
            }

            return members
        } catch {
            print("⚠️ Failed to parse hold members: \(error)")
            return []
        }
    }

    nonisolated static func normalize(_ string: String) -> String {
        string
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func buildEntity(from item: RawDirectoryItem, gymId: Int) -> DirectoryEntity {
        let kind = kind(for: item.prefix)

        switch kind {
        case .student:
            return buildStudentEntity(from: item, gymId: gymId)
        case .teacher:
            return buildTeacherEntity(from: item, gymId: gymId)
        case .hold:
            return buildHoldEntity(from: item, gymId: gymId)
        case .room:
            return buildRoomLikeEntity(from: item, gymId: gymId, kind: .room)
        case .resource:
            return buildRoomLikeEntity(from: item, gymId: gymId, kind: .resource)
        case .group:
            return buildGroupEntity(from: item, gymId: gymId)
        case .classLectio:
            return buildLectioClassEntity(from: item, gymId: gymId)
        case .classSynthetic:
            return buildSyntheticClassEntity(classCode: item.rawLabel, gymId: gymId, studentCount: nil)
        case .other:
            return makeEntity(
                item: item,
                gymId: gymId,
                kind: .other,
                name: item.rawLabel,
                subtitle: nil,
                metadata: DirectoryMetadata(rawInfo: item.rawLabel)
            )
        }
    }

    private nonisolated static func kind(for prefix: String) -> DirectoryEntityKind {
        switch prefix {
        case "S": return .student
        case "T": return .teacher
        case "HE": return .hold
        case "RO": return .room
        case "RE": return .resource
        case "GE": return .group
        case "SC": return .classLectio
        default: return .other
        }
    }

    private nonisolated static func buildStudentEntity(from item: RawDirectoryItem, gymId: Int) -> DirectoryEntity {
        let parsed = parsePersonLabel(item.rawLabel)
        let name = cleanStudentName(parsed.name)
        let info = parsed.info ?? ""
        let parts = info.split(separator: " ").map(String.init)

        var classCode: String?
        var seatNumber: String?
        var subtitle: String?

        if item.isActive,
           let first = parts.first,
           first.first?.isNumber == true {
            classCode = first
            seatNumber = parts.dropFirst().first
            subtitle = classCode
        } else if parts.count >= 2,
                  let second = parts.dropFirst().first,
                  second.first?.isNumber == true {
            classCode = second
            subtitle = second
        }

        let metadata = DirectoryMetadata(
            classCode: classCode,
            seatNumber: seatNumber,
            rawInfo: parsed.info
        )

        return makeEntity(
            item: item,
            gymId: gymId,
            kind: .student,
            name: name,
            subtitle: subtitle,
            metadata: metadata
        )
    }

    private nonisolated static func buildTeacherEntity(from item: RawDirectoryItem, gymId: Int) -> DirectoryEntity {
        let parsed = parsePersonLabel(item.rawLabel)
        let abbreviation = parsed.info?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty

        return makeEntity(
            item: item,
            gymId: gymId,
            kind: .teacher,
            name: parsed.name,
            subtitle: abbreviation,
            metadata: DirectoryMetadata(abbreviation: abbreviation, rawInfo: parsed.info)
        )
    }

    private nonisolated static func buildHoldEntity(from item: RawDirectoryItem, gymId: Int) -> DirectoryEntity {
        let tokens = item.rawLabel.split(separator: " ").map(String.init)
        let classCode = tokens.first(where: { token in
            token.first?.isNumber == true || token.lowercased().contains("g")
        })
        let subjectCode = tokens.dropFirst().first?.uppercased()

        return makeEntity(
            item: item,
            gymId: gymId,
            kind: .hold,
            name: item.rawLabel,
            subtitle: subjectCode,
            metadata: DirectoryMetadata(
                classCode: classCode,
                shortCode: item.rawLabel,
                subjectCode: subjectCode,
                rawInfo: item.rawLabel
            )
        )
    }

    private nonisolated static func buildRoomLikeEntity(from item: RawDirectoryItem, gymId: Int, kind: DirectoryEntityKind) -> DirectoryEntity {
        let segments = item.rawLabel.components(separatedBy: " - ")
        let shortCode = segments.first?.trimmingCharacters(in: .whitespacesAndNewlines)

        return makeEntity(
            item: item,
            gymId: gymId,
            kind: kind,
            name: item.rawLabel,
            subtitle: shortCode == item.rawLabel ? nil : shortCode,
            metadata: DirectoryMetadata(shortCode: shortCode, rawInfo: item.rawLabel)
        )
    }

    private nonisolated static func buildGroupEntity(from item: RawDirectoryItem, gymId: Int) -> DirectoryEntity {
        let lowerType = item.rawTypeMarker?.lowercased() ?? ""
        let subtype: DirectoryGroupSubtype

        if let classCode = classCodeFromClassStudentGroup(item.rawLabel) {
            subtype = item.rawLabel.localizedCaseInsensitiveContains("lærere") ? .classTeachers : .classStudents
            return makeEntity(
                item: item,
                gymId: gymId,
                kind: .group,
                name: item.rawLabel,
                subtitle: classCode,
                metadata: DirectoryMetadata(
                    classCode: classCode,
                    groupSubtype: subtype,
                    rawInfo: item.rawLabel
                )
            )
        } else if let yearCode = yearCodeFromYearGroup(item.rawLabel) {
            subtype = item.rawLabel.localizedCaseInsensitiveContains("lærere") ? .yearTeachers : .yearStudents
            return makeEntity(
                item: item,
                gymId: gymId,
                kind: .group,
                name: item.rawLabel,
                subtitle: yearCode,
                metadata: DirectoryMetadata(
                    yearCode: yearCode,
                    groupSubtype: subtype,
                    rawInfo: item.rawLabel
                )
            )
        } else if lowerType.contains("groupbuiltin") {
            subtype = .builtin
        } else if lowerType.contains("groupuser") {
            subtype = .user
        } else {
            subtype = .other
        }

        return makeEntity(
            item: item,
            gymId: gymId,
            kind: .group,
            name: item.rawLabel,
            subtitle: subtype == .other ? nil : subtype.rawValue,
            metadata: DirectoryMetadata(
                groupSubtype: subtype,
                rawInfo: item.rawLabel
            )
        )
    }

    private nonisolated static func buildLectioClassEntity(from item: RawDirectoryItem, gymId: Int) -> DirectoryEntity {
        let classCode = classCodeFromLectioClass(item.rawLabel)

        return makeEntity(
            item: item,
            gymId: gymId,
            kind: .classLectio,
            name: item.rawLabel,
            subtitle: classCode,
            metadata: DirectoryMetadata(
                classCode: classCode,
                rawInfo: item.rawLabel
            )
        )
    }

    private nonisolated static func buildSyntheticClassEntity(classCode: String, gymId: Int, studentCount: Int?) -> DirectoryEntity {
        let rawID = "SYN-\(classCode.lowercased())"
        let subtitle = studentCount.map { "\($0) elever" }
        let item = RawDirectoryItem(
            gymId: gymId,
            rawLabel: classCode,
            rawPrefixedID: rawID,
            prefix: "SYN",
            numericID: classCode,
            isActive: true,
            rawTypeMarker: nil
        )

        return makeEntity(
            item: item,
            gymId: gymId,
            kind: .classSynthetic,
            name: classCode,
            subtitle: subtitle,
            metadata: DirectoryMetadata(classCode: classCode, rawInfo: classCode)
        )
    }

    private nonisolated static func makeEntity(
        item: RawDirectoryItem,
        gymId: Int,
        kind: DirectoryEntityKind,
        name: String,
        subtitle: String?,
        metadata: DirectoryMetadata
    ) -> DirectoryEntity {
        let normalizedName = normalize(name)
        let tokens = searchTokens(name: name, subtitle: subtitle, metadata: metadata, rawLabel: item.rawLabel)

        return DirectoryEntity(
            entityID: DirectoryEntityID(gymId: gymId, kind: kind, rawID: item.rawPrefixedID),
            gymId: gymId,
            kind: kind,
            rawPrefixedID: item.rawPrefixedID,
            rawPrefix: item.prefix,
            numericID: item.numericID,
            name: name,
            subtitle: subtitle,
            rawLabel: item.rawLabel,
            normalizedName: normalizedName,
            searchTokens: tokens,
            isActive: item.isActive,
            rawTypeMarker: item.rawTypeMarker,
            metadata: metadata
        )
    }

    private nonisolated static func deriveSyntheticClasses(from entities: [DirectoryEntity], gymId: Int) -> [DirectoryEntity] {
        var countsByClass: [String: Int] = [:]
        for entity in entities where entity.kind == .student && entity.isActive {
            if let classCode = entity.metadata.classCode, !classCode.isEmpty {
                countsByClass[classCode, default: 0] += 1
            }
        }

        return countsByClass.keys.sorted().map { classCode in
            buildSyntheticClassEntity(classCode: classCode, gymId: gymId, studentCount: countsByClass[classCode])
        }
    }

    private nonisolated static func parsePersonLabel(_ label: String) -> (name: String, info: String?) {
        guard let parenOpen = label.lastIndex(of: "("),
              let parenClose = label.lastIndex(of: ")"),
              parenOpen < parenClose else {
            return (label.trimmingCharacters(in: .whitespacesAndNewlines), nil)
        }

        let name = String(label[..<parenOpen]).trimmingCharacters(in: .whitespacesAndNewlines)
        let info = String(label[label.index(after: parenOpen)..<parenClose]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (name, info)
    }

    private nonisolated static func cleanStudentName(_ string: String) -> String {
        var cleaned = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasSuffix("(k)") {
            cleaned = String(cleaned.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned
    }

    private nonisolated static func classCodeFromClassStudentGroup(_ name: String) -> String? {
        guard let match = name.range(of: #"Alle\s+([0-9][A-Za-z0-9]+)[-\s]elever"#, options: .regularExpression) else {
            return nil
        }
        let value = String(name[match])
        guard let regex = try? NSRegularExpression(pattern: #"Alle\s+([0-9][A-Za-z0-9]+)[-\s]elever"#),
              let result = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let swiftRange = Range(result.range(at: 1), in: value) else {
            return nil
        }
        return String(value[swiftRange]).lowercased()
    }

    private nonisolated static func yearCodeFromYearGroup(_ name: String) -> String? {
        guard let match = name.range(of: #"Alle\s+([123])\.\s*G\.\s*(elever|lærere)"#, options: .regularExpression) else {
            return nil
        }
        let value = String(name[match])
        guard let regex = try? NSRegularExpression(pattern: #"Alle\s+([123])\.\s*G\.\s*(elever|lærere)"#),
              let result = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let swiftRange = Range(result.range(at: 1), in: value) else {
            return nil
        }
        return "\(value[swiftRange])g"
    }

    /// Key used to link `SC` rows to synthetic / GE entities. Must be stable and unique per SC row in the payload.
    /// Examples from real dropdowns: `2025z`, `2025 1g7`, `2024 1g 7` (see `betterlectio.icon/dropdown.json`).
    private nonisolated static func classCodeFromLectioClass(_ name: String) -> String? {
        if let range = name.range(of: #"\b\d{4}[a-z]\b"#, options: [.regularExpression, .caseInsensitive]) {
            return String(name[range]).lowercased()
        }

        if let range = name.range(of: #"\b\d{4}\s+1g\s*(\d+)\b"#, options: [.regularExpression, .caseInsensitive]) {
            let matched = String(name[range])
            guard let regex = try? NSRegularExpression(pattern: #"\b\d{4}\s+1g\s*(\d+)\b"#, options: .caseInsensitive),
                  let result = regex.firstMatch(in: matched, range: NSRange(matched.startIndex..., in: matched)),
                  let digitRange = Range(result.range(at: 1), in: matched) else {
                return nil
            }
            return "1g\(matched[digitRange])".lowercased()
        }

        return nil
    }

    private nonisolated static func searchTokens(name: String, subtitle: String?, metadata: DirectoryMetadata, rawLabel: String) -> [String] {
        var values = [name, rawLabel]

        if let subtitle, !subtitle.isEmpty {
            values.append(subtitle)
        }
        if let classCode = metadata.classCode { values.append(classCode) }
        if let seatNumber = metadata.seatNumber { values.append(seatNumber) }
        if let abbreviation = metadata.abbreviation { values.append(abbreviation) }
        if let shortCode = metadata.shortCode { values.append(shortCode) }
        if let subjectCode = metadata.subjectCode { values.append(subjectCode) }
        if let yearCode = metadata.yearCode { values.append(yearCode) }
        if let rawInfo = metadata.rawInfo { values.append(rawInfo) }

        return Array(Set(values.map(normalize).filter { !$0.isEmpty })).sorted()
    }
}
