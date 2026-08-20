package dk.betterw4.android.feature.settings

import dk.betterw4.android.feature.schedule.W4ClassId
import java.text.Normalizer
import java.util.Locale

/**
 * Maps a W4 lesson title or class id to a canonical subject key and display metadata.
 *
 * Matching order: user override → catalogue (including W4 four-letter codes) → the
 * title's own normalised token, so an unknown subject still gets a stable colour.
 */
object SubjectMapper {

    data class SubjectMetadata(
        val defaultName: String,
        val iconKey: String,
        val defaultHue: Int,
        val aliases: Set<String>,
    )

    @Volatile
    var mappingProvider: ((String) -> ResolvedLessonMapping?)? = null

    @Volatile
    var subjectInfoProvider: (() -> List<SubjectInfo>)? = null

    private val lookupLocale = Locale.forLanguageTag("en-GB")

    private val levelWords = setOf("hl", "sl")
    private val levelPhrasePattern = Regex("""\b(?:ab initio|higher level|standard level)\b""")

    private val ignoredHoldPatterns: List<Regex> = listOf(
        Regex("""^no[\s._-]?classes$""", RegexOption.IGNORE_CASE),
        Regex("""^no\s+ea$""", RegexOption.IGNORE_CASE),
        Regex("""^weekend$""", RegexOption.IGNORE_CASE),
        Regex("""^n\s*/?\s*a$""", RegexOption.IGNORE_CASE),
        Regex("""^tba$""", RegexOption.IGNORE_CASE),
        Regex("""^tbd$""", RegexOption.IGNORE_CASE),
        Regex("""^[-–—]+$"""),
        Regex("""^breakfast$""", RegexOption.IGNORE_CASE),
        Regex("""^break$""", RegexOption.IGNORE_CASE),
        Regex("""^lunch$""", RegexOption.IGNORE_CASE),
        Regex("""^house cleaning$""", RegexOption.IGNORE_CASE),
        Regex("""^special programme$""", RegexOption.IGNORE_CASE),
    )

    private val classCodePattern = Regex(
        """^(?:ib|dp|diploma|year|grade)$|^[a-z]{0,3}\d{1,4}[a-z]?$""",
        RegexOption.IGNORE_CASE,
    )

    val metadataByCanonicalKey: Map<String, SubjectMetadata> =
        SubjectIcons.all.associate { def ->
            def.canonicalKey to SubjectMetadata(
                defaultName = def.displayName,
                iconKey = def.iconKey,
                defaultHue = def.hue,
                aliases = def.aliases,
            )
        }

    private val aliasToCanonicalKey: Map<String, String> = buildMap {
        for (def in SubjectIcons.all) {
            put(def.canonicalKey, def.canonicalKey)
            put(subjectLookupToken(def.canonicalKey), def.canonicalKey)
            for (alias in def.aliases) {
                put(subjectLookupToken(alias), def.canonicalKey)
            }
        }
        remove("")
    }

    val CURATED_HUES: List<Int> = listOf(
        0, 8, 15, 22, 28, 34, 40, 48, 52, 65, 72, 80, 88, 95, 108, 118, 132, 145,
        160, 172, 175, 186, 188, 200, 205, 210, 218, 225, 235, 242, 248, 258, 272,
        280, 286, 295, 300, 305, 312, 318, 330, 336, 342, 355,
    )

    const val UNMAPPED_HUE = 215

    fun displayName(forSubject: String): String {
        val fallback = normalizedHold(forSubject)
        val key = canonicalKey(forSubject) ?: return if (fallback.isEmpty()) forSubject else fallback
        mappingProvider?.invoke(key)?.let { return it.displayName }
        return defaultName(key, fallback)
    }

    fun defaultName(subjectCode: String, fallback: String? = null): String {
        definition(subjectCode)?.let { return it.displayName }
        return fallback ?: normalizedHold(subjectCode)
    }

    fun isKnownSubject(subject: String): Boolean {
        val key = canonicalKey(subject) ?: return false
        return mappingProvider?.invoke(key) != null || SubjectIcons.byCanonicalKey.containsKey(key)
    }

    fun iconKey(forSubject: String): String {
        val key = canonicalKey(forSubject) ?: return SubjectIcons.DEFAULT_ICON_KEY
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
        definition(subjectCode)?.let { return it.hue }
        val token = subjectLookupToken(subjectCode)
        if (token.isEmpty()) return UNMAPPED_HUE
        return stableHue(token)
    }

    fun definition(subjectCode: String): SubjectIcons.SubjectDefinition? {
        val raw = normalizedHold(subjectCode)
        aliasToCanonicalKey[raw]?.let { key ->
            SubjectIcons.byCanonicalKey[key]?.let { return it }
        }
        val token = subjectLookupToken(subjectCode)
        val key = resolveCanonicalCandidate(token) ?: return null
        return SubjectIcons.byCanonicalKey[key]
    }

    val knownSubjects: List<SubjectInfo>
        get() = SubjectIcons.all
            .map { SubjectInfo(code = it.canonicalKey, name = it.displayName) }
            .sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.name })

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
     * Stable identity a user override is stored against.
     *
     * `null` only for empty input or grid furniture (breakfast, weekend, …).
     * Unknown academic titles still get a key derived from the normalised name.
     */
    fun canonicalKey(subject: String): String? {
        val normalized = normalizedHold(subject)
        if (normalized.isEmpty()) return null
        if (isIgnoredHold(normalized)) return null

        val token = subjectLookupToken(normalized)
        if (token.isEmpty()) return null

        resolveCanonicalCandidate(token)?.let { return it }

        W4ClassId.parse(normalized)?.let { parsed ->
            resolveCanonicalCandidate(parsed.subjectCode.lowercase(lookupLocale))?.let { return it }
            return parsed.subjectCode.lowercase(lookupLocale)
        }

        val stripped = strippingLeadingClassCodes(token)
        if (stripped != token) {
            resolveCanonicalCandidate(stripped)?.let { return it }
        }

        return token
    }

    fun extractSubjectCode(subject: String): String =
        canonicalKey(subject) ?: normalizedHold(subject)

    fun normalizedHold(subject: String): String =
        subject.trim().replace(Regex("""\s+"""), " ")

    private fun resolveCanonicalCandidate(token: String): String? {
        if (token.isEmpty()) return null
        aliasToCanonicalKey[token]?.let { return it }

        val words = token.split(" ").filter { it.isNotEmpty() }.toMutableList()
        while (words.size > 1) {
            words.removeAt(words.lastIndex)
            aliasToCanonicalKey[words.joinToString(" ")]?.let { return it }
        }
        return null
    }

    private fun strippingLeadingClassCodes(token: String): String {
        val words = token.split(" ").filter { it.isNotEmpty() }.toMutableList()
        while (words.size > 1 && isClassCodeToken(words[0])) {
            words.removeAt(0)
        }
        return words.joinToString(" ")
    }

    private fun isClassCodeToken(word: String): Boolean =
        classCodePattern.matches(word)

    private fun isIgnoredHold(holdCode: String): Boolean {
        val normalized = normalizedHold(holdCode)
        return ignoredHoldPatterns.any { it.containsMatchIn(normalized) }
    }

    private fun defaultIconKey(canonicalKey: String): String =
        SubjectIcons.byCanonicalKey[canonicalKey]?.iconKey ?: SubjectIcons.DEFAULT_ICON_KEY

    /**
     * Lowercase, diacritic-folded, punctuation-to-space, HL/SL stripped.
     * Idempotent.
     */
    fun subjectLookupToken(value: String): String {
        val folded = normalizedHold(value)
            .lowercase(lookupLocale)
            .let { stripDiacritics(it) }

        val separated = folded.replace(Regex("""[^\p{L}\p{N}]+"""), " ")
        val withoutPhrases = separated.replace(levelPhrasePattern, " ")
        val words = withoutPhrases
            .split(" ")
            .filter { it.isNotEmpty() && it !in levelWords }
        return words.joinToString(" ")
    }

    /** Kept for call sites that still use the Lectio name. */
    fun normalizedLookupToken(value: String): String = subjectLookupToken(value)

    /**
     * FNV-1a 32-bit over UTF-8, folded into 0…359. Not [String.hashCode]: that is
     * not stable across processes on all ART versions the way we need colours to be.
     */
    fun stableHue(token: String): Int {
        var hash = 2166136261u
        for (byte in token.encodeToByteArray()) {
            hash = hash xor (byte.toUInt() and 0xFFu)
            hash *= 16777619u
        }
        return (hash % 360u).toInt()
    }

    private fun stripDiacritics(value: String): String {
        val nfd = Normalizer.normalize(value, Normalizer.Form.NFD)
        return nfd.replace("\\p{M}+".toRegex(), "")
    }

    fun normalizeHue(hue: Int): Int = ((hue % 360) + 360) % 360
}
