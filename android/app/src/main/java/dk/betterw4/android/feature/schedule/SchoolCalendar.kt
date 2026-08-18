package dk.betterw4.android.feature.schedule

import dk.betterw4.android.core.util.IsoDateUtils

/** Identity token for the public UWCRCN Google Calendar overlay (not for display). */
const val SCHOOL_CALENDAR_TEAM_TOKEN = "School calendar"

const val SCHOOL_CALENDAR_ID_PREFIX = "gcal-"

/**
 * The college-wide Google Calendar embedded on W4 Home (`#calendar` iframe)
 * and on [uwcrcn.no/school-calendar](https://uwcrcn.no/school-calendar/).
 * Same calendar for every student; public ICS, no Google auth.
 */
object SchoolCalendar {
    const val CALENDAR_ID = "calendar@uwcrcn.no"

    const val ICS_URL =
        "https://calendar.google.com/calendar/ical/calendar%40uwcrcn.no/public/basic.ics"

    fun isSchoolCalendarEvent(event: ScheduleEvent): Boolean {
        if (event.id.startsWith(SCHOOL_CALENDAR_ID_PREFIX, ignoreCase = true)) return true
        return event.team.equals(SCHOOL_CALENDAR_TEAM_TOKEN, ignoreCase = true)
    }

    /** Drops college-calendar overlay events when the student has hidden them. */
    fun visibleEvents(
        events: List<ScheduleEvent>,
        showSchoolCalendar: Boolean,
    ): List<ScheduleEvent> {
        if (showSchoolCalendar) return events
        return events.filterNot(::isSchoolCalendarEvent)
    }

    fun eventsFromIcs(
        ics: String,
        year: Int,
        week: Int,
    ): List<ScheduleEvent> {
        val monday = IsoDateUtils.weekStart(year, week)
        return IcsCalendarParser.eventsOverlapping(
            ics = ics,
            rangeStart = monday,
            rangeEndExclusive = monday.plusDays(7),
        )
    }

    /**
     * Overlay [extra] onto every day of [week], padding the week to Mon–Sun
     * so weekend school events still show when the W4 grid only returned weekdays.
     */
    fun mergeIntoWeek(week: ScheduleWeek, extra: List<ScheduleEvent>): ScheduleWeek {
        if (extra.isEmpty() && week.days.size >= 7) return week
        val monday = IsoDateUtils.weekStart(week.year, week.week)
        val extraByDate = extra
            .flatMap { ScheduleMultiDay.expandEventAcrossDays(it) }
            .groupBy { it.date }
        val existing = week.days.associateBy { it.date }
        val days = (0..6).map { offset ->
            val date = monday.plusDays(offset.toLong())
            val base = existing[date] ?: ScheduleDay(date, emptyList())
            val more = extraByDate[date].orEmpty()
            if (more.isEmpty()) {
                base
            } else {
                base.copy(
                    events = (base.events + more).sortedWith(
                        compareBy(
                            { !it.isAllDay },
                            { it.start ?: java.time.LocalDateTime.MIN },
                            { it.title },
                        ),
                    ),
                )
            }
        }
        return week.copy(days = days)
    }
}
