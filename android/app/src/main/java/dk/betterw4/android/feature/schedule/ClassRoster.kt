package dk.betterw4.android.feature.schedule

import dk.betterw4.android.feature.classes.W4ClassParser

/**
 * Class id on a timetable brick (`academics/classes/class&class_id=`).
 *
 * Every real AC class brick links that page. Breakfast / assembly / advisor
 * groups do not, and those have no roster to load. The brick's `team` field
 * is the same id when the href is missing.
 */
object ClassRoster {
    fun classId(href: String?, team: String? = null): String? {
        href?.let { W4ClassParser.classIdFromHref(it) }?.let { return it }
        return team?.trim()?.takeIf { W4ClassId.looksLike(it) }
    }
}
