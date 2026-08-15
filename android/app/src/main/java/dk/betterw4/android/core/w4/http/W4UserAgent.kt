package dk.betterw4.android.core.w4.http

import dk.betterw4.android.core.w4.W4Hosts

/**
 * Stable desktop Chrome UA. Do not rotate — W4 is a small Apache box.
 * Native login sends a persisted install UUID as `LoginForm[deviceId]` instead of ClientJS.
 */
object W4UserAgent {
    const val VALUE =
        "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) " +
            "Chrome/131.0.0.0 Safari/537.36"

    const val REFERER = W4Hosts.ORIGIN

    const val AJAX = "XMLHttpRequest"
}
