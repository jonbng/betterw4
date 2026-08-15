package dk.betterlectio.android.feature.supabase

import dk.betterlectio.android.BuildConfig
import dk.betterlectio.android.core.lectio.auth.LectioQrMinter
import dk.betterlectio.android.core.lectio.model.LectioCredentials
import dk.betterlectio.android.core.lectio.session.CredentialStore
import dk.betterlectio.android.core.model.Student
import dk.betterlectio.android.core.result.AppResult
import io.github.jan.supabase.auth.OtpType
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.functions.functions
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.rpc
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.contentType
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Lectio QR → Supabase session via Edge Function `lectio-auth`
 * (iOS: `SupabaseAuthService`). Does not transfer Lectio cookies.
 */
@Singleton
class SupabaseAuthService @Inject constructor(
    private val manager: SupabaseManager,
    private val credentialStore: CredentialStore,
    private val lectioQrMinter: LectioQrMinter,
) {
    private val mutex = Mutex()
    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

    /**
     * Best-effort: mint Lectio QR, invoke lectio-auth, verify magic-link OTP.
     * Never throws into Lectio auth paths. Device Lectio cookies stay local.
     */
    suspend fun authenticateWithLectio(
        credentials: LectioCredentials,
        expectedStudentId: String,
        gymId: Int,
    ): SupabaseSessionState {
        val client = manager.client ?: run {
            Timber.w("SupabaseAuth: client not configured — skipping")
            return SupabaseSessionState.Unavailable(SupabaseUnavailableReason.NOT_CONFIGURED)
        }

        return mutex.withLock {
            Timber.i("SupabaseAuth: starting QR mint + lectio-auth")
            try {
                val qr = when (
                    val minted = lectioQrMinter.mint(credentials, expectedStudentId, gymId)
                ) {
                    is AppResult.Success -> minted.data
                    is AppResult.Failure -> {
                        Timber.w("SupabaseAuth: QR mint failed: %s", minted.error)
                        return@withLock SupabaseSessionState.Unavailable(
                            SupabaseUnavailableReason.QR_MINT_FAILED,
                        )
                    }
                }

                val response = client.functions.invoke("lectio-auth") {
                    contentType(ContentType.Application.Json)
                    setBody(
                        json.encodeToString(
                            EdgeFunctionRequest.serializer(),
                            EdgeFunctionRequest(
                                qrId = qr.qrId,
                                userId = qr.userId,
                                schoolId = gymId.toString(),
                                client = ClientMetadata(
                                    platform = "android",
                                    appVersion = BuildConfig.VERSION_NAME,
                                    appBuild = BuildConfig.VERSION_CODE.toString(),
                                ),
                            ),
                        ),
                    )
                }
                val body = response.bodyAsText()
                val decoded = json.decodeFromString(EdgeFunctionResponse.serializer(), body)

                if (decoded.studentId != expectedStudentId) {
                    Timber.e(
                        "SupabaseAuth: identity mismatch expected=%s actual=%s requestId=%s",
                        expectedStudentId,
                        decoded.studentId,
                        decoded.requestId,
                    )
                    return@withLock SupabaseSessionState.Unavailable(
                        SupabaseUnavailableReason.IDENTITY_MISMATCH,
                    )
                }

                Timber.i(
                    "SupabaseAuth: received magic link token requestId=%s",
                    decoded.requestId,
                )

                client.auth.verifyEmailOtp(
                    type = OtpType.Email.MAGIC_LINK,
                    tokenHash = decoded.tokenHash,
                )
                Timber.i("SupabaseAuth: authentication successful")
                if (client.auth.currentSessionOrNull() == null) {
                    SupabaseSessionState.Unavailable(
                        SupabaseUnavailableReason.AUTHENTICATION_FAILED,
                    )
                } else {
                    decoded.requestId?.let { requestId ->
                        try {
                            client.postgrest.rpc(
                                function = "confirm_auth_attempt",
                                parameters = ConfirmAttemptParams(requestId),
                            )
                        } catch (e: Exception) {
                            Timber.w(e, "SupabaseAuth: auth-attempt confirmation failed")
                        }
                    }
                    SupabaseSessionState.Ready
                }
            } catch (e: Exception) {
                Timber.w(e, "SupabaseAuth: authentication failed")
                SupabaseSessionState.Unavailable(
                    SupabaseUnavailableReason.AUTHENTICATION_FAILED,
                )
            }
        }
    }

    /**
     * Cold-start: if SDK has no session, mint a fresh Lectio QR from stored cookies
     * and re-authenticate via lectio-auth.
     */
    suspend fun ensureSessionIfNeeded(student: Student): SupabaseSessionState {
        val result = when {
            student.isDemo -> {
                SupabaseSessionState.Unavailable(SupabaseUnavailableReason.DEMO_SESSION)
            }
            manager.client == null -> {
                SupabaseSessionState.Unavailable(SupabaseUnavailableReason.NOT_CONFIGURED)
            }
            else -> {
                val client = checkNotNull(manager.client)
                runCatching { client.auth.awaitInitialization() }
                if (client.auth.currentSessionOrNull() != null) {
                    Timber.d("SupabaseAuth: existing session present")
                    SupabaseSessionState.Ready
                } else {
                    val credentials = credentialStore.loadCredentials(student.studentId)
                    if (credentials == null) {
                        SupabaseSessionState.Unavailable(
                            SupabaseUnavailableReason.MISSING_CREDENTIALS,
                        )
                    } else {
                        Timber.i("SupabaseAuth: no cached session — re-authenticating via lectio-auth")
                        authenticateWithLectio(credentials, student.studentId, student.gymId)
                    }
                }
            }
        }
        manager.completeSessionBootstrap(result)
        return result
    }

    suspend fun authenticateAndMarkReady(
        credentials: LectioCredentials,
        studentId: String,
        gymId: Int,
    ): SupabaseSessionState {
        val result = authenticateWithLectio(credentials, studentId, gymId)
        manager.completeSessionBootstrap(result)
        return result
    }

    suspend fun signOutLocal() {
        val client = manager.client
        try {
            client?.auth?.signOut()
        } catch (e: Exception) {
            Timber.w(e, "SupabaseAuth: local signOut failed")
        } finally {
            manager.resetSessionReady()
        }
    }

    @Serializable
    private data class EdgeFunctionRequest(
        val qrId: String,
        val userId: String,
        val schoolId: String,
        val client: ClientMetadata,
    )

    @Serializable
    private data class ClientMetadata(
        val platform: String,
        @SerialName("app_version") val appVersion: String,
        @SerialName("app_build") val appBuild: String,
    )

    @Serializable
    private data class ConfirmAttemptParams(
        @SerialName("p_request_id") val requestId: String,
        @SerialName("p_completion_kind") val completionKind: String = "session_ready",
    )

    @Serializable
    private data class EdgeFunctionResponse(
        @SerialName("token_hash") val tokenHash: String,
        val email: String,
        @SerialName("student_id") val studentId: String? = null,
        @SerialName("school_id") val schoolId: String? = null,
        @SerialName("was_first_install") val wasFirstInstall: Boolean? = null,
        @SerialName("request_id") val requestId: String? = null,
    )
}
