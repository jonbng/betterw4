//
//  SubjectMapper.swift
//  BetterLectio
//
//  Created by Elliott Friedrich on 03/02/2026.
//

import SwiftUI

/// Maps Lectio holds to canonical lesson-mapping keys and resolved display metadata.
struct SubjectMapper {

    struct ResolvedLessonMapping: Codable, Equatable {
        let mappingId: UUID
        let canonicalKey: String
        let defaultName: String
        let defaultColorHue: Int
        let defaultIcon: String?
        var displayName: String
        var displayColorHue: Int
        var displayIcon: String?
    }

    struct SubjectInfo: Identifiable, Hashable {
        let code: String
        let name: String
        let mappingId: UUID?

        var id: String { code }

        init(code: String, name: String, mappingId: UUID? = nil) {
            self.code = code
            self.name = name
            self.mappingId = mappingId
        }
    }

    private struct SubjectMetadata {
        let defaultName: String
        let iconName: String
        let defaultHue: Int
        let aliases: Set<String>
    }

    static var mappingProvider: ((String) -> ResolvedLessonMapping?)?
    static var subjectInfoProvider: (() -> [SubjectInfo])?

    private static let locale = Locale(identifier: "da_DK")

    // Class-code regex constants ported from `lib/class-name.ts`. Matches every
    // Danish class shape Lectio surfaces: `1x`, `2hf`, `2zq`, `1.4`, `L2d`,
    // `S2x`, `IB1`, `10.st.kl.2`, hyphenated `3hx-u`, and named classes like
    // `BShannon` / `Epsilon`.
    private static let classLetter = "A-Za-zÆØÅæøå"
    private static let classSeparator = #"[._/-]"#
    private static let classSuffix = "(?:[\(classLetter)0-9]{1,2}|\(classSeparator)[\(classLetter)0-9]+)"
    private static let classCodeBody = "(?:[\(classLetter)]+\\d+|\\d+)"
    private static let namedClass = "[\(classLetter)]+"
    private static let classCode = "(?:[\(classLetter)]+\\d+(?:\(classSuffix))*|\(classCodeBody)(?:\(classSuffix))+|\(namedClass))"
    private static let classPrefixPattern = "^\(classCode)$"

    // Non-academic groups (kor, udvalg, kostskole, …) that look like holds but
    // should never resolve to a subject canonical key. Kept as raw strings — the
    // patterns deliberately rely on `æ`/`å`, so we match the un-folded hold.
    private static let ignoredHoldPatterns: [String] = [
        #"^alle\b"#,
        #"\belever\b"#,
        #"\blærere\b"#,
        #"\bkost(?:elever|tutor|lærere|skole)?\b"#,
        #"\blæsekursus\b"#,
        #"\budvalg\b"#,
        #"\bråd\b"#,
        #"\bguider\b"#,
        #"\bbuddies\b"#,
        #"\bfrivillig(?:hedskæmpere)?\b"#,
        #"\byoga\b"#,
        #"\bintro\b"#,
        #"\bledelsen\b"#,
        #"\bsamarbejdsudvalg\b"#,
        #"\balumneråd\b"#,
        #"\bskolerådet\b"#,
        #"\bkor\b"#,
        #"\bai-udvalg\b"#
    ]

    private static let metadataByCanonicalKey: [String: SubjectMetadata] = [
        "ap": SubjectMetadata(defaultName: "Almen sprogforståelse", iconName: "globe.europe.africa.fill", defaultHue: 48, aliases: ["ap", "almen sprogforstaaelse", "almen sprogforståelse"]),
        "as": SubjectMetadata(defaultName: "Astronomi", iconName: "sparkles", defaultHue: 260, aliases: ["as", "astronomi"]),
        "at": SubjectMetadata(defaultName: "AT", iconName: "doc.text.fill", defaultHue: 215, aliases: ["at", "almen studieforberedelse"]),
        "bi": SubjectMetadata(defaultName: "Biologi", iconName: "leaf.fill", defaultHue: 98, aliases: ["bi", "bio", "biologi"]),
        "bk": SubjectMetadata(defaultName: "Billedkunst", iconName: "paintpalette.fill", defaultHue: 355, aliases: ["bk", "billedkunst"]),
        "bro": SubjectMetadata(defaultName: "Brobygning", iconName: "link", defaultHue: 155, aliases: ["bro", "brobygning"]),
        "bt": SubjectMetadata(defaultName: "Bioteknologi", iconName: "atom", defaultHue: 160, aliases: ["bt", "bioteknologi"]),
        "da": SubjectMetadata(defaultName: "Dansk", iconName: "text.book.closed.fill", defaultHue: 342, aliases: ["da", "dan", "dansk"]),
        "de": SubjectMetadata(defaultName: "Design", iconName: "paintbrush.pointed.fill", defaultHue: 342, aliases: ["de", "design"]),
        "dho": SubjectMetadata(defaultName: "DHO", iconName: "doc.text.fill", defaultHue: 28, aliases: ["dho"]),
        "dr": SubjectMetadata(defaultName: "Dramatik", iconName: "theatermasks.fill", defaultHue: 25, aliases: ["dr", "dramatik"]),
        "en": SubjectMetadata(defaultName: "Engelsk", iconName: "book.fill", defaultHue: 215, aliases: ["en", "eng", "engelsk"]),
        "er": SubjectMetadata(defaultName: "Erhvervsøkonomi", iconName: "chart.line.uptrend.xyaxis", defaultHue: 65, aliases: ["er", "erhvervsoekonomi", "erhvervsøkonomi"]),
        "eø": SubjectMetadata(defaultName: "Erhvervsøkonomi", iconName: "chart.line.uptrend.xyaxis", defaultHue: 65, aliases: ["eø", "eoe", "eo", "erhvervsoekonomi"]),
        "ff": SubjectMetadata(defaultName: "Forsøgsfag", iconName: "lightbulb.fill", defaultHue: 52, aliases: ["ff", "forsøgsfag", "forsoegsfag", "fælles fagligt", "faelles fagligt"]),
        "fi": SubjectMetadata(defaultName: "Filosofi", iconName: "bubble.left.and.bubble.right.fill", defaultHue: 272, aliases: ["fi", "filosofi"]),
        "fr": SubjectMetadata(defaultName: "Fransk", iconName: "text.book.closed.fill", defaultHue: 330, aliases: ["fr", "frb", "frf", "fransk"]),
        "fy": SubjectMetadata(defaultName: "Fysik", iconName: "atom", defaultHue: 266, aliases: ["fy", "fys", "fysik"]),
        "ge": SubjectMetadata(defaultName: "Geografi", iconName: "globe.europe.africa.fill", defaultHue: 95, aliases: ["ge", "geo", "geografi"]),
        "hi": SubjectMetadata(defaultName: "Historie", iconName: "books.vertical.fill", defaultHue: 24, aliases: ["hi", "his", "historie"]),
        "id": SubjectMetadata(defaultName: "Idræt", iconName: "figure.run", defaultHue: 188, aliases: ["id", "idræt", "idraet"]),
        "if": SubjectMetadata(defaultName: "Idéhistorie", iconName: "books.vertical.fill", defaultHue: 300, aliases: ["if", "idehistorie", "idéhistorie", "ide-historie"]),
        "ih": SubjectMetadata(defaultName: "Idéhistorie", iconName: "books.vertical.fill", defaultHue: 300, aliases: ["ih"]),
        "it": SubjectMetadata(defaultName: "Informatik", iconName: "desktopcomputer", defaultHue: 248, aliases: ["it", "informatik"]),
        "inf": SubjectMetadata(defaultName: "Informatik", iconName: "desktopcomputer", defaultHue: 248, aliases: ["inf"]),
        "ke": SubjectMetadata(defaultName: "Kemi", iconName: "flask.fill", defaultHue: 138, aliases: ["ke", "kem", "kemi"]),
        "kit": SubjectMetadata(defaultName: "Kommunikation/IT", iconName: "bubble.left.and.text.bubble.right.fill", defaultHue: 305, aliases: ["kit", "kommunikation/it", "kommunikation it"]),
        "ks": SubjectMetadata(defaultName: "Kultur- og samfundsfag", iconName: "building.columns.fill", defaultHue: 186, aliases: ["ks", "kultur- og samfundsfag", "kultur og samfundsfag"]),
        "kt": SubjectMetadata(defaultName: "Klassens Time", iconName: "person.3.fill", defaultHue: 170, aliases: ["kt", "klassens time"]),
        "la": SubjectMetadata(defaultName: "Latin", iconName: "text.book.closed.fill", defaultHue: 358, aliases: ["la", "latin"]),
        "ma": SubjectMetadata(defaultName: "Matematik", iconName: "function", defaultHue: 238, aliases: ["ma", "mat", "matematik"]),
        "me": SubjectMetadata(defaultName: "Mediefag", iconName: "film.fill", defaultHue: 318, aliases: ["me", "mediefag"]),
        "mu": SubjectMetadata(defaultName: "Musik", iconName: "music.note", defaultHue: 322, aliases: ["mu", "musik"]),
        "ng": SubjectMetadata(defaultName: "Naturgeografi", iconName: "globe.europe.africa.fill", defaultHue: 88, aliases: ["ng", "naturgeografi"]),
        "nv": SubjectMetadata(defaultName: "Naturvidenskab", iconName: "atom", defaultHue: 145, aliases: ["nv", "naturvidenskab", "nat"]),
        "ol": SubjectMetadata(defaultName: "Oldtidskundskab", iconName: "building.columns", defaultHue: 40, aliases: ["ol", "oldtidskundskab"]),
        "pro": SubjectMetadata(defaultName: "Programmering", iconName: "chevron.left.forwardslash.chevron.right", defaultHue: 242, aliases: ["pro", "programmering"]),
        "ps": SubjectMetadata(defaultName: "Psykologi", iconName: "brain.head.profile", defaultHue: 312, aliases: ["ps", "psykologi"]),
        "pu": SubjectMetadata(defaultName: "Produktudvikling", iconName: "hammer.fill", defaultHue: 22, aliases: ["pu", "produktudvikling"]),
        "re": SubjectMetadata(defaultName: "Religion", iconName: "book.closed.fill", defaultHue: 285, aliases: ["re", "religion"]),
        "sa": SubjectMetadata(defaultName: "Samfundsfag", iconName: "building.columns.fill", defaultHue: 4, aliases: ["sa", "sam", "samf", "samfundsfag"]),
        "skr": SubjectMetadata(defaultName: "Skriftlige opgaver", iconName: "doc.text.fill", defaultHue: 12, aliases: ["skr", "skriftlige opgaver"]),
        "sp": SubjectMetadata(defaultName: "Spansk", iconName: "text.book.closed.fill", defaultHue: 15, aliases: ["sp", "spansk"]),
        "sro": SubjectMetadata(defaultName: "SRO", iconName: "doc.text.fill", defaultHue: 32, aliases: ["sro", "studieretningsopgave"]),
        "srp": SubjectMetadata(defaultName: "SRP", iconName: "doc.text.fill", defaultHue: 32, aliases: ["srp", "studieretningsprojekt"]),
        "ss": SubjectMetadata(defaultName: "Statistik", iconName: "chart.bar.fill", defaultHue: 225, aliases: ["ss", "statistik"]),
        "st": SubjectMetadata(defaultName: "Studievejledning", iconName: "person.fill.questionmark", defaultHue: 286, aliases: ["st", "studievejledning"]),
        "tek": SubjectMetadata(defaultName: "Teknologi", iconName: "gearshape.2.fill", defaultHue: 205, aliases: ["tek"]),
        "ti": SubjectMetadata(defaultName: "Teknologi", iconName: "gearshape.2.fill", defaultHue: 205, aliases: ["ti", "teknologi"]),
        "tk": SubjectMetadata(defaultName: "Teknikfag", iconName: "wrench.and.screwdriver.fill", defaultHue: 210, aliases: ["tk", "teknikfag"]),
        "ty": SubjectMetadata(defaultName: "Tysk", iconName: "text.book.closed.fill", defaultHue: 30, aliases: ["ty", "tys", "tysk"]),
        "vø": SubjectMetadata(defaultName: "Virksomhedsøkonomi", iconName: "briefcase.fill", defaultHue: 72, aliases: ["vø", "voe", "vo", "virksomhedsoekonomi", "virksomhedsøkonomi"])
    ]

    private static let aliasToCanonicalKey: [String: String] = {
        var result: [String: String] = [:]
        for (canonicalKey, metadata) in metadataByCanonicalKey {
            result[canonicalKey] = canonicalKey
            for alias in metadata.aliases {
                result[normalizedLookupToken(alias)] = canonicalKey
            }
        }
        return result
    }()

    static func displayName(for subject: String) -> String {
        let fallback = normalizedHold(subject)
        guard let canonicalKey = canonicalKey(for: subject) else {
            return fallback.isEmpty ? subject : fallback
        }

        if let resolved = mappingProvider?(canonicalKey) {
            return resolved.displayName
        }

        return defaultName(for: canonicalKey, fallback: fallback)
    }

    static func defaultName(for subjectCode: String, fallback: String? = nil) -> String {
        let lookup = normalizedLookupToken(subjectCode)
        if let canonicalKey = aliasToCanonicalKey[lookup],
           let metadata = metadataByCanonicalKey[canonicalKey] {
            return metadata.defaultName
        }
        return fallback ?? normalizedHold(subjectCode)
    }

    static func isKnownSubject(_ subject: String) -> Bool {
        guard let canonicalKey = canonicalKey(for: subject) else {
            return false
        }
        return mappingProvider?(canonicalKey) != nil || metadataByCanonicalKey[canonicalKey] != nil
    }

    static func iconName(for subject: String) -> String {
        guard let canonicalKey = canonicalKey(for: subject) else {
            return "book.fill"
        }

        if let resolved = mappingProvider?(canonicalKey) {
            return resolved.displayIcon ?? resolved.defaultIcon ?? defaultIconName(for: canonicalKey)
        }

        return defaultIconName(for: canonicalKey)
    }

    static func color(for subject: String) -> Color {
        guard let canonicalKey = canonicalKey(for: subject) else {
            return .blue
        }

        if let resolved = mappingProvider?(canonicalKey) {
            return Color.lessonMappingHue(resolved.displayColorHue)
        }

        return defaultColor(for: canonicalKey)
    }

    static func colorHue(for subject: String) -> Int {
        guard let canonicalKey = canonicalKey(for: subject) else {
            return 215
        }

        if let resolved = mappingProvider?(canonicalKey) {
            return resolved.displayColorHue
        }

        return defaultColorHue(for: canonicalKey)
    }

    static func defaultColor(for subjectCode: String) -> Color {
        Color.lessonMappingHue(defaultColorHue(for: subjectCode))
    }

    static func defaultColorHue(for subjectCode: String) -> Int {
        let lookup = normalizedLookupToken(subjectCode)
        if let canonicalKey = aliasToCanonicalKey[lookup],
           let metadata = metadataByCanonicalKey[canonicalKey] {
            return metadata.defaultHue
        }
        return 215
    }

    static var knownSubjects: [SubjectInfo] {
        metadataByCanonicalKey
            .keys
            .sorted()
            .map { canonicalKey in
                let metadata = metadataByCanonicalKey[canonicalKey]!
                return SubjectInfo(code: canonicalKey, name: metadata.defaultName)
            }
    }

    static var allSubjects: [SubjectInfo] {
        allSubjects(including: [])
    }

    static func allSubjects(including eventTitles: [String]) -> [SubjectInfo] {
        var subjectsByCode = Dictionary(
            uniqueKeysWithValues: (subjectInfoProvider?() ?? knownSubjects).map { ($0.code, $0) }
        )

        for title in eventTitles {
            guard let canonicalKey = canonicalKey(for: title), subjectsByCode[canonicalKey] == nil else {
                continue
            }

            let resolvedName = mappingProvider?(canonicalKey)?.displayName
                ?? defaultName(for: canonicalKey, fallback: normalizedHold(title))
            subjectsByCode[canonicalKey] = SubjectInfo(code: canonicalKey, name: resolvedName)
        }

        return subjectsByCode.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Returns the shared canonical key used by lesson-mapping v2, or `nil` for unknown holds.
    static func canonicalKey(for subject: String) -> String? {
        let normalized = normalizedHold(subject)
        guard !normalized.isEmpty else {
            return nil
        }

        if isIgnoredHold(normalized) {
            return nil
        }

        if let directMatch = resolveCanonicalCandidate(normalized) {
            return directMatch
        }

        let parts = normalized.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count > 1 else {
            return nil
        }

        let prefix = normalizeClassCode(String(parts[0]))
        guard prefix.range(of: classPrefixPattern,
                           options: [.regularExpression, .caseInsensitive]) != nil else {
            return nil
        }

        let remainder = parts.dropFirst().joined(separator: " ")
        return resolveCanonicalCandidate(remainder)
    }

    /// Legacy call sites still use this name; it now returns the v2 canonical key when known.
    static func extractSubjectCode(from subject: String) -> String {
        canonicalKey(for: subject) ?? normalizedHold(subject)
    }

    static func normalizedHold(_ subject: String) -> String {
        subject
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func resolveCanonicalCandidate(_ candidate: String) -> String? {
        let normalizedCandidate = normalizedLookupToken(candidate)
        if let canonicalKey = aliasToCanonicalKey[normalizedCandidate] {
            return canonicalKey
        }

        // Strip trailing subject-level qualifier like `-A`/`-B` (e.g. `MA-A` → `MA`).
        let stripped = stripSubjectLevelSuffix(normalizedCandidate)
        if stripped != normalizedCandidate, let canonicalKey = aliasToCanonicalKey[stripped] {
            return canonicalKey
        }

        let tokens = normalizedCandidate.split(separator: " ", omittingEmptySubsequences: true)
        guard let firstToken = tokens.first else {
            return nil
        }

        let firstStripped = stripSubjectLevelSuffix(String(firstToken))
        return aliasToCanonicalKey[String(firstToken)]
            ?? aliasToCanonicalKey[firstStripped]
    }

    /// Some Lectio schedule titles surface a hold identifier like `t25htxvx_1vx`
    /// instead of a stamklasse. When the segment after the last underscore is itself
        /// a valid class code, treat that as the canonical class name.
    private static func normalizeClassCode(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("_"),
              let underscoreIdx = trimmed.lastIndex(of: "_") else { return trimmed }
        let tail = String(trimmed[trimmed.index(after: underscoreIdx)...])
        if tail.range(of: classPrefixPattern,
                      options: [.regularExpression, .caseInsensitive]) != nil {
            return tail
        }
        return trimmed
    }

    private static func isIgnoredHold(_ holdCode: String) -> Bool {
        let normalized = normalizedHold(holdCode)
        for pattern in ignoredHoldPatterns {
            if normalized.range(of: pattern,
                                options: [.regularExpression, .caseInsensitive]) != nil {
                return true
            }
        }
        return false
    }

    private static func stripSubjectLevelSuffix(_ token: String) -> String {
        token.replacingOccurrences(of: #"-[a-zæøå]+$"#,
                                   with: "",
                                   options: [.regularExpression, .caseInsensitive])
    }

    private static func defaultIconName(for canonicalKey: String) -> String {
        metadataByCanonicalKey[canonicalKey]?.iconName ?? "book.fill"
    }

    private static func normalizedLookupToken(_ value: String) -> String {
        normalizedHold(value)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: locale)
            .lowercased(with: locale)
            .replacingOccurrences(
                of: #"(^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$)"#,
                with: "",
                options: .regularExpression
            )
    }
}
