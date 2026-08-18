//
//  SubjectMapperTests.swift
//  BetterW4Tests
//
//  EVIDENCE NOTE — read before adding a test here.
//
//  [I] Every subject string in this file is SYNTHESIZED. No W4 lesson block, class list,
//      timetable period or subject page has ever been captured, so nobody has seen the
//      exact text UWCRCN W4 prints for a subject. These tests verify OUR MAPPER against
//      titles written the way the IB writes subject names — they do NOT verify W4.
//
//      Concretely: a green suite here proves that "Mathematics HL" and "Mathematics SL"
//      collapse to one key in our code. It proves nothing about whether W4 ever emits
//      the string "Mathematics HL". When a real timetable is finally captured, the
//      catalogue in SubjectIcons.swift is the thing that will need revisiting; the
//      machinery tested here should survive unchanged.
//
//  There are no [V] assertions in this file, because there is no captured evidence to
//  assert against.
//

import XCTest
import SwiftUI
@testable import BetterW4

final class SubjectMapperTests: XCTestCase {

    override func tearDown() {
        SubjectMapper.mappingProvider = nil
        SubjectMapper.subjectInfoProvider = nil
        super.tearDown()
    }

    // MARK: - The five subjects the port plan calls out

    /// [I] Plan item 4.12 "Done": Mathematics HL, English A HL, Biology SL, TOK and
    /// Visual Arts all map, and to five different colours.
    func testFlagshipIBSubjectsMapToDistinctColours() {
        let titles = ["Mathematics HL", "English A HL", "Biology SL", "TOK", "Visual Arts"]

        XCTAssertEqual(
            titles.map { SubjectMapper.canonicalKey(for: $0) },
            ["mathematics", "english-a", "biology", "tok", "visual-arts"]
        )

        for title in titles {
            XCTAssertTrue(SubjectMapper.isKnownSubject(title), "\(title) should be in the catalogue")
        }

        let hues = titles.map { SubjectMapper.colorHue(for: $0) }
        XCTAssertEqual(Set(hues).count, hues.count, "flagship subjects share a hue: \(hues)")
        XCTAssertFalse(hues.contains(SubjectMapper.unmappedHue), "a known subject used the unmapped hue")

        XCTAssertEqual(SubjectMapper.displayName(for: "Mathematics HL"), "Mathematics")
        XCTAssertEqual(SubjectMapper.displayName(for: "English A HL"), "English A")
        XCTAssertEqual(SubjectMapper.displayName(for: "Biology SL"), "Biology")
        XCTAssertEqual(SubjectMapper.displayName(for: "TOK"), "Theory of Knowledge")
        XCTAssertEqual(SubjectMapper.displayName(for: "Visual Arts"), "Visual Arts")
    }

    // MARK: - HL / SL / ab initio stripping

    /// [I] The same subject at HL and at SL must be one key, one hue and one icon.
    func testLevelSuffixesCollapseToOneSubject() {
        let variants = [
            "Mathematics HL",
            "Mathematics SL",
            "Mathematics: Analysis and Approaches HL",
            "Mathematics: Applications and Interpretation SL",
            "Maths HL",
            "mathematics"
        ]

        for variant in variants {
            XCTAssertEqual(SubjectMapper.canonicalKey(for: variant), "mathematics", "\(variant)")
        }

        XCTAssertEqual(Set(variants.map { SubjectMapper.colorHue(for: $0) }).count, 1)
        XCTAssertEqual(Set(variants.map { SubjectMapper.iconName(for: $0) }).count, 1)
        XCTAssertEqual(SubjectMapper.iconName(for: "Mathematics SL"), "function")
    }

    /// [I] `ab initio`, `Higher Level` and `Standard Level` are levels, not subjects.
    func testAbInitioAndSpelledOutLevelsAreStripped() {
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "Spanish ab initio"), "spanish")
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "Spanish B SL"), "spanish")
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "Spanish B (Higher Level)"), "spanish")
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "English B Standard Level"), "english-b")

        XCTAssertEqual(
            SubjectMapper.colorHue(for: "Spanish ab initio"),
            SubjectMapper.colorHue(for: "Spanish B SL")
        )
    }

    /// [I] A longer catalogue phrase must beat a shorter one: `English A` is not `English B`.
    func testLongestSubjectPhraseWins() {
        XCTAssertEqual(
            SubjectMapper.canonicalKey(for: "English A: Language and Literature HL"),
            "english-a"
        )
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "English B SL"), "english-b")
        XCTAssertNotEqual(
            SubjectMapper.colorHue(for: "English A HL"),
            SubjectMapper.colorHue(for: "English B SL")
        )

        XCTAssertEqual(SubjectMapper.canonicalKey(for: "Norwegian A SL"), "norwegian-a")
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "Norwegian B SL"), "norwegian-b")
    }

    /// [I] A leading cohort code is stripped only as a retry, never before a direct match.
    func testLeadingClassCodeIsStrippedAsARetry() {
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "DP1 Biology HL"), "biology")
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "IB2 Visual Arts SL"), "visual-arts")
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "Y1 TOK"), "tok")
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "Grade 11 Chemistry HL"), "chemistry")
    }

    /// Live W4 class ids from `academics/classes` (nc26jban, Aug 2026). The brick
    /// prints `1EA16CECOX`; the suffix is the subject.
    func testCapturedW4ClassIdsMapToCatalogueSubjects() {
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "1DA13HMTAA"), "mathematics")
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "1EA16CECOX"), "economics")
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "1YA25SLALI"), "english-a")
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "2AA24CDALI"), "danish-a")
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "1CA24CPHIX"), "philosophy")
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "1BE12CPHYX"), "physics")
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "1ZAUDXCORE"), "core-meetings")
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "2DA14XTHOK"), "tok")
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "1AK21CGLOP"), "global-politics")
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "1AA26CNOLI"), "norwegian-a")
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "1AA13CSPLI"), "spanish-a")
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "1XA12SSPAB"), "spanish")
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "2XA26CSPBB"), "spanish")
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "1XA24SFRAB"), "french")
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "1DA21HENGB"), "english-b")
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "1EE15CENSS"), "environmental-systems-and-societies")
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "1CMUSCTHEX"), "theatre")
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "1CA22CVART"), "visual-arts")
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "2YA25SWOLX"), "world-literature")
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "1BA24CPSYC"), "psychology")
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "1EA11SMTAI"), "mathematics")

        XCTAssertEqual(SubjectMapper.displayName(for: "1EA16CECOX"), "Economics")
        XCTAssertEqual(SubjectMapper.displayName(for: "1DA13HMTAA"), "Mathematics")
        XCTAssertEqual(SubjectMapper.colorHue(for: "1DA13HMTAA"), SubjectMapper.colorHue(for: "Mathematics HL"))
    }

    // MARK: - Unknown subjects

    /// [I] An unmatched title keeps its own text and gets a deterministic hue. The pinned
    /// number is our own FNV-1a-32 over the normalised token — pinning it is exactly the
    /// point, because a process-seeded hash would reshuffle a student's colours on every
    /// launch.
    func testUnknownSubjectKeepsItsNameAndGetsAStableHue() {
        let title = "Underwater Basket Weaving HL"

        XCTAssertFalse(SubjectMapper.isKnownSubject(title))
        XCTAssertEqual(SubjectMapper.displayName(for: title), title)
        XCTAssertEqual(SubjectMapper.canonicalKey(for: title), "underwater basket weaving")
        XCTAssertEqual(SubjectMapper.iconName(for: title), SubjectIcons.defaultSymbolName)

        let first = SubjectMapper.colorHue(for: title)
        let second = SubjectMapper.colorHue(for: title)
        XCTAssertEqual(first, second, "unknown-subject hue must be stable across calls")
        XCTAssertEqual(first, 131, "FNV-1a-32 of \"underwater basket weaving\", mod 360")

        // Same subject, other level: same colour.
        XCTAssertEqual(SubjectMapper.colorHue(for: "Underwater Basket Weaving SL"), first)
        // Different subject: different colour.
        XCTAssertNotEqual(SubjectMapper.colorHue(for: "Quantum Bagpipes HL"), first)
        XCTAssertEqual(SubjectMapper.colorHue(for: "Quantum Bagpipes HL"), 93)
    }

    /// [I] An unknown subject still earns a row on the subject-colour screen, under its
    /// own name, so the user can recolour it.
    func testUnknownSubjectAppearsInAllSubjects() {
        let subjects = SubjectMapper.allSubjects(
            including: ["Biology HL", "Underwater Basket Weaving HL"]
        )

        XCTAssertTrue(subjects.contains { $0.code == "biology" })
        let unknown = subjects.first { $0.code == "underwater basket weaving" }
        XCTAssertEqual(unknown?.name, "Underwater Basket Weaving HL")
    }

    // MARK: - Non-subjects

    /// [I] Only anchored grid furniture resolves to nothing. `No-Classes` is the one
    /// string here with any provenance at all: `W4TimetableParser` already drops it.
    func testGridFurnitureResolvesToNoSubject() {
        for furniture in ["No-Classes", "No Classes", "Weekend", "No EA", "TBA", "tbd", "n/a"] {
            XCTAssertNil(SubjectMapper.canonicalKey(for: furniture), "\(furniture)")
            XCTAssertEqual(SubjectMapper.colorHue(for: furniture), SubjectMapper.unmappedHue)
            XCTAssertEqual(SubjectMapper.iconName(for: furniture), SubjectIcons.defaultSymbolName)
        }

        XCTAssertNil(SubjectMapper.canonicalKey(for: "   "))
        XCTAssertNil(SubjectMapper.canonicalKey(for: ""))
    }

    // MARK: - The Danish vocabulary is gone

    /// [I] Not one of the 55 Danish gymnasium subjects may still resolve.
    func testNoDanishGymnasiumSubjectResolves() {
        let danish = [
            "Matematik", "Dansk", "Samfundsfag", "Biologi", "Kemi", "Fysik", "Historie",
            "Engelsk", "Tysk", "Fransk", "Spansk", "Billedkunst", "Musik", "Idraet",
            "Psykologi", "Filosofi", "Geografi", "Informatik", "Oldtidskundskab",
            "Studieretningsprojekt", "SRP", "SRO", "DHO", "AP", "AT", "Mediefag",
            "Naturgeografi", "Erhvervsoekonomi", "Virksomhedsoekonomi", "Teknikfag"
        ]

        for subject in danish {
            XCTAssertFalse(
                SubjectMapper.isKnownSubject(subject),
                "\(subject) still resolves to a catalogue subject"
            )
            XCTAssertNil(SubjectMapper.definition(for: subject), "\(subject)")
        }
    }

    /// [I] The 17 Danish ignore patterns are gone: a Danish non-academic hold is now just
    /// an unknown subject, not a swallowed one.
    func testDanishIgnorePatternsAreGone() {
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "Kostelever"), "kostelever")
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "Alle elever"), "alle elever")
        XCTAssertEqual(SubjectMapper.canonicalKey(for: "AI-udvalg"), "ai udvalg")
    }

    /// [I] Nothing in the catalogue may carry a non-ASCII character, which is the cheapest
    /// mechanical proof that no Danish name survived.
    func testCatalogueIsPureASCII() {
        for definition in SubjectIcons.all {
            var strings = [definition.canonicalKey, definition.displayName, definition.symbolName]
            strings.append(contentsOf: definition.aliases)

            for text in strings {
                XCTAssertTrue(
                    text.unicodeScalars.allSatisfy { $0.isASCII },
                    "non-ASCII in catalogue entry: \(text)"
                )
            }

            XCTAssertFalse(definition.symbolName.isEmpty, "\(definition.canonicalKey) has no icon")
            XCTAssertEqual(
                definition.canonicalKey,
                definition.canonicalKey.lowercased(),
                "canonical keys must be lowercase"
            )
        }

        for group in IBSubjectGroup.allCases {
            XCTAssertTrue(group.displayName.unicodeScalars.allSatisfy { $0.isASCII })
            XCTAssertFalse(group.symbolName.isEmpty)
        }
    }

    // MARK: - Catalogue integrity

    /// [I] Keys, hues and aliases must be unambiguous, or an override would land on the
    /// wrong subject.
    func testCatalogueKeysHuesAndAliasesAreUnambiguous() {
        let keys = SubjectIcons.all.map(\.canonicalKey)
        XCTAssertEqual(Set(keys).count, keys.count, "duplicate canonical key")

        let hues = SubjectIcons.all.map(\.hue)
        XCTAssertEqual(Set(hues).count, hues.count, "two subjects share a hue")
        XCTAssertFalse(hues.contains(SubjectMapper.unmappedHue), "a subject squats on the unmapped hue")
        for hue in hues {
            XCTAssertTrue((0..<360).contains(hue), "hue \(hue) out of range")
        }

        var owner: [String: String] = [:]
        for definition in SubjectIcons.all {
            var tokens = Set(definition.aliases.map { SubjectMapper.subjectLookupToken($0) })
            tokens.insert(SubjectMapper.subjectLookupToken(definition.canonicalKey))

            for token in tokens {
                XCTAssertFalse(token.isEmpty, "\(definition.canonicalKey) has an empty alias")
                if let existing = owner[token] {
                    XCTAssertEqual(
                        existing,
                        definition.canonicalKey,
                        "alias '\(token)' is claimed by both \(existing) and \(definition.canonicalKey)"
                    )
                }
                owner[token] = definition.canonicalKey
            }
        }
    }

    /// [I] Every IB group, the DP core and the school block group are represented.
    func testEveryGroupIsPopulated() {
        let populated = Set(SubjectIcons.all.map(\.group))
        for group in IBSubjectGroup.allCases {
            XCTAssertTrue(populated.contains(group), "\(group.rawValue) has no subjects")
        }

        XCTAssertEqual(IBSubjectGroup.languageAndLiterature.groupNumber, 1)
        XCTAssertEqual(IBSubjectGroup.languageAcquisition.groupNumber, 2)
        XCTAssertEqual(IBSubjectGroup.individualsAndSocieties.groupNumber, 3)
        XCTAssertEqual(IBSubjectGroup.sciences.groupNumber, 4)
        XCTAssertEqual(IBSubjectGroup.mathematics.groupNumber, 5)
        XCTAssertEqual(IBSubjectGroup.arts.groupNumber, 6)
        XCTAssertNil(IBSubjectGroup.core.groupNumber)
        XCTAssertNil(IBSubjectGroup.schoolProgramme.groupNumber)

        XCTAssertEqual(SubjectIcons.subjects(in: .mathematics).map(\.canonicalKey), ["mathematics"])
        XCTAssertEqual(SubjectMapper.subjectGroup(for: "Biology SL"), .sciences)
        XCTAssertEqual(SubjectMapper.subjectGroup(for: "TOK"), .core)
        XCTAssertNil(SubjectMapper.subjectGroup(for: "Underwater Basket Weaving HL"))
    }

    // MARK: - Machinery kept from the original

    /// [I] canonical key -> user override -> catalogue default, in that order.
    func testUserOverrideBeatsCatalogueDefault() {
        let override = SubjectMapper.ResolvedLessonMapping(
            mappingId: UUID(),
            canonicalKey: "biology",
            defaultName: "Biology",
            defaultColorHue: 108,
            defaultIcon: "leaf.fill",
            displayName: "Bio with Marit",
            displayColorHue: 12,
            displayIcon: "hare.fill"
        )
        SubjectMapper.mappingProvider = { key -> SubjectMapper.ResolvedLessonMapping? in
            key == "biology" ? override : nil
        }

        XCTAssertEqual(SubjectMapper.displayName(for: "Biology SL"), "Bio with Marit")
        XCTAssertEqual(SubjectMapper.colorHue(for: "Biology HL"), 12)
        XCTAssertEqual(SubjectMapper.iconName(for: "DP1 Biology HL"), "hare.fill")

        // The catalogue default is untouched underneath the override.
        XCTAssertEqual(SubjectMapper.defaultColorHue(for: "biology"), 108)
        XCTAssertEqual(SubjectMapper.defaultName(for: "biology"), "Biology")

        // Chemistry has no override, so it still resolves from the catalogue.
        XCTAssertEqual(SubjectMapper.displayName(for: "Chemistry HL"), "Chemistry")
    }

    /// [I] Colour rendering: S 0.62 / V 0.88, hue 215 for unmapped, wrapping hues.
    func testColourConstantsAndHueWrapping() {
        XCTAssertEqual(SubjectMapper.unmappedHue, 215)
        XCTAssertEqual(SubjectMapper.subjectSaturation, 0.62, accuracy: 0.0001)
        XCTAssertEqual(SubjectMapper.subjectBrightness, 0.88, accuracy: 0.0001)

        XCTAssertEqual(SubjectMapper.color(hue: 108), SubjectMapper.color(hue: 468))
        XCTAssertEqual(SubjectMapper.color(hue: -1), SubjectMapper.color(hue: 359))
        XCTAssertEqual(SubjectMapper.defaultColor(for: "biology"), SubjectMapper.color(hue: 108))
    }

    /// [I] The tokeniser must be idempotent, or feeding a canonical key back through the
    /// mapper would drift.
    func testLookupTokenIsIdempotent() {
        let titles = [
            "Mathematics: Analysis and Approaches HL",
            "English A: Language and Literature SL",
            "Spanish ab initio",
            "Sports, Exercise and Health Science SL",
            "Underwater Basket Weaving HL"
        ]

        for title in titles {
            let once = SubjectMapper.subjectLookupToken(title)
            XCTAssertEqual(SubjectMapper.subjectLookupToken(once), once, "\(title)")
        }

        for definition in SubjectIcons.all {
            let key = definition.canonicalKey
            XCTAssertEqual(SubjectMapper.canonicalKey(for: key), key, "round trip of \(key)")
        }
    }

    /// [I] `normalizedHold` and `extractSubjectCode` are still what SettingsStore calls.
    func testLegacyHelpersStillBehave() {
        XCTAssertEqual(SubjectMapper.normalizedHold("  Visual   Arts  HL "), "Visual Arts HL")
        XCTAssertEqual(SubjectMapper.extractSubjectCode(from: "Visual Arts HL"), "visual-arts")
        XCTAssertEqual(SubjectMapper.extractSubjectCode(from: "No-Classes"), "No-Classes")

        XCTAssertEqual(SubjectMapper.defaultName(for: "tok"), "Theory of Knowledge")
        XCTAssertEqual(SubjectMapper.defaultName(for: "not-a-subject", fallback: "Fallback"), "Fallback")
        XCTAssertTrue(SubjectMapper.knownSubjects.contains { $0.code == "extended-essay" })
    }
}
