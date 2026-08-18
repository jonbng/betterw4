package dk.betterw4.android.feature.settings

/**
 * IB Diploma catalogue plus the W4-specific spellings captured from
 * `academics/classes/myclasses` and `div.period[title]`.
 *
 * Canonical keys are stable persistence identities and must not change once shipped.
 * Four-letter W4 suffixes (`MTAA`, `ECOX`, `LALI`, …) are aliases, not keys.
 */
object SubjectIcons {

    const val DEFAULT_ICON_KEY = "school"

    data class SubjectDefinition(
        val canonicalKey: String,
        val displayName: String,
        val iconKey: String,
        val hue: Int,
        val aliases: Set<String>,
    )

    private fun def(
        key: String,
        name: String,
        icon: String,
        hue: Int,
        vararg aliases: String,
    ) = SubjectDefinition(key, name, icon, hue, aliases.toSet())

    val all: List<SubjectDefinition> = listOf(
        // Group 1 — Language and Literature
        def(
            "norwegian-a", "Norwegian A", "book", 336,
            "norwegian a", "norwegian", "norwegian literature", "noli",
        ),
        def(
            "danish-a", "Danish Literature", "book", 340,
            "danish a", "danish", "danish literature", "dali",
        ),
        def(
            "literature-and-performance", "Literature and Performance", "theater", 342,
            "literature and performance",
        ),
        def(
            "spanish-a", "Spanish Literature", "book", 344,
            "spanish a", "spanish literature", "spli",
        ),
        def(
            "world-literature", "World Literature", "book", 348,
            "world literature", "wolx",
        ),
        def(
            "english-a", "English A", "book", 350,
            "english a", "english", "english a literature",
            "english a language and literature",
            "english language and literature",
            "english literature",
            "language and literature",
            "lali",
            "enli",
        ),
        def(
            "self-taught-a", "Self-Taught Language A", "book", 358,
            "self taught language a", "self taught",
            "school supported self taught", "ssst",
        ),

        // Group 2 — Language Acquisition
        def(
            "spanish", "Spanish", "translate", 10,
            "spanish", "spanish b", "spanish ab initio", "spab", "spbb",
        ),
        def(
            "french", "French", "translate", 14,
            "french", "french b", "french ab initio", "frab",
        ),
        def("german", "German", "translate", 18, "german", "german b"),
        def(
            "mandarin", "Mandarin", "globe", 22,
            "mandarin", "mandarin b", "mandarin chinese", "chinese", "chinese b",
        ),
        def("arabic", "Arabic", "translate", 26, "arabic", "arabic b"),
        def("russian", "Russian", "translate", 30, "russian", "russian b"),
        def("italian", "Italian", "translate", 32, "italian", "italian b"),
        def("norwegian-b", "Norwegian B", "translate", 34, "norwegian b"),
        def("english-b", "English B", "translate", 40, "english b", "engb"),

        // Group 3 — Individuals and Societies
        def("history", "History", "history", 46, "history", "hist"),
        def("geography", "Geography", "globe", 50, "geography", "geo"),
        def("economics", "Economics", "chart", 54, "economics", "econ", "ecox"),
        def("psychology", "Psychology", "chat", 58, "psychology", "psych", "psyc"),
        def(
            "global-politics", "Global Politics", "building", 62,
            "global politics", "politics", "glop",
        ),
        def("philosophy", "Philosophy", "chat", 66, "philosophy", "phix"),
        def(
            "social-and-cultural-anthropology", "Social and Cultural Anthropology", "people", 70,
            "social and cultural anthropology", "anthropology", "socult",
        ),
        def(
            "business-management", "Business Management", "chart", 74,
            "business management", "business and management", "business",
        ),
        def(
            "world-religions", "World Religions", "book", 78,
            "world religions", "religion",
        ),
        def(
            "digital-society", "Digital Society", "computer", 80,
            "digital society", "itgs",
            "information technology in a global society",
        ),
        def(
            "development-studies", "Development Studies", "globe", 76,
            "development studies",
        ),
        def("human-rights", "Human Rights", "building", 72, "human rights"),

        // Group 4 — Sciences
        def(
            "environmental-systems-and-societies",
            "Environmental Systems and Societies",
            "globe",
            100,
            "environmental systems and societies",
            "environmental systems",
            "ess",
            "enss",
        ),
        def("biology", "Biology", "science", 108, "biology", "bio", "biox"),
        def("chemistry", "Chemistry", "science", 116, "chemistry", "chem", "chex"),
        def("physics", "Physics", "science", 124, "physics", "phyx"),
        def(
            "computer-science", "Computer Science", "computer", 132,
            "computer science", "compsci", "cs",
        ),
        def(
            "design-technology", "Design Technology", "computer", 140,
            "design technology", "design and technology",
        ),
        def(
            "sports-exercise-and-health-science",
            "Sports, Exercise and Health Science",
            "sport",
            148,
            "sports exercise and health science",
            "sport exercise and health science",
            "sehs",
        ),

        // Group 5 — Mathematics (one colour for AA / AI / HL / SL)
        def(
            "mathematics", "Mathematics", "functions", 238,
            "mathematics", "maths", "math",
            "mathematics analysis and approaches",
            "mathematics applications and interpretation",
            "analysis and approaches",
            "applications and interpretation",
            "further mathematics",
            "mathematical studies",
            "mtaa",
            "mtai",
        ),

        // Group 6 — The Arts
        def("dance", "Dance", "sport", 296, "dance"),
        def(
            "visual-arts", "Visual Arts", "brush", 302,
            "visual arts", "visual art", "art", "vart",
        ),
        def("music", "Music", "music", 310, "music"),
        def("theatre", "Theatre", "theater", 318, "theatre", "theater", "theatre arts", "thex"),
        def("film", "Film", "film", 326, "film"),

        // DP core
        def("tok", "Theory of Knowledge", "bulb", 266, "tok", "theory of knowledge", "thok"),
        def("extended-essay", "Extended Essay", "doc", 274, "extended essay", "ee"),
        def(
            "cas", "CAS", "people", 282,
            "cas", "creativity activity service", "creativity action service",
        ),
        def(
            "core-meetings", "Core meetings", "people", 270,
            "core meetings", "core", "corex",
        ),

        // School programme
        def(
            "learning-support", "Learning Support", "people", 176,
            "learning support", "study support",
        ),
        def(
            "university-guidance", "University Guidance", "school", 186,
            "university guidance", "university advising",
            "college counselling", "college counseling",
        ),
        def(
            "extra-academics", "Extra Academics", "sport", 196,
            "extra academics", "ea",
        ),
        def(
            "nordic-languages", "Nordic Languages", "book", 338,
            "nordic languages",
        ),
        def(
            "advisor-group", "Advisor group", "people", 182,
            "advisor group", "advisory", "advisor",
        ),
    )

    val byCanonicalKey: Map<String, SubjectDefinition> =
        all.associateBy { it.canonicalKey }

    data class SubjectMeta(
        val canonicalKey: String,
        val defaultName: String,
        val iconKey: String,
    )

    fun fold(raw: String): String = SubjectMapper.subjectLookupToken(raw)

    fun iconKeyFor(title: String): String = SubjectMapper.iconKey(title)

    fun canonicalKeyFor(title: String): String? = SubjectMapper.canonicalKey(title)

    fun resolve(title: String): SubjectMeta? {
        val key = SubjectMapper.canonicalKey(title) ?: return null
        val meta = byCanonicalKey[key]
        return SubjectMeta(
            canonicalKey = key,
            defaultName = meta?.displayName ?: SubjectMapper.defaultName(key, fallback = title),
            iconKey = meta?.iconKey ?: SubjectMapper.iconKey(title),
        )
    }
}
