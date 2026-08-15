package dk.betterw4.android.core.w4

import org.jsoup.Jsoup
import org.jsoup.nodes.Element

/**
 * Yii 1 form helper. Posts are cookie-auth only (no CSRF token).
 * Submit buttons are `yt0`, `yt1`, … — include the clicked name when POSTing.
 */
object YiiForm {

    data class Parsed(
        val action: String?,
        val fields: Map<String, String>,
        val submitButtons: Map<String, String>,
    )

    fun parse(html: String, formSelector: String? = null): Parsed {
        val doc = Jsoup.parse(html)
        val form = when {
            !formSelector.isNullOrBlank() -> doc.selectFirst(formSelector)
            else -> doc.selectFirst("form")
        } ?: return Parsed(action = null, fields = emptyMap(), submitButtons = emptyMap())
        return parseForm(form)
    }

    fun parseForm(form: Element): Parsed {
        val fields = linkedMapOf<String, String>()
        val submits = linkedMapOf<String, String>()

        for (el in form.select("input, select, textarea")) {
            val name = el.attr("name").takeIf { it.isNotBlank() } ?: continue
            val tag = el.tagName().lowercase()
            when (tag) {
                "textarea" -> fields[name] = el.text()
                "select" -> {
                    val selected = el.select("option[selected]").last()
                        ?: el.selectFirst("option")
                    fields[name] = selected?.attr("value") ?: selected?.text().orEmpty()
                }
                else -> {
                    val type = el.attr("type").lowercase().ifBlank { "text" }
                    when (type) {
                        "checkbox", "radio" -> {
                            if (el.hasAttr("checked")) {
                                fields[name] = el.attr("value").ifEmpty { "on" }
                            }
                        }
                        "submit", "button", "image" -> {
                            submits[name] = el.attr("value")
                        }
                        "file" -> Unit
                        else -> fields[name] = el.attr("value")
                    }
                }
            }
        }

        val action = form.attr("action").takeIf { it.isNotBlank() }
        return Parsed(action = action, fields = fields, submitButtons = submits)
    }

    /**
     * Merge [extra] over parsed fields and attach the Yii submit button.
     * [submitName] defaults to `yt0`; value comes from the form, then [submitValue], then `"Login"`.
     */
    fun fieldsForSubmit(
        html: String,
        extra: Map<String, String> = emptyMap(),
        submitName: String = "yt0",
        submitValue: String? = null,
        formSelector: String? = null,
    ): Map<String, String> {
        val parsed = parse(html, formSelector)
        val merged = parsed.fields.toMutableMap()
        merged.putAll(extra)
        val value = submitValue
            ?: parsed.submitButtons[submitName]
            ?: parsed.submitButtons.values.firstOrNull()
            ?: ""
        merged[submitName] = value
        return merged
    }
}
