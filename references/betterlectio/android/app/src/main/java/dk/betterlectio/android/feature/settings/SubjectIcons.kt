package dk.betterlectio.android.feature.settings

/**
 * Thin facade over [SubjectMapper] for call sites that still use SubjectIcons APIs.
 */
object SubjectIcons {

    data class SubjectMeta(
        val canonicalKey: String,
        val defaultName: String,
        val iconKey: String,
    )

    fun fold(raw: String): String = SubjectMapper.normalizedLookupToken(raw)

    fun iconKeyFor(title: String): String = SubjectMapper.iconKey(title)

    fun canonicalKeyFor(title: String): String? = SubjectMapper.canonicalKey(title)

    fun resolve(title: String): SubjectMeta? {
        val key = SubjectMapper.canonicalKey(title) ?: return null
        val meta = SubjectMapper.metadataByCanonicalKey[key] ?: return SubjectMeta(
            canonicalKey = key,
            defaultName = SubjectMapper.defaultName(key, fallback = title),
            iconKey = SubjectMapper.iconKey(title),
        )
        return SubjectMeta(
            canonicalKey = key,
            defaultName = meta.defaultName,
            iconKey = meta.iconKey,
        )
    }
}
