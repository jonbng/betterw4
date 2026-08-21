package dk.betterw4.android.feature.schedule

import dk.betterw4.android.core.cache.CachePolicy
import dk.betterw4.android.core.cache.CachedValue
import dk.betterw4.android.core.cache.SimpleCache
import dk.betterw4.android.core.cache.W4Surface

internal data class CachedTimetableWeek(
    val week: ScheduleWeek,
    val isFresh: Boolean,
)

/**
 * Disk cache for one AC+EA timetable week.
 *
 * Own-schedule AC keys stay `schedule_<id>_<year>_<week>` so HTML written before EA was
 * cached still paints. Person and room weeks use their own keys so they cannot collide
 * with the signed-in student's grid.
 */
internal object TimetableWeekCache {
    fun ownAcKey(studentId: String, year: Int, week: Int) = "schedule_${studentId}_${year}_$week"
    fun ownEaKey(studentId: String, year: Int, week: Int) = "schedule_ea_${studentId}_${year}_$week"
    fun personAcKey(uwcId: String, year: Int, week: Int) = "person_schedule_${uwcId}_${year}_$week"
    fun personEaKey(uwcId: String, year: Int, week: Int) = "person_schedule_ea_${uwcId}_${year}_$week"
    fun roomAcKey(roomId: String, year: Int, week: Int) = "room_schedule_${roomId}_${year}_$week"

    fun read(
        cache: SimpleCache,
        acKey: String,
        eaKey: String?,
        year: Int,
        week: Int,
    ): CachedTimetableWeek? {
        val ac = cache.getWithMeta(acKey) ?: return null
        val ea = eaKey?.let { cache.getWithMeta(it) }
        val weekData = mergeHtml(ac.value, ea?.value, year, week) ?: return null
        return CachedTimetableWeek(weekData, isFresh(ac, ea))
    }

    fun write(
        cache: SimpleCache,
        acKey: String,
        acHtml: String,
        eaKey: String?,
        eaHtml: String?,
    ) {
        cache.put(acKey, acHtml)
        if (eaKey != null && !eaHtml.isNullOrBlank()) {
            cache.put(eaKey, eaHtml)
        }
    }

    fun mergeHtml(acHtml: String?, eaHtml: String?, year: Int, week: Int): ScheduleWeek? {
        if (acHtml.isNullOrBlank()) return null
        val acWeek = W4TimetableParser.parseWeek(acHtml, year, week, source = "ac")
        if (eaHtml.isNullOrBlank()) return acWeek
        return W4TimetableParser.mergeWeeks(
            acWeek,
            W4TimetableParser.parseWeek(eaHtml, year, week, source = "ea"),
        )
    }

    fun isFresh(ac: CachedValue, ea: CachedValue?): Boolean {
        if (!CachePolicy.isFresh(ac.updatedAtMs, W4Surface.TIMETABLE_ACADEMICS)) return false
        if (ea != null && !CachePolicy.isFresh(ea.updatedAtMs, W4Surface.TIMETABLE_EXTRA_ACADEMICS)) {
            return false
        }
        return true
    }
}
