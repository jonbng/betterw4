package dk.betterw4.android.core.w4.session

import dk.betterw4.android.core.cache.OfflineDataCleaner
import dk.betterw4.android.core.w4.model.W4Credentials
import dk.betterw4.android.core.model.Student
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

sealed class AuthState {
    data object Loading : AuthState()
    data object Unauthenticated : AuthState()
    data class Authenticated(val student: Student) : AuthState()
}

/**
 * Owns current auth state for the process.
 * Install after MitID cookie capture; restore on cold start.
 *
 * iOS parity: AuthenticationViewModel.handleSessionExpired — on definitive death clear
 * local session **and** wipe WebView so the next MitID login is clean.
 */
@Singleton
class SessionController @Inject constructor(
    private val credentialStore: CredentialStore,
    private val sessionEvents: SessionEvents,
    private val offlineDataCleaner: OfflineDataCleaner,
    private val externalWiper: SessionExternalWiper,
    private val lastSchoolStore: LastSchoolStore,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val ioScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val _authState = MutableStateFlow<AuthState>(AuthState.Loading)
    val authState: StateFlow<AuthState> = _authState.asStateFlow()

    val currentStudent: Student?
        get() = (authState.value as? AuthState.Authenticated)?.student

    init {
        sessionEvents.sessionExpired
            .onEach {
                handleSessionExpired()
            }
            .launchIn(scope)
    }

    /**
     * iOS AuthenticationViewModel.handleSessionExpired — idempotent.
     */
    private fun handleSessionExpired() {
        val student = currentStudent
        if (student?.isDemo == true) return
        if (_authState.value !is AuthState.Authenticated && student == null) {
            // Already signed out — still wipe residual external jars.
            ioScope.launch {
                runCatching { externalWiper.wipeExternalAuthState() }
            }
            return
        }
        Timber.w("Session expired — full wipe (store + WebView)")
        student?.let { lastSchoolStore.remember(it, LastSchoolReason.SESSION_EXPIRED) }
        clearSession(keepStudentProfile = false)
        ioScope.launch {
            runCatching { externalWiper.wipeExternalAuthState() }
                .onFailure { Timber.w(it, "External wipe after session expiry failed") }
        }
    }

    fun restore() {
        val student = credentialStore.loadStudent()
        if (student == null) {
            _authState.value = AuthState.Unauthenticated
            return
        }
        if (student.isDemo) {
            _authState.value = AuthState.Authenticated(student)
            return
        }
        val creds = credentialStore.loadCredentials(student.studentId)
        if (creds == null || creds.sessionId.isEmpty()) {
            lastSchoolStore.remember(student, LastSchoolReason.SESSION_EXPIRED)
            credentialStore.deleteStudent()
            _authState.value = AuthState.Unauthenticated
            return
        }
        _authState.value = AuthState.Authenticated(student)
    }

    fun installSession(student: Student, credentials: W4Credentials?) {
        credentialStore.saveStudent(student)
        if (credentials != null && !student.isDemo) {
            credentialStore.saveCredentials(credentials, student.studentId)
        }
        // Keep last-school hint fresh for the next logout / expiry (non-demo only).
        if (!student.isDemo) {
            lastSchoolStore.remember(student, LastSchoolReason.LOGGED_OUT)
        }
        _authState.value = AuthState.Authenticated(student)
        Timber.i(
            "Session installed for studentId=%s gymId=%s demo=%s",
            student.studentId,
            student.gymId,
            student.isDemo,
        )
    }

    fun installDemoSession() {
        val demo = Student.Demo
        credentialStore.clearAll()
        credentialStore.saveStudent(demo)
        _authState.value = AuthState.Authenticated(demo)
    }

    fun clearSession(keepStudentProfile: Boolean = false) {
        val student = credentialStore.loadStudent()
        if (student != null && !student.isDemo) {
            credentialStore.deleteCredentials(student.studentId)
        }
        if (!keepStudentProfile) {
            credentialStore.deleteStudent()
        }
        offlineDataCleaner.clearAll()
        _authState.value = AuthState.Unauthenticated
    }

    fun loadCredentialsForCurrentStudent(): W4Credentials? {
        val student = currentStudent ?: return null
        if (student.isDemo) return null
        return credentialStore.loadCredentials(student.studentId)
    }
}
