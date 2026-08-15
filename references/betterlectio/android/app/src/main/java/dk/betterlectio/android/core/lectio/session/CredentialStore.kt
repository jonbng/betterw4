package dk.betterlectio.android.core.lectio.session

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import dk.betterlectio.android.core.lectio.model.LectioCredentials
import dk.betterlectio.android.core.model.Student
import org.json.JSONObject
import timber.log.Timber

/**
 * Secure persistence for Lectio credentials + student profile.
 * iOS parity: KeychainManager (credentials + student).
 */
interface CredentialStore {
    fun saveCredentials(credentials: LectioCredentials, studentId: String)
    fun loadCredentials(studentId: String): LectioCredentials?
    fun updateCredentials(credentials: LectioCredentials, studentId: String)
    fun deleteCredentials(studentId: String)

    fun saveStudent(student: Student)
    fun loadStudent(): Student?
    fun deleteStudent()

    fun clearAll()
}

class EncryptedCredentialStore(
    context: Context,
) : CredentialStore {

    private val prefs: SharedPreferences = createPrefs(context.applicationContext)

    override fun saveCredentials(credentials: LectioCredentials, studentId: String) {
        prefs.edit {
            putString(credentialsKey(studentId), credentials.seededIsLoggedIn().toJson())
        }
    }

    override fun loadCredentials(studentId: String): LectioCredentials? {
        val raw = prefs.getString(credentialsKey(studentId), null) ?: return null
        return LectioCredentials.fromJson(raw)
    }

    override fun updateCredentials(credentials: LectioCredentials, studentId: String) {
        saveCredentials(credentials, studentId)
    }

    override fun deleteCredentials(studentId: String) {
        prefs.edit { remove(credentialsKey(studentId)) }
    }

    override fun saveStudent(student: Student) {
        prefs.edit {
            putString(KEY_STUDENT, studentToJson(student))
            putString(KEY_ACTIVE_STUDENT_ID, student.studentId)
        }
    }

    override fun loadStudent(): Student? {
        val raw = prefs.getString(KEY_STUDENT, null) ?: return null
        return studentFromJson(raw)
    }

    override fun deleteStudent() {
        prefs.edit {
            remove(KEY_STUDENT)
            remove(KEY_ACTIVE_STUDENT_ID)
        }
    }

    override fun clearAll() {
        prefs.edit { clear() }
    }

    private fun credentialsKey(studentId: String) = "creds_$studentId"

    private fun studentToJson(student: Student): String {
        val o = JSONObject()
        o.put("studentId", student.studentId)
        o.put("gymId", student.gymId)
        o.put("name", student.name)
        o.put("pictureId", student.pictureId)
        o.put("classLabel", student.classLabel)
        o.put("schoolName", student.schoolName)
        o.put("isDemo", student.isDemo)
        return o.toString()
    }

    private fun studentFromJson(json: String): Student? = try {
        val o = JSONObject(json)
        Student(
            studentId = o.getString("studentId"),
            gymId = o.getInt("gymId"),
            name = o.optString("name").takeIf { it.isNotEmpty() && o.has("name") && !o.isNull("name") },
            pictureId = o.optString("pictureId").takeIf { o.has("pictureId") && !o.isNull("pictureId") && it.isNotEmpty() },
            classLabel = o.optString("classLabel").takeIf { o.has("classLabel") && !o.isNull("classLabel") && it.isNotEmpty() },
            schoolName = o.optString("schoolName").takeIf { o.has("schoolName") && !o.isNull("schoolName") && it.isNotEmpty() },
            isDemo = o.optBoolean("isDemo", false),
        )
    } catch (e: Exception) {
        Timber.w(e, "Failed to decode student")
        null
    }

    companion object {
        private const val PREFS_FILE = "lectio_secure_session"
        private const val KEY_STUDENT = "student"
        private const val KEY_ACTIVE_STUDENT_ID = "active_student_id"

        private fun createPrefs(context: Context): SharedPreferences {
            return try {
                val masterKey = MasterKey.Builder(context)
                    .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                    .build()
                EncryptedSharedPreferences.create(
                    context,
                    PREFS_FILE,
                    masterKey,
                    EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                    EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
                )
            } catch (e: Exception) {
                // Fail closed: never store autologin cookies in plaintext prefs.
                Timber.e(e, "EncryptedSharedPreferences unavailable — refusing plaintext fallback")
                throw IllegalStateException(
                    "Secure credential storage unavailable; cannot store Lectio session",
                    e,
                )
            }
        }
    }
}

/** In-memory store for unit tests. */
class InMemoryCredentialStore : CredentialStore {
    private val creds = mutableMapOf<String, LectioCredentials>()
    private var student: Student? = null

    override fun saveCredentials(credentials: LectioCredentials, studentId: String) {
        creds[studentId] = credentials.seededIsLoggedIn()
    }

    override fun loadCredentials(studentId: String): LectioCredentials? = creds[studentId]

    override fun updateCredentials(credentials: LectioCredentials, studentId: String) {
        saveCredentials(credentials, studentId)
    }

    override fun deleteCredentials(studentId: String) {
        creds.remove(studentId)
    }

    override fun saveStudent(student: Student) {
        this.student = student
    }

    override fun loadStudent(): Student? = student

    override fun deleteStudent() {
        student = null
    }

    override fun clearAll() {
        creds.clear()
        student = null
    }
}
