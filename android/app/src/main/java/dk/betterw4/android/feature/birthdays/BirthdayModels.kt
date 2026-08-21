package dk.betterw4.android.feature.birthdays

import dk.betterw4.android.feature.directory.DirectoryEntity
import dk.betterw4.android.feature.directory.DirectoryEntityKind
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.util.Locale

enum class BirthdayKindFilter {
    ALL, STUDENTS, STAFF;

    fun includes(person: BirthdayPerson): Boolean = when (this) {
        ALL -> true
        STUDENTS -> !person.isStaff
        STAFF -> person.isStaff
    }
}

data class BirthdayPerson(
    val uwcId: String,
    val name: String? = null,
    val isStaff: Boolean = false,
    val profileRoute: String? = null,
    val photoUrl: String? = null,
) {
    val displayName: String
        get() = name?.trim()?.takeIf { it.isNotEmpty() } ?: uwcId

    val roleLabel: String
        get() = if (isStaff) "Staff" else "Student"

    fun toEntity(): DirectoryEntity = DirectoryEntity(
        id = uwcId,
        name = displayName,
        kind = if (isStaff) DirectoryEntityKind.TEACHER else DirectoryEntityKind.STUDENT,
        subtitle = roleLabel,
        avatarUrl = photoUrl,
    )
}

data class BirthdayDay(
    val date: LocalDate?,
    val dayNumber: Int,
    val dateLabel: String,
    val people: List<BirthdayPerson> = emptyList(),
) {
    val id: String get() = date?.toString() ?: "day-$dayNumber"
    val isEmpty: Boolean get() = people.isEmpty()

    fun filtered(by: BirthdayKindFilter): BirthdayDay =
        if (by == BirthdayKindFilter.ALL) this
        else copy(people = people.filter(by::includes))
}

data class BirthdayMonthRef(
    val year: Int,
    val month: Int,
) {
    val yearMonth: YearMonth get() = YearMonth.of(year, month)
    val label: String get() = yearMonth.format(MONTH_YEAR)

    fun offset(months: Int): BirthdayMonthRef {
        val next = yearMonth.plusMonths(months.toLong())
        return BirthdayMonthRef(next.year, next.monthValue)
    }

    companion object {
        private val MONTH_YEAR = DateTimeFormatter.ofPattern("MMMM yyyy", Locale.UK)

        fun of(date: LocalDate): BirthdayMonthRef = BirthdayMonthRef(date.year, date.monthValue)
    }
}

data class BirthdayMonth(
    val monthLabel: String? = null,
    val year: Int? = null,
    val month: Int? = null,
    val previous: BirthdayMonthRef? = null,
    val next: BirthdayMonthRef? = null,
    val days: List<BirthdayDay> = emptyList(),
) {
    val people: List<BirthdayPerson> get() = days.flatMap { it.people }
    val isEmpty: Boolean get() = people.isEmpty()

    val ref: BirthdayMonthRef?
        get() = if (year != null && month != null) BirthdayMonthRef(year, month) else null

    fun day(on: LocalDate): BirthdayDay? = days.firstOrNull { it.date == on }

    fun daysWithPeople(
        from: LocalDate? = null,
        through: LocalDate? = null,
    ): List<BirthdayDay> = days.filter { day ->
        if (day.people.isEmpty()) return@filter false
        val date = day.date ?: return@filter true
        if (from != null && date.isBefore(from)) return@filter false
        if (through != null && date.isAfter(through)) return@filter false
        true
    }

    fun filtered(by: BirthdayKindFilter): BirthdayMonth =
        if (by == BirthdayKindFilter.ALL) this
        else copy(days = days.map { it.filtered(by) })

    companion object {
        fun label(year: Int, month: Int): String =
            YearMonth.of(year, month).month.getDisplayName(TextStyle.FULL, Locale.UK) + " $year"
    }
}
