package dk.betterlectio.android.feature.settings

import java.text.Normalizer
import java.util.Locale

/**
 * Maps Lectio holds to canonical lesson-mapping keys and resolved display metadata.
 * Port of iOS `SubjectMapper` / extension `hold-mapping.ts` normalization contract.
 *
 * Call sites must resolve raw holds like `1x MA` through [canonicalKey] before
 * looking up Supabase overrides — never key by the raw string alone.
 */
object SubjectMapper {

    data class SubjectMetadata(
        val defaultName: String,
        val iconKey: String,
        val defaultHue: Int,
        val aliases: Set<String>,
    )

    /** Optional live mapping lookup (wired by [SettingsStore]). */
    @Volatile
    var mappingProvider: ((String) -> ResolvedLessonMapping?)? = null

    /** Optional subject list for settings (wired by [SettingsStore]). */
    @Volatile
    var subjectInfoProvider: (() -> List<SubjectInfo>)? = null

    private val locale = Locale.forLanguageTag("da-DK")

    // Class-code regex constants ported from `lib/class-name.ts`.
    // Covers `1x`, `2hf`, `2zq`, `1.4`, `L2d`, `S2x`, `IB1`, `10.st.kl.2`,
    // hyphenated `3hx-u`, and named classes like `BShannon` / `Epsilon`.
    private const val CLASS_LETTER = "A-Za-zÆØÅæøå"
    private const val CLASS_SEPARATOR = "[._/-]"
    private val classSuffix = "(?:[${CLASS_LETTER}0-9]{1,2}|$CLASS_SEPARATOR[${CLASS_LETTER}0-9]+)"
    private val classCodeBody = "(?:[${CLASS_LETTER}]+\\d+|\\d+)"
    private val namedClass = "[${CLASS_LETTER}]+"
    private val classCode =
        "(?:[${CLASS_LETTER}]+\\d+(?:$classSuffix)*|$classCodeBody(?:$classSuffix)+|$namedClass)"
    private val classPrefixPattern = Regex("^$classCode$", RegexOption.IGNORE_CASE)

    private val ignoredHoldPatterns: List<Regex> = listOf(
        Regex("^alle\\b", RegexOption.IGNORE_CASE),
        Regex("\\belever\\b", RegexOption.IGNORE_CASE),
        Regex("\\blærere\\b", RegexOption.IGNORE_CASE),
        Regex("\\bkost(?:elever|tutor|lærere|skole)?\\b", RegexOption.IGNORE_CASE),
        Regex("\\blæsekursus\\b", RegexOption.IGNORE_CASE),
        Regex("\\budvalg\\b", RegexOption.IGNORE_CASE),
        Regex("\\bråd\\b", RegexOption.IGNORE_CASE),
        Regex("\\bguider\\b", RegexOption.IGNORE_CASE),
        Regex("\\bbuddies\\b", RegexOption.IGNORE_CASE),
        Regex("\\bfrivillig(?:hedskæmpere)?\\b", RegexOption.IGNORE_CASE),
        Regex("\\byoga\\b", RegexOption.IGNORE_CASE),
        Regex("\\bintro\\b", RegexOption.IGNORE_CASE),
        Regex("\\bledelsen\\b", RegexOption.IGNORE_CASE),
        Regex("\\bsamarbejdsudvalg\\b", RegexOption.IGNORE_CASE),
        Regex("\\balumneråd\\b", RegexOption.IGNORE_CASE),
        Regex("\\bskolerådet\\b", RegexOption.IGNORE_CASE),
        Regex("\\bkor\\b", RegexOption.IGNORE_CASE),
        Regex("\\bai-udvalg\\b", RegexOption.IGNORE_CASE),
    )

    private val stripLevelSuffix = Regex("-[a-zæøå]+$", RegexOption.IGNORE_CASE)
    private val edgeNonAlnum = Regex("(^[^\\p{L}\\p{N}]+|[^\\p{L}\\p{N}]+$)")
    private val multiSpace = Regex("\\s+")

    /**
     * Built-in subject dictionary. Icon keys map to Compose ImageVectors in UI.
     * Hues match iOS SubjectMapper defaults.
     */
    val metadataByCanonicalKey: Map<String, SubjectMetadata> = mapOf(
        "ap" to meta("Almen sprogforståelse", "globe", 48, "ap", "almen sprogforstaaelse", "almen sprogforståelse"),
        "as" to meta("Astronomi", "sparkles", 260, "as", "astronomi"),
        "at" to meta("AT", "doc", 215, "at", "almen studieforberedelse"),
        "bi" to meta("Biologi", "science", 98, "bi", "bio", "biologi"),
        "bk" to meta("Billedkunst", "brush", 355, "bk", "billedkunst"),
        "bro" to meta("Brobygning", "link", 155, "bro", "brobygning"),
        "bt" to meta("Bioteknologi", "science", 160, "bt", "bioteknologi"),
        "da" to meta("Dansk", "book", 342, "da", "dan", "dansk"),
        "de" to meta("Design", "brush", 342, "de", "design"),
        "dho" to meta("DHO", "doc", 28, "dho"),
        "dr" to meta("Dramatik", "theater", 25, "dr", "dramatik"),
        "en" to meta("Engelsk", "translate", 215, "en", "eng", "engelsk"),
        "er" to meta("Erhvervsøkonomi", "chart", 65, "er", "erhvervsoekonomi", "erhvervsøkonomi"),
        "eø" to meta("Erhvervsøkonomi", "chart", 65, "eø", "eoe", "eo", "erhvervsoekonomi"),
        "ff" to meta("Forsøgsfag", "bulb", 52, "ff", "forsøgsfag", "forsoegsfag", "fælles fagligt", "faelles fagligt"),
        "fi" to meta("Filosofi", "chat", 272, "fi", "filosofi"),
        "fr" to meta("Fransk", "book", 330, "fr", "frb", "frf", "fransk"),
        "fy" to meta("Fysik", "science", 266, "fy", "fys", "fysik"),
        "ge" to meta("Geografi", "globe", 95, "ge", "geo", "geografi"),
        "hi" to meta("Historie", "history", 24, "hi", "his", "historie"),
        "id" to meta("Idræt", "sport", 188, "id", "idræt", "idraet"),
        "if" to meta("Idéhistorie", "history", 300, "if", "idehistorie", "idéhistorie", "ide-historie"),
        "ih" to meta("Idéhistorie", "history", 300, "ih"),
        "it" to meta("Informatik", "computer", 248, "it", "informatik"),
        "inf" to meta("Informatik", "computer", 248, "inf"),
        "ke" to meta("Kemi", "science", 138, "ke", "kem", "kemi"),
        "kit" to meta("Kommunikation/IT", "chat", 305, "kit", "kommunikation/it", "kommunikation it"),
        "ks" to meta("Kultur- og samfundsfag", "building", 186, "ks", "kultur- og samfundsfag", "kultur og samfundsfag"),
        "kt" to meta("Klassens Time", "people", 170, "kt", "klassens time"),
        "la" to meta("Latin", "book", 358, "la", "latin"),
        "ma" to meta("Matematik", "functions", 238, "ma", "mat", "matematik"),
        "me" to meta("Mediefag", "film", 318, "me", "mediefag"),
        "mu" to meta("Musik", "music", 322, "mu", "musik"),
        "ng" to meta("Naturgeografi", "globe", 88, "ng", "naturgeografi"),
        "nv" to meta("Naturvidenskab", "science", 145, "nv", "naturvidenskab", "nat"),
        "ol" to meta("Oldtidskundskab", "building", 40, "ol", "oldtidskundskab"),
        "pro" to meta("Programmering", "computer", 242, "pro", "programmering"),
        "ps" to meta("Psykologi", "chat", 312, "ps", "psykologi"),
        "pu" to meta("Produktudvikling", "computer", 22, "pu", "produktudvikling"),
        "re" to meta("Religion", "book", 285, "re", "religion"),
        "sa" to meta("Samfundsfag", "building", 4, "sa", "sam", "samf", "samfundsfag"),
        "skr" to meta("Skriftlige opgaver", "doc", 12, "skr", "skriftlige opgaver"),
        "sp" to meta("Spansk", "book", 15, "sp", "spansk"),
        "sro" to meta("SRO", "doc", 32, "sro", "studieretningsopgave"),
        "srp" to meta("SRP", "doc", 32, "srp", "studieretningsprojekt"),
        "ss" to meta("Statistik", "chart", 225, "ss", "statistik"),
        "st" to meta("Studievejledning", "people", 286, "st", "studievejledning"),
        "tek" to meta("Teknologi", "computer", 205, "tek"),
        "ti" to meta("Teknologi", "computer", 205, "ti", "teknologi"),
        "tk" to meta("Teknikfag", "computer", 210, "tk", "teknikfag"),
        "ty" to meta("Tysk", "translate", 30, "ty", "tys", "tysk"),
        "vø" to meta("Virksomhedsøkonomi", "chart", 72, "vø", "voe", "vo", "virksomhedsoekonomi", "virksomhedsøkonomi"),
    )

    private val aliasToCanonicalKey: Map<String, String> = buildMap {
        for ((canonicalKey, metadata) in metadataByCanonicalKey) {
            put(canonicalKey, canonicalKey)
            for (alias in metadata.aliases) {
                put(normalizedLookupToken(alias), canonicalKey)
            }
        }
    }

    /** Curated hue chips for the subject color picker (extension CURATED_HUES). */
    val CURATED_HUES: List<Int> = listOf(
        0, 8, 15, 22, 28, 34, 40, 48, 52, 65, 72, 80, 88, 95, 108, 118, 132, 145,
        160, 172, 175, 186, 188, 200, 205, 210, 218, 225, 235, 242, 248, 258, 272,
        280, 286, 295, 300, 305, 312, 318, 330, 336, 342, 355,
    )

    private const val UNMAPPED_HUE = 215

    fun displayName(forSubject: String): String {
        val fallback = normalizedHold(forSubject)
        val key = canonicalKey(forSubject) ?: return if (fallback.isEmpty()) forSubject else fallback
        mappingProvider?.invoke(key)?.let { return it.displayName }
        return defaultName(key, fallback)
    }

    fun defaultName(subjectCode: String, fallback: String? = null): String {
        val lookup = normalizedLookupToken(subjectCode)
        val key = aliasToCanonicalKey[lookup]
        if (key != null) {
            metadataByCanonicalKey[key]?.let { return it.defaultName }
        }
        return fallback ?: normalizedHold(subjectCode)
    }

    fun isKnownSubject(subject: String): Boolean {
        val key = canonicalKey(subject) ?: return false
        return mappingProvider?.invoke(key) != null || metadataByCanonicalKey.containsKey(key)
    }

    fun iconKey(forSubject: String): String {
        val key = canonicalKey(forSubject) ?: return "school"
        mappingProvider?.invoke(key)?.let { resolved ->
            return resolved.displayIcon
                ?: resolved.defaultIcon
                ?: defaultIconKey(key)
        }
        return defaultIconKey(key)
    }

    fun colorHue(forSubject: String): Int {
        val key = canonicalKey(forSubject) ?: return UNMAPPED_HUE
        mappingProvider?.invoke(key)?.let { return it.displayColorHue }
        return defaultColorHue(key)
    }

    fun defaultColorHue(subjectCode: String): Int {
        val lookup = normalizedLookupToken(subjectCode)
        val key = aliasToCanonicalKey[lookup] ?: canonicalKey(subjectCode)
        if (key != null) {
            metadataByCanonicalKey[key]?.let { return it.defaultHue }
        }
        return UNMAPPED_HUE
    }

    val knownSubjects: List<SubjectInfo>
        get() = metadataByCanonicalKey.keys.sorted().map { key ->
            SubjectInfo(code = key, name = metadataByCanonicalKey[key]!!.defaultName)
        }

    fun allSubjects(including: Collection<String> = emptyList()): List<SubjectInfo> {
        val byCode = (subjectInfoProvider?.invoke() ?: knownSubjects)
            .associateBy { it.code }
            .toMutableMap()

        for (title in including) {
            val key = canonicalKey(title) ?: continue
            if (byCode.containsKey(key)) continue
            val name = mappingProvider?.invoke(key)?.displayName
                ?: defaultName(key, normalizedHold(title))
            byCode[key] = SubjectInfo(code = key, name = name)
        }

        return byCode.values.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.name })
    }

    /**
     * Shared canonical key used by lesson-mapping v2, or null for unknown/ignored holds.
     */
    fun canonicalKey(subject: String): String? {
        val normalized = normalizedHold(subject)
        if (normalized.isEmpty()) return null
        if (isIgnoredHold(normalized)) return null

        resolveCanonicalCandidate(normalized)?.let { return it }

        val parts = normalized.split(" ").filter { it.isNotEmpty() }
        if (parts.size <= 1) return null

        val prefix = normalizeClassCode(parts[0])
        if (!classPrefixPattern.matches(prefix)) return null

        val remainder = parts.drop(1).joinToString(" ")
        return resolveCanonicalCandidate(remainder)
    }

    fun extractSubjectCode(subject: String): String =
        canonicalKey(subject) ?: normalizedHold(subject)

    fun normalizedHold(subject: String): String =
        subject.trim().replace(multiSpace, " ")

    private fun resolveCanonicalCandidate(candidate: String): String? {
        val normalizedCandidate = normalizedLookupToken(candidate)
        aliasToCanonicalKey[normalizedCandidate]?.let { return it }

        val stripped = stripSubjectLevelSuffix(normalizedCandidate)
        if (stripped != normalizedCandidate) {
            aliasToCanonicalKey[stripped]?.let { return it }
        }

        val tokens = normalizedCandidate.split(" ").filter { it.isNotEmpty() }
        val first = tokens.firstOrNull() ?: return null
        val firstStripped = stripSubjectLevelSuffix(first)
        return aliasToCanonicalKey[first] ?: aliasToCanonicalKey[firstStripped]
    }

    private fun normalizeClassCode(value: String): String {
        val trimmed = value.trim()
        if (!trimmed.contains('_')) return trimmed
        val tail = trimmed.substringAfterLast('_')
        return if (classPrefixPattern.matches(tail)) tail else trimmed
    }

    private fun isIgnoredHold(holdCode: String): Boolean {
        val normalized = normalizedHold(holdCode)
        return ignoredHoldPatterns.any { it.containsMatchIn(normalized) }
    }

    private fun stripSubjectLevelSuffix(token: String): String =
        token.replace(stripLevelSuffix, "")

    private fun defaultIconKey(canonicalKey: String): String =
        metadataByCanonicalKey[canonicalKey]?.iconKey ?: "school"

    /**
     * Lookup token: whitespace-normalized, da-DK lowercased, diacritics stripped,
     * leading/trailing non-alphanumeric removed.
     */
    fun normalizedLookupToken(value: String): String {
        val base = normalizedHold(value)
            .lowercase(locale)
            .replace(edgeNonAlnum, "")
        return stripDiacritics(base)
    }

    private fun stripDiacritics(value: String): String {
        // Keep æ/ø/å as letters that may appear in aliases; strip combining marks only.
        val nfd = Normalizer.normalize(value, Normalizer.Form.NFD)
        return nfd.replace("\\p{M}+".toRegex(), "")
    }

    private fun meta(
        defaultName: String,
        iconKey: String,
        defaultHue: Int,
        vararg aliases: String,
    ): SubjectMetadata = SubjectMetadata(
        defaultName = defaultName,
        iconKey = iconKey,
        defaultHue = defaultHue,
        aliases = aliases.toSet(),
    )

    fun normalizeHue(hue: Int): Int = ((hue % 360) + 360) % 360
}
