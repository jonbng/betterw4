package dk.betterlectio.android.feature.directory

/**
 * Smart directory ranking: pins first, then exact prefix, then substring, then classmates (same class).
 */
object DirectorySearch {
    fun rank(
        items: List<DirectoryEntity>,
        query: String,
        pinnedIds: Set<String> = emptySet(),
        classmateClassLabel: String? = null,
    ): List<DirectoryEntity> {
        val q = query.trim().lowercase()
        val classmates = items.filter {
            classmateClassLabel != null &&
                it.kind == DirectoryEntityKind.STUDENT &&
                (it.subtitle?.contains(classmateClassLabel, ignoreCase = true) == true ||
                    it.name.contains(classmateClassLabel, ignoreCase = true))
        }.map { it.id }.toSet()

        fun score(e: DirectoryEntity): Int {
            var s = 0
            if (e.id in pinnedIds) s += 1_000
            if (e.id in classmates) s += 200
            if (q.isEmpty()) return s
            val name = e.name.lowercase()
            val sub = e.subtitle?.lowercase().orEmpty()
            when {
                name == q -> s += 500
                name.startsWith(q) -> s += 400
                name.contains(q) -> s += 300
                sub.startsWith(q) -> s += 200
                sub.contains(q) -> s += 100
                else -> s -= 50 // deprioritize non-matches when searching
            }
            return s
        }

        val filtered = if (q.isEmpty()) {
            items
        } else {
            items.filter {
                it.name.lowercase().contains(q) ||
                    it.subtitle?.lowercase()?.contains(q) == true ||
                    it.kind.name.lowercase().contains(q)
            }
        }
        return filtered.sortedWith(
            compareByDescending<DirectoryEntity> { score(it) }
                .thenBy { it.name.lowercase() },
        )
    }

    fun classmates(
        items: List<DirectoryEntity>,
        classLabel: String?,
    ): List<DirectoryEntity> {
        if (classLabel.isNullOrBlank()) return emptyList()
        return items.filter {
            it.kind == DirectoryEntityKind.STUDENT &&
                (it.subtitle?.contains(classLabel, ignoreCase = true) == true)
        }
    }
}
