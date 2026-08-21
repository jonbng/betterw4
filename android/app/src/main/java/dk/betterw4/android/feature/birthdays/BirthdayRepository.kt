package dk.betterw4.android.feature.birthdays

import dk.betterw4.android.core.cache.CachePolicy
import dk.betterw4.android.core.cache.SimpleCache
import dk.betterw4.android.core.cache.W4Surface
import dk.betterw4.android.core.result.AppError
import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.core.w4.W4Client
import dk.betterw4.android.core.w4.W4Dates
import dk.betterw4.android.core.w4.W4Urls
import dk.betterw4.android.core.w4.model.FetchPriority
import dk.betterw4.android.core.w4.session.SessionController
import dk.betterw4.android.feature.demo.DemoData
import dk.betterw4.android.feature.directory.DirectoryEntityKind
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.DateTimeFormatter
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class BirthdayRepository @Inject constructor(
    private val client: W4Client,
    private val cache: SimpleCache,
    private val session: SessionController,
) {
    suspend fun loadMonth(
        ref: BirthdayMonthRef,
        force: Boolean = false,
        priority: FetchPriority = FetchPriority.Important,
    ): AppResult<BirthdayMonth> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) return AppResult.Success(demoMonth(ref))

        val key = cacheKey(student.studentId, ref)
        if (!force) {
            cache.getWithMeta(key)?.let { cached ->
                if (CachePolicy.isFresh(cached.updatedAtMs, W4Surface.PEOPLE)) {
                    return AppResult.Success(parsed(cached.value, ref))
                }
            }
        }
        return when (
            val res = client.get(
                W4Urls.Routes.BIRTHDAYS_INDEX,
                query = mapOf(
                    "month" to ref.month.toString(),
                    "year" to ref.year.toString(),
                ),
                priority = priority,
            )
        ) {
            is AppResult.Success -> {
                cache.put(key, res.data.body)
                AppResult.Success(parsed(res.data.body, ref))
            }
            is AppResult.Failure -> {
                cache.get(key)?.let { return AppResult.Success(parsed(it, ref)) }
                res
            }
        }
    }

    private fun parsed(html: String, ref: BirthdayMonthRef): BirthdayMonth {
        val parsed = W4BirthdayParser.parse(html)
        return parsed.copy(
            year = parsed.year ?: ref.year,
            month = parsed.month ?: ref.month,
            monthLabel = parsed.monthLabel ?: ref.label,
            previous = parsed.previous ?: ref.offset(-1),
            next = parsed.next ?: ref.offset(1),
        )
    }

    companion object {
        private val DISPLAY_DAY = DateTimeFormatter.ofPattern("EEE d MMM", Locale.UK)

        fun cacheKey(studentId: String, ref: BirthdayMonthRef): String =
            "birthdays_${studentId}_${ref.year}_${ref.month.toString().padStart(2, '0')}"

        fun demoMonth(
            ref: BirthdayMonthRef,
            today: LocalDate = W4Dates.today(),
        ): BirthdayMonth {
            val students = DemoData.directory.filter { it.kind == DirectoryEntityKind.STUDENT }
            val staff = DemoData.directory.filter { it.kind == DirectoryEntityKind.TEACHER }
            val length = YearMonth.of(ref.year, ref.month).lengthOfMonth()
            val isCurrent = today.year == ref.year && today.monthValue == ref.month

            fun person(entity: dk.betterw4.android.feature.directory.DirectoryEntity) = BirthdayPerson(
                uwcId = entity.id,
                name = entity.name,
                isStaff = entity.kind == DirectoryEntityKind.TEACHER,
                photoUrl = entity.avatarUrl,
            )

            fun day(number: Int, people: List<dk.betterw4.android.feature.directory.DirectoryEntity>): BirthdayDay {
                val date = runCatching { LocalDate.of(ref.year, ref.month, number) }.getOrNull()
                return BirthdayDay(
                    date = date,
                    dayNumber = number,
                    dateLabel = date?.format(DISPLAY_DAY) ?: number.toString(),
                    people = people.map(::person),
                )
            }

            val days = buildList {
                if (isCurrent) {
                    add(day(today.dayOfMonth, students.take(1)))
                    val tomorrow = today.dayOfMonth + 1
                    if (tomorrow <= length) {
                        add(day(tomorrow, students.drop(1).take(1)))
                    }
                    val later = minOf(today.dayOfMonth + 6, length)
                    if (later != today.dayOfMonth && later != tomorrow) {
                        add(day(later, staff.take(1) + students.drop(2).take(2)))
                    }
                } else {
                    add(day(3, students.take(2)))
                    add(day(minOf(18, length), staff.take(1)))
                }
            }.sortedBy { it.date ?: LocalDate.MIN }

            return BirthdayMonth(
                monthLabel = ref.label,
                year = ref.year,
                month = ref.month,
                previous = ref.offset(-1),
                next = ref.offset(1),
                days = days,
            )
        }
    }
}
