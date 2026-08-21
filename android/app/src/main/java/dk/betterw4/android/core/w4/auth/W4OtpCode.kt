package dk.betterw4.android.core.w4.auth

internal object W4OtpCode {
    private const val LENGTH = 8

    fun sanitizeInput(value: String): String =
        value.filter { !it.isWhitespace() }.take(LENGTH)
}
