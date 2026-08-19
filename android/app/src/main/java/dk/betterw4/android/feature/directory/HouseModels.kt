package dk.betterw4.android.feature.directory

/**
 * One boarding house from `people/students/byhouse`.
 *
 * W4 lists houses as `house_id` slugs (`denmark`, `finland`, …) and then a page
 * of rooms (`Room 101`) with a `ul.user-list` of residents under each heading.
 */
data class House(
    val id: String,
    val name: String,
    val leaders: List<HouseResident> = emptyList(),
    val rooms: List<HouseRoom> = emptyList(),
    val unassigned: List<HouseResident> = emptyList(),
    val loaded: Boolean = false,
) {
    val studentCount: Int
        get() = rooms.sumOf { it.residents.size } + unassigned.size

    val roomCount: Int get() = rooms.size
}

data class HouseRoom(
    val id: String,
    val name: String,
    val residents: List<HouseResident> = emptyList(),
)

data class HouseResident(
    val entity: DirectoryEntity,
    val country: String? = null,
    val year: String? = null,
    val status: String? = null,
) {
    val id: String get() = entity.id

    val detailLine: String?
        get() = listOfNotNull(
            country?.takeIf { it.isNotBlank() },
            yearLabel,
            status?.takeIf { it.isNotBlank() },
        ).joinToString(" · ").ifBlank { entity.subtitle }
}

private val HouseResident.yearLabel: String?
    get() {
        val raw = year?.trim().orEmpty()
        if (raw.isEmpty()) return null
        return when (raw) {
            "1" -> "1st year"
            "2" -> "2nd year"
            else -> raw
        }
    }

/** Where a student lives: boarding house plus the room heading, when they have one. */
data class HousePlacement(
    val house: House,
    val room: HouseRoom?,
    val resident: HouseResident,
)

fun House.placementOf(uwcId: String): HousePlacement? {
    val id = uwcId.trim().lowercase()
    if (id.isEmpty()) return null
    rooms.forEach { room ->
        room.residents.firstOrNull { it.id.equals(id, ignoreCase = true) }?.let {
            return HousePlacement(this, room, it)
        }
    }
    unassigned.firstOrNull { it.id.equals(id, ignoreCase = true) }?.let {
        return HousePlacement(this, null, it)
    }
    return null
}

fun Iterable<House>.placementOf(uwcId: String): HousePlacement? {
    forEach { house -> house.placementOf(uwcId)?.let { return it } }
    return null
}
