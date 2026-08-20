package dk.betterw4.android.feature.directory

import dk.betterw4.android.feature.schedule.PersonClass

/**
 * One extra-academic activity a staff member leads, from their public
 * `people/staff/staff` page.
 */
data class StaffActivity(
    val name: String,
    val dates: String? = null,
    val category: String? = null,
)

/**
 * What we know about a person on their profile screen.
 *
 * Students: boarding house + room from `people/students/byhouse`, classes
 * from their public timetable, directory identity as a fallback.
 *
 * Staff: roles, real email, office/mobile, taught classes and EA activities
 * from `people/staff/staff&uwc_id=`.
 */
data class StudentProfile(
    val id: String,
    val name: String? = null,
    val kind: DirectoryEntityKind = DirectoryEntityKind.STUDENT,
    val houseId: String? = null,
    val house: String? = null,
    val room: String? = null,
    val year: String? = null,
    val country: String? = null,
    val email: String? = null,
    val officeTel: String? = null,
    val mobile: String? = null,
    val birthday: String? = null,
    val positions: List<String> = emptyList(),
    val classes: List<PersonClass> = emptyList(),
    val activities: List<StaffActivity> = emptyList(),
    val photoUrl: String? = null,
) {
    val isStaff: Boolean get() = kind == DirectoryEntityKind.TEACHER

    fun displayName(fallback: String): String {
        val preferred = name?.trim().orEmpty()
        return preferred.ifBlank { fallback }
    }

    fun pictureUrl(fallback: String?): String? {
        val custom = photoUrl?.trim().orEmpty()
        if (custom.isNotEmpty()) return custom
        return fallback?.takeIf { it.isNotBlank() }
    }

    val subtitle: String?
        get() = if (isStaff) {
            listOfNotNull(
                positions.take(3).joinToString(" · ").ifBlank { null },
                country?.takeIf { it.isNotBlank() },
            ).joinToString(" · ").ifBlank { null }
        } else {
            listOfNotNull(
                house?.takeIf { it.isNotBlank() },
                room?.takeIf { it.isNotBlank() },
                year?.let { label ->
                    when (label) {
                        "1" -> "Year 1"
                        "2" -> "Year 2"
                        else -> if (label.startsWith("Year", ignoreCase = true)) label else "Year $label"
                    }
                },
                country?.takeIf { it.isNotBlank() },
            ).joinToString(" · ").ifBlank { null }
        }

    companion object {
        fun from(
            entity: DirectoryEntity,
            placement: HousePlacement?,
            classes: List<PersonClass> = emptyList(),
            parsed: W4PersonProfile? = null,
        ): StudentProfile {
            val resident = placement?.resident
            val mergedClasses = dk.betterw4.android.feature.schedule.PersonClasses.merge(
                parsed?.classes.orEmpty(),
                classes,
            )
            return StudentProfile(
                id = entity.id,
                name = parsed?.entity?.name?.takeIf { it.isNotBlank() } ?: entity.name,
                kind = parsed?.entity?.kind ?: entity.kind,
                houseId = placement?.house?.id,
                house = placement?.house?.name ?: parsed?.house,
                room = placement?.room?.name,
                year = resident?.year ?: parsed?.year,
                country = parsed?.country ?: resident?.country,
                email = parsed?.email,
                officeTel = parsed?.officeTel,
                mobile = parsed?.mobile,
                birthday = parsed?.birthday,
                positions = parsed?.positions.orEmpty().ifEmpty {
                    if (entity.kind == DirectoryEntityKind.TEACHER) {
                        StaffRoles.parse(entity.subtitle)
                    } else {
                        emptyList()
                    }
                },
                classes = mergedClasses,
                activities = parsed?.activities.orEmpty(),
                photoUrl = parsed?.entity?.avatarUrl ?: entity.avatarUrl,
            )
        }
    }
}

/**
 * Staff "Position" is a comma list that mixes jobs students care about
 * (`Teacher`, `Advisor`, `Kitchen`) with internal mailing lists.
 */
object StaffRoles {
    fun parse(raw: String?): List<String> {
        if (raw.isNullOrBlank()) return emptyList()
        val source = raw.split('·').map { it.trim() }
            .lastOrNull { it.contains(',') }
            ?: raw
        return source.split(',')
            .map { it.replace('\u00a0', ' ').trim() }
            .filter { it.isNotEmpty() && !isMailingList(it) }
            .distinct()
    }

    fun isMailingList(role: String): Boolean {
        val n = role.trim().lowercase()
        if (n.isEmpty()) return true
        return n.contains("mail list") || n.endsWith(" mail") || n == "support staff mail"
    }
}

object InstagramHandles {
    fun normalize(value: String?): String? {
        val trimmed = value?.trim().orEmpty()
        if (trimmed.isEmpty()) return null

        var handle = trimmed
        val urlMatch = Regex(
            """(?:https?://)?(?:www\.)?instagram\.com/([^/?#]+)""",
            RegexOption.IGNORE_CASE,
        ).find(handle)
        if (urlMatch != null) {
            handle = urlMatch.groupValues[1]
        }

        handle = handle.replace(Regex("^@+"), "")
            .replace(Regex("^/+|/+$"), "")
            .trim()
        return handle.takeIf { it.isNotEmpty() }
    }

    fun format(value: String?): String {
        val handle = normalize(value) ?: return ""
        return "@$handle"
    }

    fun profileUrl(value: String?): String? {
        val handle = normalize(value) ?: return null
        return "https://instagram.com/$handle"
    }
}

/** Extension parity: `12. maj 2008` style. */
fun formatDanishBirthdate(isoDate: String): String {
    val months = listOf(
        "jan", "feb", "mar", "apr", "maj", "jun",
        "jul", "aug", "sep", "okt", "nov", "dec",
    )
    val parts = isoDate.trim().split('-')
    if (parts.size < 3) return isoDate
    val year = parts[0]
    val month = parts[1].toIntOrNull() ?: return isoDate
    val day = parts[2].toIntOrNull() ?: return isoDate
    val monthName = months.getOrNull(month - 1) ?: parts[1]
    return "$day. $monthName $year"
}
