package dk.betterlectio.android.core.lectio.auth

import com.posthog.PostHog
import dk.betterlectio.android.BuildConfig
import dk.betterlectio.android.core.lectio.http.LectioHttpEngine
import dk.betterlectio.android.core.lectio.model.FetchPriority
import dk.betterlectio.android.core.lectio.model.LectioCredentials
import dk.betterlectio.android.core.lectio.model.LectioError
import dk.betterlectio.android.core.lectio.model.LectioRequest
import dk.betterlectio.android.core.lectio.scrape.LectioUrls
import dk.betterlectio.android.core.lectio.scrape.StudentIdentityParser
import dk.betterlectio.android.core.lectio.session.CredentialStore
import dk.betterlectio.android.core.lectio.session.LastSchoolReason
import dk.betterlectio.android.core.lectio.session.LastSchoolStore
import dk.betterlectio.android.core.lectio.session.SessionController
import dk.betterlectio.android.core.lectio.session.SessionExternalWiper
import dk.betterlectio.android.core.model.School
import dk.betterlectio.android.core.model.Student
import dk.betterlectio.android.core.result.AppResult
import dk.betterlectio.android.feature.directory.AvatarRepository
import dk.betterlectio.android.feature.directory.DirectorySyncService
import dk.betterlectio.android.feature.messages.MessageListPrefetcher
import dk.betterlectio.android.feature.referral.ReferralCoordinator
import dk.betterlectio.android.feature.settings.SettingsStore
import dk.betterlectio.android.feature.supabase.SupabaseAuthService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Completes MitID/WebView auth: validate cookies against Lectio, persist, install session.
 * iOS parity: AuthenticationService.completeAuthentication / coldStartValidate / wipeAuthState
 * Flutter inspiration: uniloginLogin(callbackUrl) then checkIfLoggedIn.
 */
@Singleton
class AuthSessionInstaller @Inject constructor(
    private val engine: LectioHttpEngine,
    private val credentialStore: CredentialStore,
    private val sessionController: SessionController,
    private val webViewCookieExtractor: WebViewCookieExtractor,
    private val sessionExternalWiper: SessionExternalWiper,
    private val lastSchoolStore: LastSchoolStore,
    private val supabaseAuth: SupabaseAuthService,
    private val settingsStore: SettingsStore,
    private val directorySync: DirectorySyncService,
    private val messagePrefetcher: MessageListPrefetcher,
    private val avatarRepository: AvatarRepository,
    private val referralCoordinator: ReferralCoordinator,
) {
    private val bgScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /**
     * Use after WebView finished forside/unilogin callback — reads cookies from CookieManager.
     *
     * @param callbackUrl final WebView URL (UniLogin integration or forside). When this is the
     * UniLogin integration callback, we re-request it over HTTP (Flutter `uniloginLogin`) so
     * Lectio can finish minting session cookies even if WebView jar was incomplete.
     */
    suspend fun completeLoginFromWebView(
        school: School,
        callbackUrl: String? = null,
    ): AppResult<Student> {
        return when (val extracted = webViewCookieExtractor.extractFromCookieManager(school.id.toString())) {
            is AppResult.Failure -> extracted
            is AppResult.Success -> completeLogin(extracted.data, school, callbackUrl)
        }
    }

    /**
     * Validate [credentials], parse student identity, persist, install session.
     *
     * Probe order:
     * 0. Optional **UniLogin integration callback** HTTP GET (Flutter)
     * 1. **SkemaNy.aspx** — iOS `validateCredentialsAndGetStudentInfo`
     * 2. **forside.aspx** — Flutter `checkIfLoggedIn`
     * 3. Fallback: person id embedded in [callbackUrl]
     */
    suspend fun completeLogin(
        credentials: LectioCredentials,
        school: School,
        callbackUrl: String? = null,
    ): AppResult<Student> {
        var latestCreds = credentials.seededIsLoggedIn()
        val skemaUrl = LectioUrls.buildUrl(school.id, "SkemaNy.aspx")
        val forsideUrl = LectioUrls.forsideUrl(school.id)

        return try {
            // Flutter: request(unilogin.aspx) so Set-Cookie from the integration hop lands in our jar.
            if (!callbackUrl.isNullOrBlank() &&
                MitIdAuthUrls.isUniloginIntegrationCallback(callbackUrl)
            ) {
                val callbackHttp = callbackUrl.toHttpUrlOrNull()
                if (callbackHttp != null) {
                    Timber.i("Login: replaying UniLogin callback over HTTP")
                    val replay = engine.execute(
                        LectioRequest(
                            url = callbackHttp,
                            method = "GET",
                            priority = FetchPriority.Important,
                            studentId = null,
                        ),
                        latestCreds,
                    )
                    latestCreds = replay.credentials
                    val fromCallbackHtml = StudentIdentityParser.parse(replay.response.body)
                    logIdentityProbe("UniLogin callback replay", replay.response.body, fromCallbackHtml)
                    if (!fromCallbackHtml.personId.isNullOrBlank()) {
                        return finishLogin(
                            personId = fromCallbackHtml.personId!!,
                            name = fromCallbackHtml.name,
                            pictureId = fromCallbackHtml.pictureId,
                            school = school,
                            credentials = latestCreds,
                        )
                    }
                }
            }

            var first = engine.execute(
                LectioRequest(
                    url = skemaUrl,
                    method = "GET",
                    priority = FetchPriority.Important,
                    studentId = null,
                ),
                latestCreds,
            )

            var identity = StudentIdentityParser.parse(first.response.body)
            latestCreds = first.credentials
            Timber.i(
                "Login probe SkemaNy personId=%s finalUrl=%s bodyLen=%d looksLogin=%s",
                identity.personId,
                first.response.finalUrl,
                first.response.body.length,
                looksLikeLoginHtml(first.response.body),
            )
            logIdentityProbe("SkemaNy", first.response.body, identity)

            // Lectio sometimes finishes the MitID callback before the authenticated page
            // chrome includes elevid/laererid. Retry with the rotated jar, matching the
            // Supabase token helper used by iOS.
            var skemaAttempt = 0
            while (identity.personId.isNullOrBlank() &&
                !looksLikeLoginHtml(first.response.body) &&
                skemaAttempt < 2
            ) {
                delay(400L * (skemaAttempt + 1))
                first = engine.execute(
                    LectioRequest(
                        url = skemaUrl,
                        method = "GET",
                        priority = FetchPriority.Important,
                        studentId = null,
                    ),
                    latestCreds,
                )
                latestCreds = first.credentials
                identity = StudentIdentityParser.parse(first.response.body)
                Timber.i(
                    "Login probe SkemaNy retry=%d personId=%s finalUrl=%s bodyLen=%d looksLogin=%s",
                    skemaAttempt + 1,
                    identity.personId,
                    first.response.finalUrl,
                    first.response.body.length,
                    looksLikeLoginHtml(first.response.body),
                )
                logIdentityProbe("SkemaNy retry ${skemaAttempt + 1}", first.response.body, identity)
                skemaAttempt++
            }

            if (identity.personId.isNullOrBlank()) {
                val forside = engine.execute(
                    LectioRequest(
                        url = forsideUrl,
                        method = "GET",
                        priority = FetchPriority.Important,
                        studentId = null,
                    ),
                    latestCreds,
                )
                latestCreds = forside.credentials
                identity = StudentIdentityParser.parse(forside.response.body)
                Timber.i(
                    "Login probe forside personId=%s finalUrl=%s bodyLen=%d looksLogin=%s",
                    identity.personId,
                    forside.response.finalUrl,
                    forside.response.body.length,
                    looksLikeLoginHtml(forside.response.body),
                )
                logIdentityProbe("forside", forside.response.body, identity)
            }

            // Last resort: elevid in callback / final URL query.
            val personId = identity.personId
                ?: callbackUrl?.let { MitIdAuthUrls.personIdFromUrl(it) }
                ?: first.response.finalUrl.toString().let { MitIdAuthUrls.personIdFromUrl(it) }

            if (personId.isNullOrBlank()) {
                Timber.w(
                    "Login parse failed. cookiePreview names present; body sample: %s",
                    first.response.body.take(400).replace('\n', ' '),
                )
                return AppResult.Failure(
                    LectioError.Parse(
                        "Could not parse student id from Lectio " +
                            "(no elevid/laererid — session may be incomplete after MitID)",
                    ).toAppError(),
                )
            }

            return finishLogin(
                personId = personId,
                name = identity.name,
                pictureId = identity.pictureId,
                school = school,
                credentials = latestCreds,
            )
        } catch (e: LectioError) {
            Timber.w(e, "Login validation failed")
            AppResult.Failure(e.toAppError())
        } catch (e: Exception) {
            Timber.e(e, "Login validation crashed")
            AppResult.Failure(LectioError.Unknown(e.message, e).toAppError())
        }
    }

    private suspend fun finishLogin(
        personId: String,
        name: String?,
        pictureId: String?,
        school: School,
        credentials: LectioCredentials,
    ): AppResult<Student> {
        val forsideUrl = LectioUrls.forsideUrl(school.id)
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
            LectioRequest(
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

        PostHog.identify(
            distinctId = personId,
            userProperties = mapOf(
                "gym_id" to school.id,
                "school_name" to school.name,
            ),
        )
        PostHog.capture(
            event = "login_completed",
            properties = mapOf("login_method" to "mitid"),
        )

        bgScope.launch {
            supabaseAuth.authenticateAndMarkReady(finalCreds, personId, school.id)
            settingsStore.activateScope(student.studentId, student.gymId.toString())
            settingsStore.syncSubjectsFromSupabase(student)
            referralCoordinator.tryFinalizeAfterAuth(student)
            schedulePostLoginSync()
        }

        Timber.i("Login complete studentId=%s gymId=%s", personId, school.id)
        return AppResult.Success(student)
    }

    private fun looksLikeLoginHtml(html: String): Boolean {
        val lower = html.lowercase()
        return lower.contains("login.aspx") ||
            lower.contains("m\$content\$username") ||
            lower.contains("m_content_username") ||
            lower.contains("unilogin") && lower.contains("log ind")
    }

    private fun logIdentityProbe(
        label: String,
        html: String,
        identity: dk.betterlectio.android.core.lectio.scrape.StudentIdentity,
    ) {
        if (!BuildConfig.DEBUG) return
        val signals = StudentIdentityParser.debugSignals(html)
        Timber.d(
            "Login identity probe [%s]: parsed student=%s teacher=%s name=%s picture=%s signals=%s",
            label,
            identity.studentId,
            identity.teacherId,
            identity.name?.take(80),
            identity.pictureId,
            signals,
        )
    }

    fun enterDemo(): Student {
        sessionController.installDemoSession()
        PostHog.capture(event = "demo_entered")
        bgScope.launch {
            supabaseAuth.ensureSessionIfNeeded(Student.Demo)
            schedulePostLoginSync()
        }
        return Student.Demo
    }

    /**
     * Directory full-catalog offline snapshot + message folder/thread prefetch.
     * Fire-and-forget; never prompts for background/battery permissions.
     */
    private fun schedulePostLoginSync() {
        bgScope.launch {
            sessionController.currentStudent?.let { s ->
                if (!s.pictureId.isNullOrBlank()) {
                    runCatching {
                        avatarRepository.seedSelf(s.pictureId, s.studentId, s.gymId)
                    }
                }
            }
            runCatching { directorySync.syncFullCatalog() }
                .onFailure { Timber.w(it, "Directory catalog sync failed") }
        }
        messagePrefetcher.schedulePrefetch()
    }

    /**
     * iOS `wipeAuthState` / logout — clear UI session immediately, then wipe WebView jar
     * so the next MitID login does not inherit a stale UniLogin session.
     */
    fun logout() {
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
        PostHog.capture(event = "logged_out")
        PostHog.reset()
        sessionController.clearSession()
        bgScope.launch {
            runCatching { sessionExternalWiper.wipeExternalAuthState() }
                .onFailure { Timber.w(it, "External wipe on logout failed") }
        }
    }

    /**
     * Unexpected Lectio session death (extension parity: `lectio session lost`).
     * No-op if already signed out so cold-start + HTTP expiry do not double-fire.
     */
    private fun forceLogoutSessionLost(detectionSource: String) {
        val student = sessionController.currentStudent ?: return
        if (student.isDemo) return
        lastSchoolStore.remember(student, LastSchoolReason.SESSION_EXPIRED)
        PostHog.capture(
            event = "lectio session lost",
            properties = mapOf(
                "school_id" to student.gymId.toString(),
                "school_name" to (student.schoolName ?: ""),
                "detection_source" to detectionSource,
                "platform" to "android",
            ),
        )
        PostHog.reset()
        sessionController.clearSession()
        bgScope.launch {
            runCatching { sessionExternalWiper.wipeExternalAuthState() }
                .onFailure { Timber.w(it, "External wipe after session lost failed") }
        }
    }

    /**
     * iOS: when no stored student, wipe residual WK/keychain/Supabase before LoginView.
     * Call after [SessionController.restore] when state is unauthenticated.
     */
    fun wipeResidualAuthState() {
        bgScope.launch {
            runCatching { sessionExternalWiper.wipeExternalAuthState() }
            Timber.i("Residual auth state wiped (unauthenticated cold start)")
        }
    }

    /**
     * Cold-start sequence (iOS AuthenticationViewModel.checkStoredCredentials Task):
     * 1. coldStartValidate — cheapest Lectio probe; definitive death → logout
     * 2. ensureSupabaseSession
     * 3. directory / message prefetch
     *
     * Strictly sequential so parallel autologin rotation races do not kill the session.
     */
    fun onColdStart(student: Student): Job {
        return bgScope.launch {
            if (student.isDemo) {
                supabaseAuth.ensureSessionIfNeeded(student)
                schedulePostLoginSync()
                return@launch
            }

            when (val probe = coldStartValidate(student)) {
                ColdStartResult.Dead -> {
                    Timber.w("Cold-start validation: session dead — logging out")
                    // Engine may already have emitted sessionExpired → lectio session lost.
                    // Only wipe + analytics if we are still authenticated.
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

            supabaseAuth.ensureSessionIfNeeded(student)
            settingsStore.activateScope(student.studentId, student.gymId.toString())
            settingsStore.syncSubjectsFromSupabase(student)
            referralCoordinator.tryFinalizeAfterAuth(student)
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
                LectioRequest(
                    url = LectioUrls.buildUrl(student.gymId, "SkemaNy.aspx"),
                    method = "GET",
                    priority = FetchPriority.Opportunistic,
                    studentId = student.studentId,
                ),
                credentials,
            )
            // Persist post-probe rotations (iOS updates keychain on success).
            credentialStore.saveCredentials(result.credentials, student.studentId)
            ColdStartResult.Ok
        } catch (_: LectioError.SessionExpired) {
            ColdStartResult.Dead
        } catch (_: LectioError.InvalidCredentials) {
            ColdStartResult.Dead
        } catch (e: LectioError.MissingCookies) {
            ColdStartResult.Dead
        } catch (e: LectioError) {
            // Offline, robot, network, parse — keep user signed in (iOS parity).
            ColdStartResult.Deferred(e)
        } catch (e: Exception) {
            ColdStartResult.Deferred(e)
        }
    }

    /**
     * @deprecated Prefer [onColdStart] which validates first. Kept for call-site clarity.
     */
    fun ensureSupabaseSession(student: Student): Job = onColdStart(student)
}

/**
 * Result of cold-start Lectio probe.
 */
sealed class ColdStartResult {
    data object Ok : ColdStartResult()
    data object Dead : ColdStartResult()
    data class Deferred(val cause: Throwable) : ColdStartResult()
}
