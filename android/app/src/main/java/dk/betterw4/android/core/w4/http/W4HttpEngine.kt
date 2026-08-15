package dk.betterw4.android.core.w4.http

import dk.betterw4.android.BuildConfig
import dk.betterw4.android.core.w4.W4Html
import dk.betterw4.android.core.w4.W4Session
import dk.betterw4.android.core.w4.cookie.CookieHeaderBuilder
import dk.betterw4.android.core.w4.cookie.W4CookieJar
import dk.betterw4.android.core.w4.model.W4Credentials
import dk.betterw4.android.core.w4.model.W4Error
import dk.betterw4.android.core.w4.model.W4Request
import dk.betterw4.android.core.w4.model.W4Response
import dk.betterw4.android.core.w4.session.CredentialStore
import dk.betterw4.android.core.w4.session.SessionEvents
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import timber.log.Timber
import java.io.IOException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import javax.inject.Inject
import javax.inject.Named
import javax.inject.Singleton

data class W4EngineResult(
    val response: W4Response,
    val credentials: W4Credentials,
)

/**
 * W4 HTTP loop: serial limiter, **no** OkHttp cookie jar, **manual** redirects,
 * merge non-empty `PHPSESSID` on every hop (README §4.1 / §5.4 / §5.5).
 */
@Singleton
class W4HttpEngine @Inject constructor(
    @param:Named("w4") private val client: OkHttpClient,
    private val credentialStore: CredentialStore,
    private val sessionEvents: SessionEvents,
    private val limiter: PriorityRequestLimiter,
) {
    private val maxRedirects = 5
    private val maxAttempts = 3

    suspend fun execute(
        request: W4Request,
        initialCredentials: W4Credentials,
    ): W4EngineResult = withContext(Dispatchers.IO) {
        var currentCredentials = initialCredentials
        var lastError: W4Error = W4Error.Unknown("No response")

        for (attempt in 0 until maxAttempts) {
            try {
                return@withContext limiter.withPermit(request.priority) {
                    val fresh = request.studentId
                        ?.let { credentialStore.loadCredentials(it) }
                        ?: currentCredentials
                    when (val outcome = performSingleAttempt(request, fresh)) {
                        is SingleAttemptOutcome.Success -> {
                            currentCredentials = outcome.credentials
                            W4EngineResult(outcome.response, outcome.credentials)
                        }
                        is SingleAttemptOutcome.Failure -> {
                            currentCredentials = outcome.credentials
                            throw outcome.error
                        }
                    }
                }
            } catch (e: W4Error.SessionExpired) {
                throw e
            } catch (e: W4Error.Forbidden) {
                throw e
            } catch (e: W4Error.ServerConflict) {
                throw e
            } catch (e: W4Error.InvalidCredentials) {
                lastError = e
                if (attempt < maxAttempts - 1) {
                    delay(if (attempt == 0) 500L else 1500L)
                }
            } catch (e: W4Error.Network) {
                lastError = e
                if (attempt < maxAttempts - 1 && isTransient(e.cause)) {
                    delay(1000)
                } else {
                    throw e
                }
            } catch (e: W4Error) {
                throw e
            } catch (e: IOException) {
                lastError = mapIoException(e)
                if (attempt < maxAttempts - 1 && isTransient(e)) {
                    delay(1000)
                } else {
                    throw lastError
                }
            }
        }

        if (lastError is W4Error.InvalidCredentials) {
            sessionEvents.emitSessionExpired()
            throw W4Error.SessionExpired
        }
        throw lastError
    }

    private sealed class SingleAttemptOutcome {
        data class Success(
            val response: W4Response,
            val credentials: W4Credentials,
        ) : SingleAttemptOutcome()

        data class Failure(
            val error: W4Error,
            val credentials: W4Credentials,
        ) : SingleAttemptOutcome()
    }

    private fun performSingleAttempt(
        request: W4Request,
        credentials: W4Credentials,
    ): SingleAttemptOutcome {
        var currentCredentials = credentials
        var currentUrl = request.url
        var redirectCount = 0
        var method = request.method
        var body = request.body

        fun fail(error: W4Error): SingleAttemptOutcome =
            SingleAttemptOutcome.Failure(error, currentCredentials)

        while (redirectCount <= maxRedirects) {
            val cookieHeader = CookieHeaderBuilder.build(currentCredentials)
            if (BuildConfig.DEBUG) {
                Timber.d(
                    "W4 %s %s | %s",
                    method,
                    currentUrl.encodedPath + (currentUrl.encodedQuery?.let { "?$it" } ?: ""),
                    CookieHeaderBuilder.redactedPreview(currentCredentials),
                )
            }

            val okRequest = Request.Builder()
                .url(currentUrl)
                .method(
                    method,
                    body?.toRequestBody(
                        request.headers["Content-Type"]?.toMediaType()
                            ?: FORM_URLENCODED,
                    ),
                )
                .header("User-Agent", W4UserAgent.VALUE)
                .header("Referer", W4UserAgent.REFERER)
                .apply {
                    if (cookieHeader.isNotBlank()) {
                        header("Cookie", cookieHeader)
                    }
                    if (request.ajax) {
                        header("X-Requested-With", W4UserAgent.AJAX)
                    } else if (method == "GET" && request.headers.keys.none { it.equals("Accept", true) }) {
                        header("Accept", "text/html")
                    }
                    request.headers.forEach { (k, v) ->
                        if (!k.equals("Cookie", ignoreCase = true)) {
                            header(k, v)
                        }
                    }
                }
                .build()

            client.newCall(okRequest).execute().use { response ->
                currentCredentials = mergeCookiesFromResponse(response, currentCredentials, request.studentId)

                when (response.code) {
                    in 200..299 -> {
                        val finalUrl = response.request.url
                        val bytes = response.body?.bytes() ?: ByteArray(0)
                        val html = W4Html.decode(bytes)
                        if (!request.allowLoginPage &&
                            (W4Session.isLoginUrl(finalUrl) || W4Html.isLoginHtml(html))
                        ) {
                            return fail(sessionDead(request.studentId))
                        }
                        return SingleAttemptOutcome.Success(
                            W4Response(
                                body = html,
                                bytes = bytes,
                                finalUrl = finalUrl,
                                statusCode = response.code,
                                contentType = response.header("Content-Type"),
                                contentDisposition = response.header("Content-Disposition"),
                                credentials = currentCredentials,
                            ),
                            currentCredentials,
                        )
                    }

                    301, 302, 303, 307, 308 -> {
                        val location = response.header("Location")
                            ?: return fail(W4Error.Unknown("Redirect without Location"))
                        val redirectUrl = resolveRedirect(currentUrl, location)
                            ?: return fail(W4Error.Unknown("Invalid redirect: $location"))

                        if (!request.allowLoginPage && W4Session.isLoginUrl(redirectUrl)) {
                            Timber.w("Redirect to site/login — session expired")
                            return fail(sessionDead(request.studentId))
                        }

                        if (redirectCount >= maxRedirects) {
                            Timber.w("Exceeded %d redirects — treating as session death", maxRedirects)
                            return fail(redirectBudgetError(request.studentId))
                        }

                        if (response.code == 303 || response.code == 302) {
                            method = "GET"
                            body = null
                        }
                        currentUrl = redirectUrl
                        redirectCount++
                    }

                    401, 403 -> {
                        val bytes = response.body?.bytes() ?: ByteArray(0)
                        val html = W4Html.decode(bytes)
                        return if (W4Html.isAjaxLoginRequired(html)) {
                            fail(sessionDead(request.studentId))
                        } else {
                            fail(W4Error.Forbidden)
                        }
                    }

                    409 -> {
                        val bytes = response.body?.bytes() ?: ByteArray(0)
                        val html = W4Html.decode(bytes)
                        return fail(W4Error.ServerConflict(html.trim()))
                    }

                    else -> return fail(W4Error.Http(response.code))
                }
            }
        }

        Timber.w("Redirect loop exceeded — treating as session death")
        return fail(redirectBudgetError(request.studentId))
    }

    private fun redirectBudgetError(studentId: String?): W4Error =
        if (studentId != null) sessionDead(studentId) else W4Error.InvalidCredentials

    private fun sessionDead(studentId: String?): W4Error {
        if (studentId != null) {
            sessionEvents.emitSessionExpired()
        }
        return W4Error.SessionExpired
    }

    private fun mergeCookiesFromResponse(
        response: Response,
        current: W4Credentials,
        studentId: String?,
    ): W4Credentials {
        val setCookies = response.headers("Set-Cookie")
        if (setCookies.isEmpty()) return current
        val host = response.request.url.host
        val updated = W4CookieJar.mergeSetCookies(current, setCookies, host) ?: return current
        if (studentId != null) {
            try {
                credentialStore.updateCredentials(updated, studentId)
            } catch (e: Exception) {
                Timber.e(e, "Failed to persist rotated PHPSESSID")
            }
        }
        if (BuildConfig.DEBUG) {
            Timber.d("PHPSESSID rotated: %s", CookieHeaderBuilder.redactedPreview(updated))
        }
        return updated
    }

    private fun resolveRedirect(base: HttpUrl, location: String): HttpUrl? {
        location.toHttpUrlOrNull()?.let { return it }
        return base.resolve(location)
    }

    private fun isTransient(cause: Throwable?): Boolean = when (cause) {
        is SocketTimeoutException -> true
        is UnknownHostException -> true
        is IOException -> {
            val msg = cause.message.orEmpty()
            msg.contains("timeout", ignoreCase = true) ||
                msg.contains("connection", ignoreCase = true)
        }
        else -> false
    }

    private fun mapIoException(e: IOException): W4Error = when (e) {
        is UnknownHostException -> W4Error.Offline
        else -> W4Error.Network(e)
    }

    companion object {
        private val FORM_URLENCODED = "application/x-www-form-urlencoded; charset=UTF-8".toMediaType()
    }
}
