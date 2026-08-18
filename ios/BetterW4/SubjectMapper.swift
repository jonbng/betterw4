//
//  SubjectMapper.swift
//  BetterW4
//
//  Maps a W4 lesson title to a canonical subject key and to the display metadata the UI
//  renders: name, hue and SF Symbol.
//
//  The machinery is unchanged from the Lectio original and is the part that is sound:
//
//      canonical key  ->  user override (mappingProvider)  ->  catalogue default
//
//  The VOCABULARY is new. The Danish gymnasium table (55 subjects), the Danish class-code
//  regex (`1x`, `2hf`, `3hx-u`, `AEOEAA` letters) and the 17 Danish ignore patterns
//  (`kor`, `udvalg`, `kostelever`, ...) are gone; UWC Red Cross Nordic teaches the IB
//  Diploma in English. The catalogue now lives in `SubjectIcons.swift`.
//
//  EVIDENCE:
//
//    [I] No W4 lesson block, class list or subject page has ever been captured, so the
//        exact string W4 prints for a subject is UNKNOWN. Every alias, every hue and
//        every symbol in `SubjectIcons.swift` is synthesized from the published IB
//        Diploma subject list. This file is therefore written so that a miss is cheap:
//
//          * A title that matches nothing keeps its OWN text as the display name and is
//            given a deterministic hash-derived hue, so two students never see the same
//            subject in two different colours and nobody sees a wrong subject name.
//          * Only genuinely empty input and a very short list of anchored grid-furniture
//            strings ("No-Classes", "Weekend", "TBA") resolve to no subject at all.
//
//  Colour: hue -> RGB at S 0.62 / V 0.88 (`color(hue:)`), unmapped hue 215.
//
//  KNOWN DIVERGENCE (not fixable from this file): `Color.lessonMappingHue(_:)` in
//  `SettingsStore.swift` renders the same hues at S 0.72. Wave 5/6 owns that file and
//  should delete the helper in favour of `SubjectMapper.color(hue:)`.
//

import SwiftUI

/// Maps W4 lesson titles to canonical subject keys and resolved display metadata.
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

    static var mappingProvider: ((String) -> ResolvedLessonMapping?)?
    static var subjectInfoProvider: (() -> [SubjectInfo])?

    // MARK: - Colour constants

    /// Hue used when a title resolves to no subject at all.
    static let unmappedHue = 215
    /// Saturation every subject colour is rendered at (`features.md` section 6).
    static let subjectSaturation = 0.62
    /// Brightness every subject colour is rendered at (`features.md` section 6).
    static let subjectBrightness = 0.88

    /// Renders a subject hue (any integer; wrapped into 0...359) as the app's subject colour.
    static func color(hue: Int) -> Color {
        let normalized = Double(((hue % 360) + 360) % 360) / 360.0
        return Color(hue: normalized, saturation: subjectSaturation, brightness: subjectBrightness)
    }

    // MARK: - Normalisation

    /// English-only, locale-stable folding. Never `Locale.current` — a student with a
    /// Turkish locale must not get a dotless `i` out of `iranian`.
    private static let lookupLocale = Locale(identifier: "en_GB_POSIX")

    /// Level markers stripped before lookup, so `Mathematics HL`, `Mathematics SL` and
    /// `Mathematics: Analysis and Approaches HL` all land on one canonical key.
    private static let levelWords: Set<String> = ["hl", "sl"]

    /// Multi-word level markers, removed before the string is split into words.
    private static let levelPhrasePattern = #"\b(?:ab initio|higher level|standard level)\b"#

    /// [I] Anchored on purpose. These are grid furniture, not lessons, and an anchored
    /// pattern cannot swallow a real subject the way an unanchored one can. There is no
    /// captured evidence for any of them beyond `No-Classes`, which `W4TimetableParser`
    /// already drops.
    private static let ignoredHoldPatterns: [String] = [
        #"^no[\s._-]?classes$"#,
        #"^no\s+ea$"#,
        #"^weekend$"#,
        #"^n\s*/?\s*a$"#,
        #"^tba$"#,
        #"^tbd$"#,
        #"^[-–—]+$"#
    ]

    /// [I] Generic, digit-bearing class/cohort tokens (`DP1`, `IB2`, `Y1`, `25`), plus the
    /// bare words that introduce them. Only ever stripped from the FRONT of a title, and
    /// only as a retry after the untouched title failed to resolve, so a false positive
    /// cannot hide a subject that would otherwise have matched.
    private static let classCodePattern = #"^(?:ib|dp|diploma|year|grade)$|^[a-z]{0,3}\d{1,4}[a-z]?$"#

    /// alias (already normalised) -> canonical key. Built once from the catalogue.
    private static let aliasToCanonicalKey: [String: String] = {
        var result: [String: String] = [:]
        for entry in SubjectIcons.all {
            // The raw key, so a call site that already holds a canonical key resolves
            // without going through the tokeniser.
            result[entry.canonicalKey] = entry.canonicalKey
            result[subjectLookupToken(entry.canonicalKey)] = entry.canonicalKey
            for alias in entry.aliases {
                result[subjectLookupToken(alias)] = entry.canonicalKey
            }
        }
        result.removeValue(forKey: "")
        return result
    }()

    // MARK: - Display metadata

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

    /// Catalogue name for a subject code or title; `fallback` (then the normalised input)
    /// when the catalogue has never heard of it. Never invents a name.
    static func defaultName(for subjectCode: String, fallback: String? = nil) -> String {
        if let match = definition(for: subjectCode) {
            return match.displayName
        }
        return fallback ?? normalizedHold(subjectCode)
    }

    static func isKnownSubject(_ subject: String) -> Bool {
        guard let canonicalKey = canonicalKey(for: subject) else {
            return false
        }
        return mappingProvider?(canonicalKey) != nil || SubjectIcons.byCanonicalKey[canonicalKey] != nil
    }

    static func iconName(for subject: String) -> String {
        guard let canonicalKey = canonicalKey(for: subject) else {
            return SubjectIcons.defaultSymbolName
        }

        if let resolved = mappingProvider?(canonicalKey) {
            return resolved.displayIcon ?? resolved.defaultIcon ?? defaultIconName(for: canonicalKey)
        }

        return defaultIconName(for: canonicalKey)
    }

    static func color(for subject: String) -> Color {
        guard let canonicalKey = canonicalKey(for: subject) else {
            return color(hue: unmappedHue)
        }

        if let resolved = mappingProvider?(canonicalKey) {
            return color(hue: resolved.displayColorHue)
        }

        return defaultColor(for: canonicalKey)
    }

    static func colorHue(for subject: String) -> Int {
        guard let canonicalKey = canonicalKey(for: subject) else {
            return unmappedHue
        }

        if let resolved = mappingProvider?(canonicalKey) {
            return resolved.displayColorHue
        }

        return defaultColorHue(for: canonicalKey)
    }

    static func defaultColor(for subjectCode: String) -> Color {
        color(hue: defaultColorHue(for: subjectCode))
    }

    /// Catalogue hue when the subject is known, otherwise a deterministic hue derived from
    /// the subject's own name. Deliberately NOT `hashValue`: Swift seeds that per process,
    /// so a student's unknown-subject colours would shuffle on every launch.
    static func defaultColorHue(for subjectCode: String) -> Int {
        if let match = definition(for: subjectCode) {
            return match.hue
        }
        let token = subjectLookupToken(subjectCode)
        guard !token.isEmpty else {
            return unmappedHue
        }
        return stableHue(for: token)
    }

    /// The IB group a subject belongs to, or `nil` when it is not in the catalogue.
    static func subjectGroup(for subject: String) -> IBSubjectGroup? {
        definition(for: subject)?.group
    }

    /// Catalogue entry for a code or a title; `nil` when nothing matches.
    static func definition(for subjectCode: String) -> IBSubjectDefinition? {
        let raw = normalizedHold(subjectCode)
        if let key = aliasToCanonicalKey[raw], let exact = SubjectIcons.byCanonicalKey[key] {
            return exact
        }
        let token = subjectLookupToken(subjectCode)
        guard let key = resolveCanonicalCandidate(token) else {
            return nil
        }
        return SubjectIcons.byCanonicalKey[key]
    }

    // MARK: - Subject lists

    static var knownSubjects: [SubjectInfo] {
        SubjectIcons.all
            .map { SubjectInfo(code: $0.canonicalKey, name: $0.displayName) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static var allSubjects: [SubjectInfo] {
        allSubjects(including: [])
    }

    static func allSubjects(including eventTitles: [String]) -> [SubjectInfo] {
        var subjectsByCode = Dictionary(
            (subjectInfoProvider?() ?? knownSubjects).map { ($0.code, $0) },
            uniquingKeysWith: { _, latest in latest }
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

    // MARK: - Canonical key

    /// The stable identity a user override is stored against.
    ///
    /// Returns `nil` only for input that is not a subject at all — empty, or one of the
    /// anchored grid-furniture strings. Anything else always gets a key: a catalogue key
    /// when we recognise it, otherwise the normalised title itself, so that an unknown
    /// subject still gets its own colour, its own settings row and its own override slot.
    static func canonicalKey(for subject: String) -> String? {
        let normalized = normalizedHold(subject)
        guard !normalized.isEmpty else {
            return nil
        }

        if isIgnoredHold(normalized) {
            return nil
        }

        let token = subjectLookupToken(normalized)
        guard !token.isEmpty else {
            return nil
        }

        if let match = resolveCanonicalCandidate(token) {
            return match
        }

        // Retry once with a leading class/cohort code removed: `DP1 Biology HL`.
        let stripped = strippingLeadingClassCodes(token)
        if stripped != token, let match = resolveCanonicalCandidate(stripped) {
            return match
        }

        // Unknown but academic-looking. Its own key, derived deterministically from the
        // title with the level marker already removed, so `X HL` and `X SL` still agree.
        return token
    }

    /// Legacy call sites still use this name; it returns the canonical key when known.
    static func extractSubjectCode(from subject: String) -> String {
        canonicalKey(for: subject) ?? normalizedHold(subject)
    }

    /// Trim plus whitespace collapse. The one normalisation that keeps the original text.
    static func normalizedHold(_ subject: String) -> String {
        subject
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    // MARK: - Matching

    /// Exact match first, then progressively drop trailing words, so the longest catalogue
    /// phrase wins: `english a language and literature` beats `english a` beats `english`.
    private static func resolveCanonicalCandidate(_ token: String) -> String? {
        guard !token.isEmpty else {
            return nil
        }
        if let key = aliasToCanonicalKey[token] {
            return key
        }

        var words = token.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        while words.count > 1 {
            words.removeLast()
            if let key = aliasToCanonicalKey[words.joined(separator: " ")] {
                return key
            }
        }
        return nil
    }

    private static func strippingLeadingClassCodes(_ token: String) -> String {
        var words = token.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        while words.count > 1, isClassCodeToken(words[0]) {
            words.removeFirst()
        }
        return words.joined(separator: " ")
    }

    private static func isClassCodeToken(_ word: String) -> Bool {
        word.range(of: classCodePattern, options: [.regularExpression]) != nil
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

    private static func defaultIconName(for canonicalKey: String) -> String {
        SubjectIcons.byCanonicalKey[canonicalKey]?.symbolName ?? SubjectIcons.defaultSymbolName
    }

    /// Lowercase, diacritic-folded, punctuation-to-space, level markers removed.
    /// Idempotent: feeding a token back through this produces the same token.
    static func subjectLookupToken(_ value: String) -> String {
        let folded = normalizedHold(value)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: lookupLocale)
            .lowercased(with: lookupLocale)

        let separated = folded.replacingOccurrences(
            of: #"[^\p{L}\p{N}]+"#,
            with: " ",
            options: .regularExpression
        )

        let withoutPhrases = separated.replacingOccurrences(
            of: levelPhrasePattern,
            with: " ",
            options: .regularExpression
        )

        let words = withoutPhrases
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { !levelWords.contains($0) }

        return words.joined(separator: " ")
    }

    /// FNV-1a (32-bit) over the token's UTF-8 bytes, folded into 0...359.
    ///
    /// Hand-rolled on purpose. `String.hashValue` is seeded per process, so using it would
    /// reshuffle every unknown subject's colour on every app launch.
    static func stableHue(for token: String) -> Int {
        var hash: UInt32 = 2_166_136_261
        for byte in token.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return Int(hash % 360)
    }
}
