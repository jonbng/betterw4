//
//  SubjectIcons.swift
//  BetterW4
//
//  The IB Diploma Programme subject catalogue: canonical key -> English display name,
//  subject group, hue and SF Symbol. `SubjectMapper` owns the matching machinery;
//  this file owns nothing but the vocabulary.
//
//  EVIDENCE — read this before trusting any entry here:
//
//    [I] EVERY entry in this file is SYNTHESIZED. No W4 lesson block, timetable period,
//        class list or subject page has ever been captured, so we have never seen the
//        exact string UWCRCN W4 prints for a subject. The names below come from the
//        published IB Diploma Programme subject list, not from W4.
//
//    Consequences, which the machinery in `SubjectMapper` is built around:
//      * A miss is normal and must be cheap: unknown subjects keep their own title and
//        get a stable hash-derived hue, never a wrong name.
//      * Aliases are generous on purpose. A false positive costs a slightly-off colour;
//        a false negative costs nothing at all.
//      * Hues are grouped into per-IB-group bands so that a subject that misses the
//        catalogue is visibly "not in a group" rather than silently mis-coloured.
//
//  Hue bands (degrees, rendered at S 0.62 / V 0.88 by `SubjectMapper.color(hue:)`):
//
//    Group 1  Studies in Language and Literature   336 - 358   rose
//    Group 2  Language Acquisition                  10 -  40   orange
//    Group 3  Individuals and Societies             46 -  80   gold
//    Group 4  Sciences                             100 - 152   green
//    Group 5  Mathematics                          228 - 252   indigo
//    Group 6  The Arts                             296 - 326   magenta
//    DP core  TOK / EE / CAS                       262 - 288   violet
//    School   non-IB timetable regulars            172 - 200   teal
//    (unmapped subjects use hue 215, which sits in none of the bands)
//

import Foundation

/// One of the six IB Diploma subject groups, the DP core, or the small set of non-IB
/// blocks a UWCRCN timetable also carries (Learning Support, University Guidance, EA).
enum IBSubjectGroup: String, CaseIterable, Codable, Sendable {
    case languageAndLiterature
    case languageAcquisition
    case individualsAndSocieties
    case sciences
    case mathematics
    case arts
    case core
    case schoolProgramme

    /// English label for the group, as the IB writes it.
    var displayName: String {
        switch self {
        case .languageAndLiterature: return "Studies in Language and Literature"
        case .languageAcquisition: return "Language Acquisition"
        case .individualsAndSocieties: return "Individuals and Societies"
        case .sciences: return "Sciences"
        case .mathematics: return "Mathematics"
        case .arts: return "The Arts"
        case .core: return "DP Core"
        case .schoolProgramme: return "School Programme"
        }
    }

    /// 1...6 for the six IB subject groups; `nil` for the core and for school blocks.
    var groupNumber: Int? {
        switch self {
        case .languageAndLiterature: return 1
        case .languageAcquisition: return 2
        case .individualsAndSocieties: return 3
        case .sciences: return 4
        case .mathematics: return 5
        case .arts: return 6
        case .core, .schoolProgramme: return nil
        }
    }

    /// Centre of the group's hue band. Individual subjects sit within the band.
    var baseHue: Int {
        switch self {
        case .languageAndLiterature: return 348
        case .languageAcquisition: return 24
        case .individualsAndSocieties: return 62
        case .sciences: return 126
        case .mathematics: return 238
        case .arts: return 310
        case .core: return 274
        case .schoolProgramme: return 186
        }
    }

    /// Fallback SF Symbol for a subject in this group that has no symbol of its own.
    var symbolName: String {
        switch self {
        case .languageAndLiterature: return "text.book.closed.fill"
        case .languageAcquisition: return "globe.europe.africa.fill"
        case .individualsAndSocieties: return "building.columns.fill"
        case .sciences: return "atom"
        case .mathematics: return "function"
        case .arts: return "paintpalette.fill"
        case .core: return "lightbulb.fill"
        case .schoolProgramme: return "calendar"
        }
    }
}

/// One catalogue entry. `canonicalKey` is the stable identity a user override is stored
/// against, so it must never change once shipped.
struct IBSubjectDefinition: Identifiable, Hashable, Sendable {
    /// Lowercase, hyphenated, ASCII. The persistence key for lesson mappings.
    let canonicalKey: String
    /// English name shown when the user has not renamed the subject.
    let displayName: String
    let group: IBSubjectGroup
    /// 0...359.
    let hue: Int
    let symbolName: String
    /// Extra spellings that resolve to this entry. Matched after normalisation, so they
    /// are written lowercase, unpunctuated and WITHOUT an HL / SL / ab initio marker.
    let aliases: Set<String>

    var id: String { canonicalKey }
}

/// The IB subject catalogue. Pure data; no I/O, no clock, no state.
enum SubjectIcons {

    /// Used when a subject resolves to nothing at all.
    static let defaultSymbolName = "book.fill"

    // MARK: - Group 1 — Studies in Language and Literature

    static let languageAndLiterature: [IBSubjectDefinition] = [
        IBSubjectDefinition(
            canonicalKey: "norwegian-a",
            displayName: "Norwegian A",
            group: .languageAndLiterature,
            hue: 336,
            symbolName: "text.book.closed.fill",
            aliases: ["norwegian a", "norwegian"]
        ),
        IBSubjectDefinition(
            canonicalKey: "literature-and-performance",
            displayName: "Literature and Performance",
            group: .languageAndLiterature,
            hue: 342,
            symbolName: "theatermasks.fill",
            aliases: ["literature and performance"]
        ),
        IBSubjectDefinition(
            canonicalKey: "english-a",
            displayName: "English A",
            group: .languageAndLiterature,
            hue: 350,
            symbolName: "text.book.closed.fill",
            aliases: [
                "english a",
                "english",
                "english a literature",
                "english a language and literature",
                "english language and literature",
                "english literature",
                "language and literature"
            ]
        ),
        IBSubjectDefinition(
            canonicalKey: "self-taught-a",
            displayName: "Self-Taught Language A",
            group: .languageAndLiterature,
            hue: 358,
            symbolName: "character.book.closed.fill",
            aliases: [
                "self taught language a",
                "self taught",
                "school supported self taught",
                "ssst"
            ]
        )
    ]

    // MARK: - Group 2 — Language Acquisition

    static let languageAcquisition: [IBSubjectDefinition] = [
        IBSubjectDefinition(
            canonicalKey: "spanish",
            displayName: "Spanish",
            group: .languageAcquisition,
            hue: 10,
            symbolName: "globe.americas.fill",
            aliases: ["spanish", "spanish b"]
        ),
        IBSubjectDefinition(
            canonicalKey: "french",
            displayName: "French",
            group: .languageAcquisition,
            hue: 14,
            symbolName: "globe.europe.africa.fill",
            aliases: ["french", "french b"]
        ),
        IBSubjectDefinition(
            canonicalKey: "german",
            displayName: "German",
            group: .languageAcquisition,
            hue: 18,
            symbolName: "globe.europe.africa.fill",
            aliases: ["german", "german b"]
        ),
        IBSubjectDefinition(
            canonicalKey: "mandarin",
            displayName: "Mandarin",
            group: .languageAcquisition,
            hue: 22,
            symbolName: "globe.asia.australia.fill",
            aliases: ["mandarin", "mandarin b", "mandarin chinese", "chinese", "chinese b"]
        ),
        IBSubjectDefinition(
            canonicalKey: "arabic",
            displayName: "Arabic",
            group: .languageAcquisition,
            hue: 26,
            symbolName: "globe.asia.australia.fill",
            aliases: ["arabic", "arabic b"]
        ),
        IBSubjectDefinition(
            canonicalKey: "russian",
            displayName: "Russian",
            group: .languageAcquisition,
            hue: 30,
            symbolName: "globe.europe.africa.fill",
            aliases: ["russian", "russian b"]
        ),
        IBSubjectDefinition(
            canonicalKey: "norwegian-b",
            displayName: "Norwegian B",
            group: .languageAcquisition,
            hue: 34,
            symbolName: "globe.europe.africa.fill",
            aliases: ["norwegian b"]
        ),
        IBSubjectDefinition(
            canonicalKey: "english-b",
            displayName: "English B",
            group: .languageAcquisition,
            hue: 40,
            symbolName: "character.bubble.fill",
            aliases: ["english b"]
        )
    ]

    // MARK: - Group 3 — Individuals and Societies

    static let individualsAndSocieties: [IBSubjectDefinition] = [
        IBSubjectDefinition(
            canonicalKey: "history",
            displayName: "History",
            group: .individualsAndSocieties,
            hue: 46,
            symbolName: "building.columns.fill",
            aliases: ["history"]
        ),
        IBSubjectDefinition(
            canonicalKey: "geography",
            displayName: "Geography",
            group: .individualsAndSocieties,
            hue: 50,
            symbolName: "map.fill",
            aliases: ["geography", "geo"]
        ),
        IBSubjectDefinition(
            canonicalKey: "economics",
            displayName: "Economics",
            group: .individualsAndSocieties,
            hue: 54,
            symbolName: "chart.line.uptrend.xyaxis",
            aliases: ["economics", "econ"]
        ),
        IBSubjectDefinition(
            canonicalKey: "psychology",
            displayName: "Psychology",
            group: .individualsAndSocieties,
            hue: 58,
            symbolName: "brain.head.profile",
            aliases: ["psychology", "psych"]
        ),
        IBSubjectDefinition(
            canonicalKey: "global-politics",
            displayName: "Global Politics",
            group: .individualsAndSocieties,
            hue: 62,
            symbolName: "flag.fill",
            aliases: ["global politics", "politics"]
        ),
        IBSubjectDefinition(
            canonicalKey: "philosophy",
            displayName: "Philosophy",
            group: .individualsAndSocieties,
            hue: 66,
            symbolName: "bubble.left.and.bubble.right.fill",
            aliases: ["philosophy"]
        ),
        IBSubjectDefinition(
            canonicalKey: "social-and-cultural-anthropology",
            displayName: "Social and Cultural Anthropology",
            group: .individualsAndSocieties,
            hue: 70,
            symbolName: "person.3.fill",
            aliases: ["social and cultural anthropology", "anthropology", "socult"]
        ),
        IBSubjectDefinition(
            canonicalKey: "business-management",
            displayName: "Business Management",
            group: .individualsAndSocieties,
            hue: 74,
            symbolName: "briefcase.fill",
            aliases: ["business management", "business and management", "business"]
        ),
        IBSubjectDefinition(
            canonicalKey: "world-religions",
            displayName: "World Religions",
            group: .individualsAndSocieties,
            hue: 78,
            symbolName: "book.closed.fill",
            aliases: ["world religions", "religion"]
        ),
        IBSubjectDefinition(
            canonicalKey: "digital-society",
            displayName: "Digital Society",
            group: .individualsAndSocieties,
            hue: 80,
            symbolName: "desktopcomputer",
            aliases: [
                "digital society",
                "itgs",
                "information technology in a global society"
            ]
        )
    ]

    // MARK: - Group 4 — Sciences

    static let sciences: [IBSubjectDefinition] = [
        IBSubjectDefinition(
            canonicalKey: "environmental-systems-and-societies",
            displayName: "Environmental Systems and Societies",
            group: .sciences,
            hue: 100,
            symbolName: "globe.europe.africa.fill",
            aliases: [
                "environmental systems and societies",
                "environmental systems",
                "ess"
            ]
        ),
        IBSubjectDefinition(
            canonicalKey: "biology",
            displayName: "Biology",
            group: .sciences,
            hue: 108,
            symbolName: "leaf.fill",
            aliases: ["biology", "bio"]
        ),
        IBSubjectDefinition(
            canonicalKey: "chemistry",
            displayName: "Chemistry",
            group: .sciences,
            hue: 116,
            symbolName: "flask.fill",
            aliases: ["chemistry", "chem"]
        ),
        IBSubjectDefinition(
            canonicalKey: "physics",
            displayName: "Physics",
            group: .sciences,
            hue: 124,
            symbolName: "atom",
            aliases: ["physics"]
        ),
        IBSubjectDefinition(
            canonicalKey: "computer-science",
            displayName: "Computer Science",
            group: .sciences,
            hue: 132,
            symbolName: "chevron.left.forwardslash.chevron.right",
            aliases: ["computer science", "compsci", "cs"]
        ),
        IBSubjectDefinition(
            canonicalKey: "design-technology",
            displayName: "Design Technology",
            group: .sciences,
            hue: 140,
            symbolName: "wrench.and.screwdriver.fill",
            aliases: ["design technology", "design and technology"]
        ),
        IBSubjectDefinition(
            canonicalKey: "sports-exercise-and-health-science",
            displayName: "Sports, Exercise and Health Science",
            group: .sciences,
            hue: 148,
            symbolName: "figure.run",
            aliases: [
                "sports exercise and health science",
                "sport exercise and health science",
                "sehs"
            ]
        )
    ]

    // MARK: - Group 5 — Mathematics

    // One entry on purpose: "Mathematics HL", "Mathematics SL",
    // "Mathematics: Analysis and Approaches HL" and
    // "Mathematics: Applications and Interpretation SL" must share one colour.
    static let mathematics: [IBSubjectDefinition] = [
        IBSubjectDefinition(
            canonicalKey: "mathematics",
            displayName: "Mathematics",
            group: .mathematics,
            hue: 238,
            symbolName: "function",
            aliases: [
                "mathematics",
                "maths",
                "math",
                "mathematics analysis and approaches",
                "mathematics applications and interpretation",
                "analysis and approaches",
                "applications and interpretation",
                "further mathematics",
                "mathematical studies"
            ]
        )
    ]

    // MARK: - Group 6 — The Arts

    static let arts: [IBSubjectDefinition] = [
        IBSubjectDefinition(
            canonicalKey: "dance",
            displayName: "Dance",
            group: .arts,
            hue: 296,
            symbolName: "figure.dance",
            aliases: ["dance"]
        ),
        IBSubjectDefinition(
            canonicalKey: "visual-arts",
            displayName: "Visual Arts",
            group: .arts,
            hue: 302,
            symbolName: "paintpalette.fill",
            aliases: ["visual arts", "visual art", "art"]
        ),
        IBSubjectDefinition(
            canonicalKey: "music",
            displayName: "Music",
            group: .arts,
            hue: 310,
            symbolName: "music.note",
            aliases: ["music"]
        ),
        IBSubjectDefinition(
            canonicalKey: "theatre",
            displayName: "Theatre",
            group: .arts,
            hue: 318,
            symbolName: "theatermasks.fill",
            aliases: ["theatre", "theater"]
        ),
        IBSubjectDefinition(
            canonicalKey: "film",
            displayName: "Film",
            group: .arts,
            hue: 326,
            symbolName: "film.fill",
            aliases: ["film"]
        )
    ]

    // MARK: - DP core

    static let core: [IBSubjectDefinition] = [
        IBSubjectDefinition(
            canonicalKey: "tok",
            displayName: "Theory of Knowledge",
            group: .core,
            hue: 266,
            symbolName: "lightbulb.fill",
            aliases: ["tok", "theory of knowledge"]
        ),
        IBSubjectDefinition(
            canonicalKey: "extended-essay",
            displayName: "Extended Essay",
            group: .core,
            hue: 274,
            symbolName: "doc.text.fill",
            aliases: ["extended essay", "ee"]
        ),
        IBSubjectDefinition(
            canonicalKey: "cas",
            displayName: "CAS",
            group: .core,
            hue: 282,
            symbolName: "heart.circle.fill",
            aliases: ["cas", "creativity activity service", "creativity action service"]
        )
    ]

    // MARK: - Non-IB school blocks

    // [I] These three are the school-side blocks `inventory.md` names alongside the IB
    // subjects. Like everything else here, the exact strings are unverified.
    static let schoolProgramme: [IBSubjectDefinition] = [
        IBSubjectDefinition(
            canonicalKey: "learning-support",
            displayName: "Learning Support",
            group: .schoolProgramme,
            hue: 176,
            symbolName: "person.fill.questionmark",
            aliases: ["learning support", "study support"]
        ),
        IBSubjectDefinition(
            canonicalKey: "university-guidance",
            displayName: "University Guidance",
            group: .schoolProgramme,
            hue: 186,
            symbolName: "graduationcap.fill",
            aliases: [
                "university guidance",
                "university advising",
                "college counselling",
                "college counseling"
            ]
        ),
        IBSubjectDefinition(
            canonicalKey: "extra-academics",
            displayName: "Extra Academics",
            group: .schoolProgramme,
            hue: 196,
            symbolName: "figure.hiking",
            aliases: ["extra academics", "ea"]
        )
    ]

    // MARK: - Assembled catalogue

    /// Every catalogue entry, in IB group order.
    static let all: [IBSubjectDefinition] = {
        var result: [IBSubjectDefinition] = []
        result.append(contentsOf: languageAndLiterature)
        result.append(contentsOf: languageAcquisition)
        result.append(contentsOf: individualsAndSocieties)
        result.append(contentsOf: sciences)
        result.append(contentsOf: mathematics)
        result.append(contentsOf: arts)
        result.append(contentsOf: core)
        result.append(contentsOf: schoolProgramme)
        return result
    }()

    /// Catalogue indexed by canonical key.
    static let byCanonicalKey: [String: IBSubjectDefinition] = {
        var result: [String: IBSubjectDefinition] = [:]
        for definition in all {
            result[definition.canonicalKey] = definition
        }
        return result
    }()

    /// Entries belonging to one IB group, in catalogue order.
    static func subjects(in group: IBSubjectGroup) -> [IBSubjectDefinition] {
        all.filter { $0.group == group }
    }
}
