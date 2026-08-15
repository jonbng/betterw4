package dk.betterlectio.android.core.lectio.session

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit
import dagger.hilt.android.qualifiers.ApplicationContext
import dk.betterlectio.android.core.model.School
import dk.betterlectio.android.core.model.Student
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Non-secret "last school" hint so login can offer one-tap MitID after logout / session expiry.
 * Never stores credentials, cookies, or student ids.
 */
enum class LastSchoolReason {
    SESSION_EXPIRED,
    LOGGED_OUT,
}

data class LastSchoolHint(
    val gymId: Int,
    val schoolName: String,
    val reason: LastSchoolReason,
) {
    fun toSchool(): School = School(id = gymId, name = schoolName)

    companion object {
        fun fromStudent(student: Student, reason: LastSchoolReason): LastSchoolHint? {
            if (student.isDemo) return null
            val name = student.schoolName?.takeIf { it.isNotBlank() } ?: "Gymnasium"
            return LastSchoolHint(
                gymId = student.gymId,
                schoolName = name,
                reason = reason,
            )
        }

        /** Prefer [Student.schoolName]; fall back to [School.name] when building from login. */
        fun fromSchool(school: School, reason: LastSchoolReason = LastSchoolReason.LOGGED_OUT): LastSchoolHint? {
            if (school.isDemo) return null
            if (school.name.isBlank()) return null
            return LastSchoolHint(
                gymId = school.id,
                schoolName = school.name,
                reason = reason,
            )
        }
    }
}

interface LastSchoolStore {
    fun load(): LastSchoolHint?
    fun save(hint: LastSchoolHint)
    fun remember(student: Student, reason: LastSchoolReason)
    fun clear()
}

@Singleton
class SharedPrefsLastSchoolStore @Inject constructor(
    @ApplicationContext context: Context,
) : LastSchoolStore {

    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)

    override fun load(): LastSchoolHint? {
        val gymId = prefs.getInt(KEY_GYM_ID, Int.MIN_VALUE)
        if (gymId == Int.MIN_VALUE) return null
        val name = prefs.getString(KEY_SCHOOL_NAME, null)?.takeIf { it.isNotBlank() } ?: return null
        val reason = when (prefs.getString(KEY_REASON, null)) {
            LastSchoolReason.SESSION_EXPIRED.name -> LastSchoolReason.SESSION_EXPIRED
            LastSchoolReason.LOGGED_OUT.name -> LastSchoolReason.LOGGED_OUT
            else -> LastSchoolReason.LOGGED_OUT
        }
        return LastSchoolHint(gymId = gymId, schoolName = name, reason = reason)
    }

    override fun save(hint: LastSchoolHint) {
        prefs.edit {
            putInt(KEY_GYM_ID, hint.gymId)
            putString(KEY_SCHOOL_NAME, hint.schoolName)
            putString(KEY_REASON, hint.reason.name)
        }
    }

    override fun remember(student: Student, reason: LastSchoolReason) {
        LastSchoolHint.fromStudent(student, reason)?.let { save(it) }
    }

    override fun clear() {
        prefs.edit { clear() }
    }

    companion object {
        private const val PREFS_FILE = "last_school_hint"
        private const val KEY_GYM_ID = "gym_id"
        private const val KEY_SCHOOL_NAME = "school_name"
        private const val KEY_REASON = "reason"
    }
}
