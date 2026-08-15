package dk.betterlectio.android.core.lectio

import dk.betterlectio.android.core.lectio.http.LectioHttpEngine
import dk.betterlectio.android.core.lectio.model.FetchPriority
import dk.betterlectio.android.core.lectio.model.LectioCredentials
import dk.betterlectio.android.core.lectio.model.LectioError
import dk.betterlectio.android.core.lectio.model.LectioRequest
import dk.betterlectio.android.core.lectio.model.LectioResponse
import dk.betterlectio.android.core.lectio.scrape.AspNetForm
import dk.betterlectio.android.core.lectio.scrape.LectioUrls
import dk.betterlectio.android.core.lectio.session.CredentialStore
import dk.betterlectio.android.core.lectio.session.SessionController
import dk.betterlectio.android.core.lectio.session.SessionEvents
import dk.betterlectio.android.core.result.AppResult
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import timber.log.Timber
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Public façade for Lectio HTTP. Feature scrapers depend on this only.
 */
interface LectioClient {
    /**
     * @param pathOrUrl Absolute URL or path relative to the active student's gym.
     * @param credentials Explicit creds (login validation); otherwise session store.
     * @param gymId Override gym; defaults to current student.
     */
    suspend fun get(
        pathOrUrl: String,
        priority: FetchPriority = FetchPriority.Important,
        credentials: LectioCredentials? = null,
        studentId: String? = null,
        gymId: Int? = null,
    ): AppResult<LectioResponse>

    suspend fun postForm(
        pathOrUrl: String,
        fields: Map<String, String>,
        priority: FetchPriority = FetchPriority.Important,
        credentials: LectioCredentials? = null,
        studentId: String? = null,
        gymId: Int? = null,
    ): AppResult<LectioResponse>

    /**
     * Multipart POST (e.g. Lectio `dokumentupload.aspx`).
     * [contentType] must include the multipart boundary.
     */
    suspend fun postMultipart(
        pathOrUrl: String,
        body: ByteArray,
        contentType: String,
        priority: FetchPriority = FetchPriority.Important,
        credentials: LectioCredentials? = null,
        studentId: String? = null,
        gymId: Int? = null,
    ): AppResult<LectioResponse>

    suspend fun getBytes(
        pathOrUrl: String,
        priority: FetchPriority = FetchPriority.Important,
        credentials: LectioCredentials? = null,
        studentId: String? = null,
        gymId: Int? = null,
    ): AppResult<ByteArray>

    /**
     * GET page → extract ASP.NET fields → POST with [eventTarget] + [extra].
     * Dart parity: postLoggedInPageSoup
     */
    suspend fun postback(
        pathOrUrl: String,
        eventTarget: String,
        extra: Map<String, String> = emptyMap(),
        priority: FetchPriority = FetchPriority.Important,
        credentials: LectioCredentials? = null,
        studentId: String? = null,
        gymId: Int? = null,
    ): AppResult<LectioResponse>

    fun buildUrl(path: String, gymId: Int? = null): HttpUrl
}

@Singleton
class DefaultLectioClient @Inject constructor(
    private val engine: LectioHttpEngine,
    private val credentialStore: CredentialStore,
    private val sessionController: SessionController,
    private val sessionEvents: SessionEvents,
) : LectioClient {

    override suspend fun get(
        pathOrUrl: String,
        priority: FetchPriority,
        credentials: LectioCredentials?,
        studentId: String?,
        gymId: Int?,
    ): AppResult<LectioResponse> = execute(
        pathOrUrl = pathOrUrl,
        method = "GET",
        body = null,
        headers = emptyMap(),
        priority = priority,
        credentials = credentials,
        studentId = studentId,
        gymId = gymId,
    )

    override suspend fun postForm(
        pathOrUrl: String,
        fields: Map<String, String>,
        priority: FetchPriority,
        credentials: LectioCredentials?,
        studentId: String?,
        gymId: Int?,
    ): AppResult<LectioResponse> {
        val encoded = fields.entries.joinToString("&") { (k, v) ->
            "${urlEncode(k)}=${urlEncode(v)}"
        }
        return execute(
            pathOrUrl = pathOrUrl,
            method = "POST",
            body = encoded.toByteArray(StandardCharsets.UTF_8),
            headers = mapOf("Content-Type" to "application/x-www-form-urlencoded; charset=UTF-8"),
            priority = priority,
            credentials = credentials,
            studentId = studentId,
            gymId = gymId,
        )
    }

    override suspend fun postMultipart(
        pathOrUrl: String,
        body: ByteArray,
        contentType: String,
        priority: FetchPriority,
        credentials: LectioCredentials?,
        studentId: String?,
        gymId: Int?,
    ): AppResult<LectioResponse> = execute(
        pathOrUrl = pathOrUrl,
        method = "POST",
        body = body,
        headers = mapOf("Content-Type" to contentType),
        priority = priority,
        credentials = credentials,
        studentId = studentId,
        gymId = gymId,
    )

    override suspend fun getBytes(
        pathOrUrl: String,
        priority: FetchPriority,
        credentials: LectioCredentials?,
        studentId: String?,
        gymId: Int?,
    ): AppResult<ByteArray> {
        return when (val result = get(pathOrUrl, priority, credentials, studentId, gymId)) {
            is AppResult.Success -> AppResult.Success(result.data.bytes)
            is AppResult.Failure -> result
        }
    }

    override suspend fun postback(
        pathOrUrl: String,
        eventTarget: String,
        extra: Map<String, String>,
        priority: FetchPriority,
        credentials: LectioCredentials?,
        studentId: String?,
        gymId: Int?,
    ): AppResult<LectioResponse> {
        val page = get(pathOrUrl, priority, credentials, studentId, gymId)
        if (page is AppResult.Failure) return page
        val html = (page as AppResult.Success).data.body
        // Smart resolve: merge full form + prefer live button names matching eventTarget
        val resolved = dk.betterlectio.android.core.lectio.scrape.SmartPostback.resolve(
            html = html,
            preferredTargets = listOf(eventTarget),
            extra = extra,
        )
        return postForm(pathOrUrl, resolved.fields, priority, credentials, studentId, gymId)
    }

    /**
     * Postback trying several event targets / content field patterns from a single GET.
     */
    suspend fun smartPostback(
        pathOrUrl: String,
        preferredTargets: List<String>,
        extra: Map<String, String> = emptyMap(),
        targetKeywords: List<String> = emptyList(),
        priority: FetchPriority = FetchPriority.Important,
    ): AppResult<LectioResponse> {
        val page = get(pathOrUrl, priority)
        if (page is AppResult.Failure) return page
        val html = (page as AppResult.Success).data.body
        val resolved = dk.betterlectio.android.core.lectio.scrape.SmartPostback.resolve(
            html = html,
            preferredTargets = preferredTargets,
            extra = extra,
            nameContainsAny = targetKeywords,
        )
        return postForm(pathOrUrl, resolved.fields, priority)
    }

    override fun buildUrl(path: String, gymId: Int?): HttpUrl {
        val resolvedGym = gymId
            ?: sessionController.currentStudent?.gymId
            ?: error("No gymId for relative path: $path")
        return LectioUrls.resolve(path, resolvedGym)
    }

    private suspend fun execute(
        pathOrUrl: String,
        method: String,
        body: ByteArray?,
        headers: Map<String, String>,
        priority: FetchPriority,
        credentials: LectioCredentials?,
        studentId: String?,
        gymId: Int?,
    ): AppResult<LectioResponse> {
        val student = sessionController.currentStudent
        if (student?.isDemo == true && credentials == null) {
            return AppResult.Failure(LectioError.Unknown("Demo mode: no network Lectio calls").toAppError())
        }

        val sid = studentId ?: student?.studentId
        val resolvedGym = gymId ?: student?.gymId
        val url = try {
            pathOrUrl.toHttpUrlOrNull() ?: LectioUrls.resolve(pathOrUrl, resolvedGym)
        } catch (e: Exception) {
            return AppResult.Failure(LectioError.Unknown(e.message, e).toAppError())
        }

        val creds = resolveCredentials(credentials, sid)
            ?: return AppResult.Failure(LectioError.MissingCookies.toAppError())

        val request = LectioRequest(
            url = url,
            method = method,
            body = body,
            headers = headers,
            priority = priority,
            studentId = sid,
        )

        return try {
            val result = engine.execute(request, creds)
            AppResult.Success(result.response)
        } catch (e: kotlinx.coroutines.CancellationException) {
            // Must not convert cancel into Failure — LazyList disposal cancels callers.
            throw e
        } catch (e: LectioError) {
            AppResult.Failure(e.toAppError())
        } catch (e: Exception) {
            AppResult.Failure(LectioError.Unknown(e.message, e).toAppError())
        }
    }

    /**
     * Load session credentials. If the user appears authenticated but the jar is gone/empty,
     * force session death (iOS-style) instead of leaving a zombie Authenticated UI.
     */
    private fun resolveCredentials(
        explicit: LectioCredentials?,
        studentId: String?,
    ): LectioCredentials? {
        if (explicit != null) {
            return if (explicit.autologinkey.isEmpty()) {
                forceExpireIfAuthenticated("explicit credentials have empty autologinkey")
                null
            } else {
                explicit
            }
        }
        if (studentId == null) {
            forceExpireIfAuthenticated("no studentId for Lectio request")
            return null
        }
        val stored = credentialStore.loadCredentials(studentId)
        if (stored == null || stored.autologinkey.isEmpty()) {
            forceExpireIfAuthenticated("missing/empty stored credentials for studentId=$studentId")
            return null
        }
        return stored
    }

    private fun forceExpireIfAuthenticated(reason: String) {
        val student = sessionController.currentStudent
        if (student == null || student.isDemo) return
        Timber.w("Mid-session missing credentials — emitting sessionExpired (%s)", reason)
        sessionEvents.emitSessionExpired()
    }

    private fun urlEncode(value: String): String =
        URLEncoder.encode(value, StandardCharsets.UTF_8.name()).replace("+", "%20")
}
