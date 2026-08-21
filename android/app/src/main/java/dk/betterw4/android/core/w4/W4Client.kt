package dk.betterw4.android.core.w4

import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.core.w4.http.W4HttpEngine
import dk.betterw4.android.core.w4.http.W4UserAgent
import dk.betterw4.android.core.w4.model.FetchPriority
import dk.betterw4.android.core.w4.model.W4Credentials
import dk.betterw4.android.core.w4.model.W4Error
import dk.betterw4.android.core.w4.model.W4Request
import dk.betterw4.android.core.w4.model.W4Response
import dk.betterw4.android.core.w4.scrape.W4Form
import dk.betterw4.android.core.w4.session.CredentialStore
import dk.betterw4.android.core.w4.session.SessionController
import dk.betterw4.android.core.w4.session.SessionEvents
import okhttp3.HttpUrl
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Public façade for W4 HTTP. Feature scrapers should depend on this, not the engine.
 *
 * [routeOrUrl] is a Yii `r=` value (`academics/timetable/mytimetable`), a path, or an absolute URL.
 */
interface W4Client {
    suspend fun get(
        routeOrUrl: String,
        query: Map<String, String> = emptyMap(),
        priority: FetchPriority = FetchPriority.Important,
        credentials: W4Credentials? = null,
        studentId: String? = null,
        allowLoginPage: Boolean = false,
    ): AppResult<W4Response>

    suspend fun postForm(
        routeOrUrl: String,
        fields: Map<String, String>,
        query: Map<String, String> = emptyMap(),
        priority: FetchPriority = FetchPriority.Important,
        credentials: W4Credentials? = null,
        studentId: String? = null,
        allowLoginPage: Boolean = false,
    ): AppResult<W4Response>

    /** Form POST variant for HTML controls whose names repeat, such as `items[]`. */
    suspend fun postForm(
        routeOrUrl: String,
        fields: List<Pair<String, String>>,
        query: Map<String, String> = emptyMap(),
        priority: FetchPriority = FetchPriority.Important,
        credentials: W4Credentials? = null,
        studentId: String? = null,
        allowLoginPage: Boolean = false,
    ): AppResult<W4Response> = postForm(
        routeOrUrl,
        fields.toMap(),
        query,
        priority,
        credentials,
        studentId,
        allowLoginPage,
    )

    /**
     * jQuery `$.post` — urlencoded + `X-Requested-With: XMLHttpRequest`.
     * 403 + `Login Required` is session death; other 403 is forbidden; 409 is a server error.
     */
    suspend fun postAjax(
        routeOrUrl: String,
        fields: Map<String, String>,
        query: Map<String, String> = emptyMap(),
        priority: FetchPriority = FetchPriority.Important,
        credentials: W4Credentials? = null,
        studentId: String? = null,
    ): AppResult<W4Response>

    suspend fun postMultipart(
        routeOrUrl: String,
        body: ByteArray,
        contentType: String,
        query: Map<String, String> = emptyMap(),
        priority: FetchPriority = FetchPriority.Important,
        credentials: W4Credentials? = null,
        studentId: String? = null,
    ): AppResult<W4Response>

    /**
     * GET [routeOrUrl] → merge Yii fields + [extra] + submit button → POST same URL.
     */
    suspend fun postYiiForm(
        routeOrUrl: String,
        extra: Map<String, String> = emptyMap(),
        submitName: String = "yt0",
        submitValue: String? = null,
        query: Map<String, String> = emptyMap(),
        priority: FetchPriority = FetchPriority.Important,
        credentials: W4Credentials? = null,
        studentId: String? = null,
        allowLoginPage: Boolean = false,
    ): AppResult<W4Response>

    suspend fun getBytes(
        routeOrUrl: String,
        query: Map<String, String> = emptyMap(),
        priority: FetchPriority = FetchPriority.Important,
        credentials: W4Credentials? = null,
        studentId: String? = null,
    ): AppResult<ByteArray>

    fun url(routeOrUrl: String, query: Map<String, String> = emptyMap()): HttpUrl
}

@Singleton
class DefaultW4Client @Inject constructor(
    private val engine: W4HttpEngine,
    private val credentialStore: CredentialStore,
    private val sessionController: SessionController,
    private val sessionEvents: SessionEvents,
) : W4Client {

    override suspend fun get(
        routeOrUrl: String,
        query: Map<String, String>,
        priority: FetchPriority,
        credentials: W4Credentials?,
        studentId: String?,
        allowLoginPage: Boolean,
    ): AppResult<W4Response> = execute(
        routeOrUrl = routeOrUrl,
        query = query,
        method = "GET",
        body = null,
        headers = emptyMap(),
        priority = priority,
        credentials = credentials,
        studentId = studentId,
        allowLoginPage = allowLoginPage,
        ajax = false,
    )

    override suspend fun postForm(
        routeOrUrl: String,
        fields: Map<String, String>,
        query: Map<String, String>,
        priority: FetchPriority,
        credentials: W4Credentials?,
        studentId: String?,
        allowLoginPage: Boolean,
    ): AppResult<W4Response> = execute(
        routeOrUrl = routeOrUrl,
        query = query,
        method = "POST",
        body = encodeForm(fields),
        headers = mapOf("Content-Type" to "application/x-www-form-urlencoded; charset=UTF-8"),
        priority = priority,
        credentials = credentials,
        studentId = studentId,
        allowLoginPage = allowLoginPage,
        ajax = false,
    )

    override suspend fun postForm(
        routeOrUrl: String,
        fields: List<Pair<String, String>>,
        query: Map<String, String>,
        priority: FetchPriority,
        credentials: W4Credentials?,
        studentId: String?,
        allowLoginPage: Boolean,
    ): AppResult<W4Response> = execute(
        routeOrUrl = routeOrUrl,
        query = query,
        method = "POST",
        body = W4Form.encode(fields),
        headers = mapOf("Content-Type" to "application/x-www-form-urlencoded; charset=UTF-8"),
        priority = priority,
        credentials = credentials,
        studentId = studentId,
        allowLoginPage = allowLoginPage,
        ajax = false,
    )

    override suspend fun postAjax(
        routeOrUrl: String,
        fields: Map<String, String>,
        query: Map<String, String>,
        priority: FetchPriority,
        credentials: W4Credentials?,
        studentId: String?,
    ): AppResult<W4Response> = execute(
        routeOrUrl = routeOrUrl,
        query = query,
        method = "POST",
        body = encodeForm(fields),
        headers = mapOf(
            "Content-Type" to "application/x-www-form-urlencoded; charset=UTF-8",
            "X-Requested-With" to W4UserAgent.AJAX,
        ),
        priority = priority,
        credentials = credentials,
        studentId = studentId,
        allowLoginPage = false,
        ajax = true,
    )

    override suspend fun postMultipart(
        routeOrUrl: String,
        body: ByteArray,
        contentType: String,
        query: Map<String, String>,
        priority: FetchPriority,
        credentials: W4Credentials?,
        studentId: String?,
    ): AppResult<W4Response> = execute(
        routeOrUrl = routeOrUrl,
        query = query,
        method = "POST",
        body = body,
        headers = mapOf("Content-Type" to contentType),
        priority = priority,
        credentials = credentials,
        studentId = studentId,
        allowLoginPage = false,
        ajax = false,
    )

    override suspend fun postYiiForm(
        routeOrUrl: String,
        extra: Map<String, String>,
        submitName: String,
        submitValue: String?,
        query: Map<String, String>,
        priority: FetchPriority,
        credentials: W4Credentials?,
        studentId: String?,
        allowLoginPage: Boolean,
    ): AppResult<W4Response> {
        val page = get(routeOrUrl, query, priority, credentials, studentId, allowLoginPage)
        if (page is AppResult.Failure) return page
        val html = (page as AppResult.Success).data.body
        val fields = YiiForm.fieldsForSubmit(
            html = html,
            extra = extra,
            submitName = submitName,
            submitValue = submitValue,
        )
        return postForm(routeOrUrl, fields, query, priority, credentials, studentId, allowLoginPage)
    }

    override suspend fun getBytes(
        routeOrUrl: String,
        query: Map<String, String>,
        priority: FetchPriority,
        credentials: W4Credentials?,
        studentId: String?,
    ): AppResult<ByteArray> = when (
        val result = get(routeOrUrl, query, priority, credentials, studentId)
    ) {
        is AppResult.Success -> AppResult.Success(result.data.bytes)
        is AppResult.Failure -> result
    }

    override fun url(routeOrUrl: String, query: Map<String, String>): HttpUrl =
        W4Urls.resolve(routeOrUrl, query)

    private suspend fun execute(
        routeOrUrl: String,
        query: Map<String, String>,
        method: String,
        body: ByteArray?,
        headers: Map<String, String>,
        priority: FetchPriority,
        credentials: W4Credentials?,
        studentId: String?,
        allowLoginPage: Boolean,
        ajax: Boolean,
    ): AppResult<W4Response> {
        val student = sessionController.currentStudent
        if (student?.isDemo == true && credentials == null) {
            return AppResult.Failure(
                W4Error.Unknown("Demo mode: no network W4 calls").toAppError(),
            )
        }

        val sid = studentId ?: student?.studentId
        val url = try {
            W4Urls.resolve(routeOrUrl, query)
        } catch (e: Exception) {
            return AppResult.Failure(W4Error.Unknown(e.message, e).toAppError())
        }

        val creds = resolveCredentials(credentials, sid, allowLoginPage)
            ?: return AppResult.Failure(W4Error.MissingCookies.toAppError())

        val request = W4Request(
            url = url,
            method = method,
            body = body,
            headers = headers,
            priority = priority,
            studentId = sid,
            allowLoginPage = allowLoginPage,
            ajax = ajax,
        )

        return try {
            val result = engine.execute(request, creds)
            AppResult.Success(result.response)
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: W4Error) {
            AppResult.Failure(e.toAppError())
        } catch (e: Exception) {
            AppResult.Failure(W4Error.Unknown(e.message, e).toAppError())
        }
    }

    private fun resolveCredentials(
        explicit: W4Credentials?,
        studentId: String?,
        allowLoginPage: Boolean,
    ): W4Credentials? {
        if (explicit != null) {
            return if (explicit.sessionId.isEmpty() && !allowLoginPage) {
                forceExpireIfAuthenticated("explicit credentials have empty PHPSESSID")
                null
            } else {
                explicit
            }
        }
        if (studentId == null) {
            if (allowLoginPage) return W4Credentials(sessionId = "")
            forceExpireIfAuthenticated("no studentId for W4 request")
            return null
        }
        val stored = credentialStore.loadCredentials(studentId)
        if (stored == null || stored.sessionId.isEmpty()) {
            forceExpireIfAuthenticated("missing/empty PHPSESSID for studentId=$studentId")
            return null
        }
        return stored
    }

    private fun forceExpireIfAuthenticated(reason: String) {
        val student = sessionController.currentStudent
        if (student == null || student.isDemo) return
        Timber.w("Mid-session missing PHPSESSID — emitting sessionExpired (%s)", reason)
        sessionEvents.emitSessionExpired()
    }

    private fun encodeForm(fields: Map<String, String>): ByteArray = W4Form.encode(fields)
}
