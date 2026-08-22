package dk.betterw4.android.feature.schedule

/**
 * One academic class a student is in. [id] is W4's `class_id` when the
 * timetable brick linked `academics/classes/class` — that is what opens
 * the roster page.
 */
data class PersonClass(
    val id: String?,
    val name: String,
    val year: String? = null,
    val levelLabel: String? = null,
    val teacher: String? = null,
    val room: String? = null,
) {
    val canOpen: Boolean get() = !id.isNullOrBlank()

    val subtitle: String?
        get() = listOfNotNull(
            year?.let { if (it.startsWith("Year", ignoreCase = true)) it else "Year $it" },
            levelLabel?.takeIf { it.isNotBlank() },
            teacher?.takeIf { it.isNotBlank() },
            room?.takeIf { it.isNotBlank() },
        ).joinToString(" · ").ifBlank { null }
}

/**
 * Academic classes a student is enrolled in.
 *
 * Another student's public profile (`people/students/student&uwc_id=`) lists
 * their classes. `myclasses` / `mytimetable&uwc_id=` always returns the
 * signed-in student, so the profile page is the source of truth. The week
 * helper below is kept for callers that only have a timetable.
 */
object PersonClasses {
    private val SKIP_TITLES = setOf(
        "breakfast", "lunch", "dinner", "assembly", "tutorial",
        "study hall", "studyhall",
    )

    fun fromWeek(week: ScheduleWeek): List<PersonClass> {
        val linked = linkedMapOf<String, PersonClass>()
        val fallback = linkedMapOf<String, PersonClass>()
        for (day in week.days) {
            for (event in day.events) {
                val name = event.title.trim()
                if (name.isEmpty()) continue
                val classId = ClassRoster.classId(event.href, event.team)
                if (classId != null) {
                    linked.putIfAbsent(classId.lowercase(), PersonClass(id = classId, name = name))
                    continue
                }
                if (event.source.equals("ac", ignoreCase = true) &&
                    !event.isAllDay &&
                    name.lowercase() !in SKIP_TITLES
                ) {
                    fallback.putIfAbsent(name.lowercase(), PersonClass(id = null, name = name))
                }
            }
        }
        val source = if (linked.isNotEmpty()) linked.values else fallback.values
        return source.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.name })
    }

    fun merge(existing: Collection<PersonClass>, incoming: Collection<PersonClass>): List<PersonClass> {
        val byKey = linkedMapOf<String, PersonClass>()
        for (item in existing + incoming) {
            val name = item.name.trim()
            if (name.isEmpty()) continue
            val key = item.id?.lowercase() ?: "name:${name.lowercase()}"
            val previous = byKey[key]
            byKey[key] = if (previous == null) {
                item.copy(name = name)
            } else {
                previous.copy(
                    id = previous.id ?: item.id,
                    name = preferName(previous.name, name),
                    year = previous.year ?: item.year,
                    levelLabel = previous.levelLabel ?: item.levelLabel,
                    teacher = previous.teacher ?: item.teacher,
                    room = previous.room ?: item.room,
                )
            }
        }
        return byKey.values.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.name })
    }

    private fun preferName(existing: String, incoming: String): String {
        val a = existing.trim()
        val b = incoming.trim()
        if (b.isEmpty()) return a
        if (a.isEmpty()) return b
        // A class-id caption is worse than a subject name from the profile page.
        if (a.contains(':') && !b.contains(':')) return b
        if (b.contains(':') && !a.contains(':')) return a
        return if (b.length > a.length) b else a
    }
}