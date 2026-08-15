package dk.betterw4.android.core.w4

import okhttp3.HttpUrl

/**
 * Session-expiry and mid-login URL classification (README §4.5, §5.4).
 *
 * Reliability order for a dead session:
 * 1. HTTP 302 to `r=site/login`
 * 2. HTTP 200 whose body is the login form
 * 3. AJAX 403 with body `Login Required`
 *
 * 403 **without** that string is forbidden (logged in, wrong role) — not expiry.
 * 409 is a server error string, not expiry.
 * 302 to `site/verify2fa` / `site/otp` or `site/index` is success-in-progress, not failure.
 */
object W4Session {

    fun isLoginUrl(url: HttpUrl): Boolean = isLoginUrl(url.toString())

    fun isLoginUrl(url: String): Boolean {
        val route = W4Urls.routeOf(url)?.lowercase() ?: return false
        return route == W4Urls.Routes.LOGIN
    }

    fun isOtpUrl(url: HttpUrl): Boolean = isOtpUrl(url.toString())

    fun isOtpUrl(url: String): Boolean {
        val route = W4Urls.routeOf(url)?.lowercase() ?: return false
        if (route == W4Urls.Routes.OTP || route == W4Urls.Routes.VERIFY_2FA) return true
        return route.startsWith("site/") &&
            (route.contains("otp") || route.contains("2fa") || route.contains("verify"))
    }

    fun isHomeUrl(url: HttpUrl): Boolean = isHomeUrl(url.toString())

    fun isHomeUrl(url: String): Boolean {
        val route = W4Urls.routeOf(url)?.lowercase() ?: return false
        return route == W4Urls.Routes.HOME || route == "site"
    }

    /** Follow this redirect; it is not a dead session. */
    fun isAuthProgressUrl(url: HttpUrl): Boolean =
        isOtpUrl(url) || isHomeUrl(url)

    fun isAuthProgressUrl(url: String): Boolean =
        isOtpUrl(url) || isHomeUrl(url)
}
