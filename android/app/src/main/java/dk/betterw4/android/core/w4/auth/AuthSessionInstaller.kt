package dk.betterw4.android.core.w4.auth

import dk.betterw4.android.core.w4.W4Html
import dk.betterw4.android.core.w4.W4Urls
import dk.betterw4.android.core.w4.http.W4HttpEngine
import dk.betterw4.android.core.w4.model.FetchPriority
import dk.betterw4.android.core.w4.model.W4Credentials
import dk.betterw4.android.core.w4.model.W4Error
import dk.betterw4.android.core.w4.model.W4Request
import dk.betterw4.android.core.w4.scrape.W4IdentityParser
import dk.betterw4.android.core.w4.session.CredentialStore
import dk.betterw4.android.core.w4.session.LastSchoolReason
import dk.betterw4.android.core.w4.session.LastSchoolStore
import dk.betterw4.android.core.w4.session.SavedLoginStore
import dk.betterw4.android.core.w4.session.SessionController
import dk.betterw4.android.core.w4.session.SessionExternalWiper
import dk.betterw4.android.core.model.School
import dk.betterw4.android.core.model.Student
import dk.betterw4.android.core.model.W4School
import dk.betterw4.android.core.result.AppError
import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.feature.directory.AvatarRepository
import dk.betterw4.android.feature.directory.DirectorySyncService
import dk.betterw4.android.feature.messages.MessageListPrefetcher
import dk.betterw4.android.feature.settings.SettingsStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Completes native W4 username/password (+ OTP) login and installs the session.
 */
@Singleton
class AuthSessionInstaller @Inject constructor(
    private val engine: W4HttpEngine,
    private val credentialStore: CredentialStore,
    private val savedLoginStore: SavedLoginStore,
    private val sessionController: SessionController,
    private val sessionExternalWiper: SessionExternalWiper,
    private val lastSchoolStore: LastSchoolStore,
    private val settingsStore: SettingsStore,
    private val directorySync: DirectorySyncService,
    private val messagePrefetcher: MessageListPrefetcher,
    private val avatarRepository: AvatarRepository,
    private val w4LoginClient: W4LoginClient,
) {
    private val bgScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    sealed class W4AuthResult {
        data class LoggedIn(val student: Student) : W4AuthResult()
        data class OtpRequired(val challenge: W4OtpChallenge) : W4AuthResult()
    }

    suspend fun loginWithPassword(username: String, password: String): AppResult<W4AuthResult> {
        return loginWithPassword(username, password, wipeSavedOnInvalid = false)
    }

    /**
     * Re-POST the encrypted username + password after a biometric / device-credential gate.
     * A wrong saved password (user changed it on W4) wipes the store so we do not loop.
     */
    suspend fun loginWithSavedLogin(): AppResult<W4AuthResult> {
        val saved = savedLoginStore.load() ?: return AppResult.Failure(AppError.InvalidLogin)
        return loginWithPassword(saved.username, saved.password, wipeSavedOnInvalid = true)
    }

    private suspend fun loginWithPassword(
        username: String,
        password: String,
        wipeSavedOnInvalid: Boolean,
    ): AppResult<W4AuthResult> {
        return try {
            when (val step = w4LoginClient.submitPassword(username, password)) {
                is W4LoginStep.Authenticated -> {
                    persistSavedLogin(username, password)
                    finishNativeLogin(step.credentials, step.html, username)
                        .map { W4AuthResult.LoggedIn(it) }
                }
                is W4LoginStep.NeedsOtp -> {
                    persistSavedLogin(username, password)
                    AppResult.Success(W4AuthResult.OtpRequired(step.challenge))
                }
                is W4LoginStep.Failed -> {
                    if (wipeSavedOnInvalid) savedLoginStore.clear()
                    AppResult.Failure(AppError.InvalidLogin)
                }
            }
        } catch (e: W4Error) {
            Timber.w(e, "W4 password login failed")
            AppResult.Failure(e.toAppError())
        } catch (e: Exception) {
            Timber.e(e, "W4 password login crashed")
            AppResult.Failure(W4Error.Unknown(e.message, e).toAppError())
        }
    }

    suspend fun loginWithOtp(challenge: W4OtpChallenge, code: String, username: String): AppResult<W4AuthResult> {
        return try {
            when (val step = w4LoginClient.submitOtp(challenge, code)) {
                is W4LoginStep.Authenticated ->
                    finishNativeLogin(step.credentials, step.html, username)
                        .map { W4AuthResult.LoggedIn(it) }
                is W4LoginStep.NeedsOtp ->
                    AppResult.Failure(AppError.InvalidLogin)
                is W4LoginStep.Failed ->
                    AppResult.Failure(AppError.InvalidLogin)
            }
        } catch (e: W4Error) {
            Timber.w(e, "W4 OTP login failed")
            AppResult.Failure(e.toAppError())
        } catch (e: Exception) {
            Timber.e(e, "W4 OTP login crashed")
            AppResult.Failure(W4Error.Unknown(e.message, e).toAppError())
        }
    }

    private suspend fun finishNativeLogin(
        credentials: W4Credentials,
        html: String,
        fallbackUsername: String,
    ): AppResult<Student> {
        var latestCreds = credentials
        var identity = W4IdentityParser.parse(html)
        if (identity.personId.isNullOrBlank() || looksLikeLoginHtml(html)) {
            val home = engine.execute(
                W4Request(
                    url = W4Urls.route(W4Urls.Routes.HOME),
                    method = "GET",
                    priority = FetchPriority.Important,
                    studentId = null,
                    allowLoginPage = true,
                ),
                latestCreds,
            )
            latestCreds = home.credentials
            identity = W4IdentityParser.parse(home.response.body)
            if (looksLikeLoginHtml(home.response.body)) {
                return AppResult.Failure(AppError.InvalidLogin)
            }
        }
        val personId = identity.personId ?: fallbackUsername.trim().takeIf { it.isNotEmpty() }
        if (personId.isNullOrBlank()) {
            return AppResult.Failure(
                W4Error.Parse("Could not parse W4 user id").toAppError(),
            )
        }
        return finishLogin(
            personId = personId,
            name = identity.name,
            pictureId = identity.pictureId,
            school = W4School.school,
            credentials = latestCreds,
        )
    }

    private suspend fun finishLogin(
        personId: String,
        name: String?,
        pictureId: String?,
        school: School,
        credentials: W4Credentials,
    ): AppResult<Student> {
        val forsideUrl = W4Urls.route(W4Urls.Routes.HOME)
        val student = Student(
            studentId = personId,
            gymId = school.id,
            name = name,
            pictureId = pictureId,
            classLabel = null,
            schoolName = school.name,
            isDemo = false,
        )

        // Persist under real student id, then one more request so rotations bind to that id.
        credentialStore.saveCredentials(credentials, personId)
        val confirm = engine.execute(
            W4Request(
                url = forsideUrl,
                method = "GET",
                priority = FetchPriority.Important,
                studentId = personId,
            ),
            credentials,
        )
        val finalCreds = confirm.credentials
        credentialStore.saveCredentials(finalCreds, personId)
        sessionController.installSession(student, finalCreds)

        bgScope.launch {
            settingsStore.activateScope(student.studentId, student.gymId.toString())
            schedulePostLoginSync()
        }

        Timber.i("Login complete studentId=%s gymId=%s", personId, school.id)
        return AppResult.Success(student)
    }

    private fun persistSavedLogin(username: String, password: String) {
        savedLoginStore.save(username, password)
    }

    private fun looksLikeLoginHtml(html: String): Boolean = W4Html.isLoginHtml(html)

    fun enterDemo(): Student {
        savedLoginStore.clear()
        sessionController.installDemoSession()
        bgScope.launch {
            schedulePostLoginSync()
        }
        return Student.Demo
    }

    /**
     * Prefetch inbox after login. Fire-and-forget.
     */
    private fun schedulePostLoginSync() {
        bgScope.launch {
            sessionController.currentStudent?.let { s ->
                runCatching {
                    avatarRepository.seedSelf(s.pictureId, s.studentId, s.gymId)
                }
            }
            runCatching { directorySync.syncFullCatalog() }
                .onFailure { Timber.w(it, "Directory catalog sync failed") }
        }
        messagePrefetcher.schedulePrefetch()
    }

    /**
     * Clear UI session immediately, then wipe residual cookies.
     */
    fun logout() {
        savedLoginStore.clear()
        val student = sessionController.currentStudent
        if (student == null || student.isDemo) {
            // Already signed out (e.g. session-lost handler) — still wipe residual jars.
            sessionController.clearSession()
            bgScope.launch {
                runCatching { sessionExternalWiper.wipeExternalAuthState() }
            }
            return
        }
        lastSchoolStore.remember(student, LastSchoolReason.LOGGED_OUT)
        val creds = credentialStore.loadCredentials(student.studentId)
        sessionController.clearSession()
        bgScope.launch {
            if (creds != null && creds.sessionId.isNotEmpty()) {
                runCatching {
                    engine.execute(
                        W4Request(
                            url = W4Urls.route(W4Urls.Routes.LOGOUT),
                            method = "GET",
                            priority = FetchPriority.Opportunistic,
                            allowLoginPage = true,
                        ),
                        creds,
                    )
                }.onFailure { Timber.w(it, "W4 site/logout failed") }
            }
            runCatching { sessionExternalWiper.wipeExternalAuthState() }
                .onFailure { Timber.w(it, "External wipe on logout failed") }
        }
    }

    /**
     * Unexpected W4 session death.
     * No-op if already signed out so cold-start + HTTP expiry do not double-fire.
     */
    private fun forceLogoutSessionLost(@Suppress("UNUSED_PARAMETER") detectionSource: String) {
        val student = sessionController.currentStudent ?: return
        if (student.isDemo) return
        lastSchoolStore.remember(student, LastSchoolReason.SESSION_EXPIRED)
        sessionController.clearSession()
        bgScope.launch {
            runCatching { sessionExternalWiper.wipeExternalAuthState() }
                .onFailure { Timber.w(it, "External wipe after session lost failed") }
        }
    }

    /**
     * iOS: when no stored student, wipe residual WK/keychain before LoginView.
     * Call after [SessionController.restore] when state is unauthenticated.
     */
    fun wipeResidualAuthState() {
        bgScope.launch {
            runCatching { sessionExternalWiper.wipeExternalAuthState() }
            Timber.i("Residual auth state wiped (unauthenticated cold start)")
        }
    }

    /**
     * Cold-start sequence:
     * 1. coldStartValidate — cheapest W4 probe; definitive death → logout
     * 2. message prefetch
     *
     * Strictly sequential so parallel autologin rotation races do not kill the session.
     */
    fun onColdStart(student: Student): Job {
        return bgScope.launch {
            if (student.isDemo) {
                schedulePostLoginSync()
                return@launch
            }

            when (val probe = coldStartValidate(student)) {
                ColdStartResult.Dead -> {
                    Timber.w("Cold-start validation: session dead — logging out")
                    forceLogoutSessionLost(detectionSource = "cold_start_validation")
                    return@launch
                }
                is ColdStartResult.Deferred -> {
                    Timber.w(
                        probe.cause,
                        "Cold-start validation deferred — will recover on next user fetch",
                    )
                }
                ColdStartResult.Ok -> {
                    Timber.i("Cold-start validation OK")
                }
            }

            settingsStore.activateScope(student.studentId, student.gymId.toString())
            schedulePostLoginSync()
        }
    }

    /**
     * Lightweight probe (iOS `AuthenticationService.coldStartValidate`).
     * Only definitive session death returns [ColdStartResult.Dead]; network/robot stay signed in.
     */
    suspend fun coldStartValidate(student: Student): ColdStartResult {
        val credentials = credentialStore.loadCredentials(student.studentId)
            ?: return ColdStartResult.Dead

        return try {
            val result = engine.execute(
                W4Request(
                    url = W4Urls.route(W4Urls.Routes.HOME),
                    method = "GET",
                    priority = FetchPriority.Opportunistic,
                    studentId = student.studentId,
                ),
                credentials,
            )
            // Persist post-probe rotations (iOS updates keychain on success).
            credentialStore.saveCredentials(result.credentials, student.studentId)
            ColdStartResult.Ok
        } catch (_: W4Error.SessionExpired) {
            ColdStartResult.Dead
        } catch (_: W4Error.InvalidCredentials) {
            ColdStartResult.Dead
        } catch (e: W4Error.MissingCookies) {
            ColdStartResult.Dead
        } catch (e: W4Error) {
            // Offline, robot, network, parse — keep user signed in (iOS parity).
            ColdStartResult.Deferred(e)
        } catch (e: Exception) {
            ColdStartResult.Deferred(e)
        }
    }
}

/**
 * Result of cold-start W4 probe.
 */
sealed class ColdStartResult {
    data object Ok : ColdStartResult()
    data object Dead : ColdStartResult()
    data class Deferred(val cause: Throwable) : ColdStartResult()
}
