package dk.betterw4.android.core.w4.auth

import dk.betterw4.android.core.w4.W4Html
import dk.betterw4.android.core.w4.W4Session
import dk.betterw4.android.core.w4.W4Urls
import dk.betterw4.android.core.w4.YiiForm
import dk.betterw4.android.core.w4.http.W4HttpEngine
import dk.betterw4.android.core.w4.model.FetchPriority
import dk.betterw4.android.core.w4.model.W4Credentials
import dk.betterw4.android.core.w4.model.W4Request
import dk.betterw4.android.core.w4.scrape.W4Form
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

data class W4OtpChallenge(
    val credentials: W4Credentials,
    val formAction: HttpUrl,
    val hiddenFields: Map<String, String>,
    val otpFieldName: String,
    val submitName: String?,
    val submitValue: String?,
)

sealed class W4LoginStep {
    data class Authenticated(
        val credentials: W4Credentials,
        val html: String,
        val finalUrl: String,
    ) : W4LoginStep()

    data class NeedsOtp(val challenge: W4OtpChallenge) : W4LoginStep()

    data class Failed(val invalidOtp: Boolean = false) : W4LoginStep()
}

/**
 * Native W4 username/password (+ OTP) login. No WebView.
 *
 * Uses [W4HttpEngine] with [W4Request.allowLoginPage] so a 302 to
 * `site/verify2fa` / `site/otp` or a 200 login form is not treated as session expiry.
 */
@Singleton
class W4LoginClient @Inject constructor(
    private val engine: W4HttpEngine,
    private val deviceIdStore: W4DeviceIdStore,
) {
    suspend fun submitPassword(username: String, password: String): W4LoginStep {
        val loginUrl = W4Urls.route(W4Urls.Routes.LOGIN)
        val empty = W4Credentials(sessionId = "")
        val opened = engine.execute(
            W4Request(
                url = loginUrl,
                method = "GET",
                priority = FetchPriority.Important,
                allowLoginPage = true,
            ),
            empty,
        )
        val parsed = W4Form.parse(opened.response.body)
        val fields = YiiForm.fieldsForSubmit(
            html = opened.response.body,
            extra = mapOf(
                "LoginForm[username]" to username.trim(),
                "LoginForm[password]" to password,
                "LoginForm[deviceId]" to deviceIdStore.getOrCreate(),
            ),
            submitName = parsed?.submitName ?: "yt0",
            submitValue = parsed?.submitValue ?: "Login",
            formSelector = "form:has(input[name^=LoginForm])",
        )
        val posted = engine.execute(
            W4Request(
                url = loginUrl,
                method = "POST",
                body = W4Form.encode(fields),
                headers = mapOf(
                    "Content-Type" to "application/x-www-form-urlencoded; charset=UTF-8",
                    "Referer" to loginUrl.toString(),
                ),
                priority = FetchPriority.Important,
                allowLoginPage = true,
            ),
            opened.credentials,
        )
        return classify(posted.credentials, posted.response.body, posted.response.finalUrl.toString())
    }

    suspend fun submitOtp(challenge: W4OtpChallenge, code: String): W4LoginStep {
        val fields = challenge.hiddenFields.toMutableMap()
        fields[challenge.otpFieldName] = code.trim()
        val submitName = challenge.submitName ?: "yt0"
        val submitValue = challenge.submitValue ?: "Verify"
        fields.putIfAbsent(submitName, submitValue)

        val posted = engine.execute(
            W4Request(
                url = challenge.formAction,
                method = "POST",
                body = W4Form.encode(fields),
                headers = mapOf(
                    "Content-Type" to "application/x-www-form-urlencoded; charset=UTF-8",
                    "Referer" to challenge.formAction.toString(),
                ),
                priority = FetchPriority.Important,
                allowLoginPage = true,
            ),
            challenge.credentials,
        )
        return classify(
            posted.credentials,
            posted.response.body,
            posted.response.finalUrl.toString(),
            expectingOtp = true,
        )
    }

    private fun classify(
        credentials: W4Credentials,
        html: String,
        finalUrl: String,
        expectingOtp: Boolean = false,
    ): W4LoginStep {
        Timber.i(
            "W4 login classify url=%s otpUrl=%s authHtml=%s loginHtml=%s inputs=%s",
            finalUrl,
            W4Session.isOtpUrl(finalUrl),
            W4Html.isAuthenticatedHtml(html),
            W4Html.isLoginHtml(html),
            W4Form.inputInventory(html),
        )
        if (credentials.sessionId.isEmpty()) {
            Timber.w("W4 login: no PHPSESSID after response")
            return W4LoginStep.Failed(invalidOtp = expectingOtp)
        }
        // 2FA pages still ship logged-in chrome (Welcome / #user-panel). Check OTP first.
        if (W4Session.isOtpUrl(finalUrl) || looksLikeOtp(html, finalUrl)) {
            val form = W4Form.parse(html)
            val otpField = form?.otpFieldName
            if (form == null || otpField.isNullOrBlank()) {
                Timber.w(
                    "W4 OTP page but no code field parsed url=%s inputs=%s",
                    finalUrl,
                    W4Form.inputInventory(html),
                )
                return W4LoginStep.Failed(invalidOtp = expectingOtp)
            }
            val action = resolveAction(form.action, finalUrl)
                ?: W4Urls.route(W4Urls.Routes.VERIFY_2FA)
            val hidden = form.fields.toMutableMap().apply { remove(otpField) }
            Timber.i("W4 login: OTP required route=%s field=%s", W4Urls.routeOf(finalUrl), otpField)
            return W4LoginStep.NeedsOtp(
                W4OtpChallenge(
                    credentials = credentials,
                    formAction = action,
                    hiddenFields = hidden,
                    otpFieldName = otpField,
                    submitName = form.submitName,
                    submitValue = form.submitValue,
                ),
            )
        }
        if (W4Html.isLoginHtml(html) || W4Session.isLoginUrl(finalUrl)) {
            W4Form.loginError(html)?.let { Timber.w("W4 login rejected: %s", it) }
            return W4LoginStep.Failed(invalidOtp = expectingOtp)
        }
        if (W4Html.isAuthenticatedHtml(html) || W4Session.isHomeUrl(finalUrl)) {
            return W4LoginStep.Authenticated(credentials, html, finalUrl)
        }
        Timber.w("W4 login: unexpected page url=%s", finalUrl)
        return W4LoginStep.Failed(invalidOtp = expectingOtp)
    }

    private fun looksLikeOtp(html: String, finalUrl: String): Boolean {
        if (W4Session.isOtpUrl(finalUrl)) return true
        if (W4Html.isLoginHtml(html)) return false
        val form = W4Form.parse(html) ?: return false
        return !form.otpFieldName.isNullOrBlank()
    }

    private fun resolveAction(action: String?, fallbackUrl: String): HttpUrl? {
        if (action.isNullOrBlank()) return fallbackUrl.toHttpUrlOrNull()
        action.toHttpUrlOrNull()?.let { return it }
        return W4Urls.origin().resolve(action) ?: fallbackUrl.toHttpUrlOrNull()
    }
}
