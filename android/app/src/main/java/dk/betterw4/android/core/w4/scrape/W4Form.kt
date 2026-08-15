package dk.betterw4.android.core.w4.scrape

import dk.betterw4.android.core.w4.YiiForm
import okhttp3.FormBody
import okio.Buffer
import org.jsoup.Jsoup
import org.jsoup.nodes.Element

/**
 * Login / OTP extras on top of [YiiForm]. Feature posts should use [YiiForm] directly.
 */
object W4Form {
    data class Parsed(
        val action: String?,
        val fields: Map<String, String>,
        val submitName: String?,
        val submitValue: String?,
        val otpFieldName: String?,
    )

    fun encode(fields: Map<String, String>): ByteArray {
        val builder = FormBody.Builder()
        for ((name, value) in fields) {
            builder.add(name, value)
        }
        val buffer = Buffer()
        builder.build().writeTo(buffer)
        return buffer.readByteArray()
    }

    fun parse(html: String): Parsed? {
        val doc = Jsoup.parse(html)
        val form = doc.selectFirst("form:has(input[name^=LoginForm])")
            ?: doc.selectFirst("form[action*=otp], form[action*=verify2fa], form[action*=2fa]")
            ?: doc.selectFirst("#content_inner form, #content form")
            ?: doc.selectFirst("form")
            ?: return null

        val yii = YiiForm.parseForm(form)
        val submit = yii.submitButtons.entries.firstOrNull()
        return Parsed(
            action = yii.action,
            fields = yii.fields,
            submitName = submit?.key,
            submitValue = submit?.value?.ifBlank { "Login" },
            otpFieldName = findOtpFieldName(form),
        )
    }

    fun loginError(html: String): String? {
        val doc = Jsoup.parse(html)
        val summary = doc.selectFirst(".errorSummary li, .errorSummary")
            ?.text()
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
        if (summary != null) return summary
        val flash = doc.selectFirst(".flash-error, .alert-error, .errorMessage, div.error")
            ?.text()
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
        return flash
    }

    fun inputInventory(html: String): String =
        Jsoup.parse(html).select("input[name]").joinToString { input ->
            val type = input.attr("type").ifBlank { "text" }
            "${input.attr("name")}:$type"
        }

    private val OTP_NAME = Regex(
        """otp|totp|2fa|code|token|pin|sms|verify|verification|authenticator|onetime|one[_-]?time""",
        RegexOption.IGNORE_CASE,
    )

    private fun findOtpFieldName(form: Element): String? {
        val candidates = form.select("input[name]").filter { input ->
            val name = input.attr("name")
            if (name.startsWith("LoginForm", ignoreCase = true)) return@filter false
            val type = input.attr("type").lowercase().ifBlank { "text" }
            type !in SKIP_OTP_INPUT_TYPES
        }
        return candidates.firstOrNull { OTP_NAME.containsMatchIn(it.attr("name")) }?.attr("name")
            ?: candidates.singleOrNull()?.attr("name")
            ?: candidates.firstOrNull()?.attr("name")
    }

    private val SKIP_OTP_INPUT_TYPES = setOf(
        "hidden", "submit", "checkbox", "radio", "button", "file", "image",
    )
}
