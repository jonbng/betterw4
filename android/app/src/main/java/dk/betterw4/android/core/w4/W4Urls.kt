package dk.betterw4.android.core.w4

import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import java.net.URLDecoder
import java.nio.charset.StandardCharsets

/**
 * Yii 1 URL builder for `https://w4.uwcrcn.no/index.php?r={route}&k=v`.
 *
 * Extra params are **sibling** query keys, not part of `r`
 * (`people/students/student&uwc_id=nc26jban` → `r=people/students/student&uwc_id=nc26jban`).
 */
object W4Urls {
    const val HOST = W4Hosts.HOST
    const val ORIGIN = W4Hosts.ORIGIN
    const val INDEX = "index.php"

    fun origin(): HttpUrl = ORIGIN.toHttpUrl()

    fun route(r: String, query: Map<String, String> = emptyMap()): HttpUrl {
        val (routeName, inline) = splitRouteAndQuery(r)
        val builder = origin().newBuilder()
            .addPathSegment(INDEX)
            // Keep `/` unencoded so URLs match W4's own `r=site/login` links.
            .addEncodedQueryParameter("r", encodeRoute(routeName))
        val merged = LinkedHashMap<String, String>()
        merged.putAll(inline)
        merged.putAll(query)
        for ((key, value) in merged) {
            if (key == "r") continue
            builder.addQueryParameter(key, value)
        }
        return builder.build()
    }

    fun student(uwcId: String): HttpUrl =
        route(Routes.STUDENT_PROFILE, mapOf("uwc_id" to uwcId))

    /**
     * Accepts an absolute URL, a path (`/index.php?r=…`), `index.php?r=…`,
     * or a bare Yii route (`academics/timetable/mytimetable`).
     *
     * A route may include sibling query keys inline:
     * `people/students/student&uwc_id=nc26jban`.
     */
    fun resolve(pathOrUrl: String, query: Map<String, String> = emptyMap()): HttpUrl {
        val trimmed = pathOrUrl.trim()
        val base: HttpUrl = when {
            trimmed.toHttpUrlOrNull() != null -> trimmed.toHttpUrl()
            trimmed.startsWith("/") -> (ORIGIN + trimmed).toHttpUrl()
            trimmed.startsWith(INDEX) || trimmed.startsWith("?r=") -> "$ORIGIN/$trimmed".toHttpUrl()
            else -> return route(trimmed, query)
        }
        if (query.isEmpty()) return base
        return base.newBuilder().apply {
            query.forEach { (k, v) ->
                if (k != "r") addQueryParameter(k, v)
            }
        }.build()
    }

    /** `r` query value from a W4 URL, decoded (`site%2Flogin` → `site/login`). */
    fun routeOf(url: HttpUrl): String? = routeOf(url.toString())

    fun routeOf(url: String): String? {
        val decoded = runCatching {
            URLDecoder.decode(url, StandardCharsets.UTF_8.name())
        }.getOrDefault(url)
        val match = ROUTE_QUERY.find(decoded) ?: return null
        return match.groupValues[1].trim().trimEnd('/')
    }

    object Routes {
        const val HOME = "site/index"
        const val LOGIN = "site/login"
        const val LOGOUT = "site/logout"
        /** Research guessed this; unauthenticated GETs 302 to login. */
        const val OTP = "site/otp"
        /** Live mid-login 2FA page after password POST (captured 14 Aug 2026). */
        const val VERIFY_2FA = "site/verify2fa"
        const val FORGOT_PASSWORD = "site/forgotpass"
        const val PROFILE = "site/profile"
        const val PASSWORD = "site/password"
        const val RSS = "site/rss"
        const val SET_STATUS = "site/setstatus"

        const val ASSESSMENTS = "academics/deadlines"
        const val MY_TIMETABLE = "academics/timetable/mytimetable"
        const val MY_TIMETABLE_INDEX = "academics/timetable/mytimetable/index"
        /** Another person's AC week: `?uwc_id=&year=&week=`. */
        const val PERSON_TIMETABLE = "academics/timetable/timetable"
        const val PERSON_TIMETABLE_INDEX = "academics/timetable/timetable/index"
        const val MY_CLASSES = "academics/classes/myclasses"
        const val ALL_CLASSES = "academics/classes/allclasses"
        /** One class: `?class_id=1EA16CECOX`. Roster lives here. */
        const val CLASS = "academics/classes/class"
        const val ALL_ASSESSMENTS = "academics/classes/assessments/all"
        const val GRADES = "academics/grades/grades"
        const val SAT_ACT = "academics/grades/grades/sat"
        const val TRANSCRIPTS = "academics/transcripts/transcripts"
        const val ROP = "academics/rop"
        const val EE = "academics/ee"
        const val TESTIMONIAL = "academics/testimonial"
        const val FEEDS = "academics/feeds"
        const val SUBJECT_PAGES = "academics/subjects/pages"
        const val TRIPS = "academics/trips"
        const val TRAVEL = "academics/travel/travel.list"
        const val RESOURCES = "academics/resources/resources"
        const val ROOM_TIMETABLE = "academics/timetable/room"
        const val ROOM_TIMETABLE_INDEX = "academics/timetable/room/index"

        const val EA_TIMETABLE = "extraacademics/timetable/mytimetable"
        const val EA_TIMETABLE_INDEX = "extraacademics/timetable/mytimetable/index"
        const val EA_PERSON_TIMETABLE = "extraacademics/timetable/timetable"
        const val EA_PERSON_TIMETABLE_INDEX = "extraacademics/timetable/timetable/index"
        const val EA_ACTIVITIES = "extraacademics/activities/myactivities"
        const val EA_DIARY = "extraacademics/activities/myactivities/diary"
        const val EA_PORTFOLIO = "extraacademics/activities/myportfolio"
        const val EA_INTERVIEWS = "extraacademics/activities/interviews"
        const val EA_SAFETYNET = "extraacademics/safetynet/mysafetynet"
        const val EA_ALL = "extraacademics/activities/ea"
        const val EA_DOCUMENTS = "extraacademics/documents"

        const val ABSENCES = "people/students/absences"
        const val ABSENCES_INDEX = "people/students/absences/index"
        const val ABSENCES_LIST = "people/students/absences/list"
        const val ABSENCES_REGISTER = "people/students/absences/register"
        const val EA_ABSENCES = "people/students/eaabsences"
        const val EA_ABSENCES_INDEX = "people/students/eaabsences/index"
        const val EA_ABSENCES_LIST = "people/students/eaabsences/list"
        const val STUDENT_PROFILE = "people/students/student"
        const val STUDENTS_ALL = "people/students/all"
        const val STUDENTS_FIRSTYEAR = "people/students/firstyear"
        const val STUDENTS_SECONDYEAR = "people/students/secondyear"
        const val STUDENTS_BY_HOUSE = "people/students/byhouse"
        const val STUDENTS_BY_HOUSE_INDEX = "people/students/byhouse/index"
        const val STAFF = "people/students/staff"
        const val STAFF_CURRENT = "people/staff/current"
        const val STAFF_PROFILE = "people/staff/staff"
        const val LETTER_ATTENDANCE = "people/students/letter/attendance"
        const val BIRTHDAYS = "people/birthdays"
        const val BIRTHDAYS_INDEX = "people/birthdays/index"
        const val ON_DUTY = "people/onduty"
        const val ON_DUTY_SCHEDULE = "people/onduty/schedule"

        const val MAILER_INBOX = "mailer/inbox"
        const val MAILER_SENT = "mailer/archive"
        const val MAILER_ARCHIVE = "mailer/archive"
        const val MAILER_VIEW = "mailer/view"
        const val MAILER_SEND = "mailer/send"
        const val MAILER_EXTRA = "mailer/extra"

        const val DOCUMENTS = "documents/index"
        const val ADMISSIONS_APPLICANTS = "admissions/browse/admissions"

        const val NOTIFICATIONS_READ = "notifications/read"
        const val NOTIFICATIONS_READ_GROUP = "notifications/readgroup"
        const val NOTIFICATIONS_READ_ALL = "notifications/readall"
        const val NOTIFICATIONS_READ_ALL_EMAILS = "notifications/readallemails"
        const val NOTIFICATIONS_CLEAR = "notifications/clear"
        const val NOTIFICATIONS_CLEAR_GROUP = "notifications/cleargroup"
        const val NOTIFICATIONS_CLEAR_ALL = "notifications/clearall"
        const val NOTIFICATIONS_REFRESH = "notifications/refresh"
    }

    private val ROUTE_QUERY = Regex("""[?&]r=([^&]+)""", RegexOption.IGNORE_CASE)

    /**
     * `people/students/student&uwc_id=nc26jban` → route + sibling keys.
     * Extra params must **not** be stuffed inside `r`.
     */
    internal fun splitRouteAndQuery(raw: String): Pair<String, Map<String, String>> {
        val trimmed = raw.trim().trimStart('/')
        val amp = trimmed.indexOf('&')
        if (amp < 0) return trimmed to emptyMap()
        val routeName = trimmed.substring(0, amp)
        val map = linkedMapOf<String, String>()
        for (part in trimmed.substring(amp + 1).split('&')) {
            if (part.isEmpty()) continue
            val eq = part.indexOf('=')
            val key = if (eq < 0) decode(part) else decode(part.substring(0, eq))
            val value = if (eq < 0) "" else decode(part.substring(eq + 1))
            if (key.isEmpty() || key == "r") continue
            map[key] = value
        }
        return routeName to map
    }

    private fun encodeRoute(route: String): String =
        route.split('/').joinToString("/") { segment ->
            java.net.URLEncoder.encode(segment, StandardCharsets.UTF_8.name())
                .replace("+", "%20")
        }

    private fun decode(value: String): String = runCatching {
        URLDecoder.decode(value, StandardCharsets.UTF_8.name())
    }.getOrDefault(value)
}
