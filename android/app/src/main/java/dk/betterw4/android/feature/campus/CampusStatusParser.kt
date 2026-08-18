package dk.betterw4.android.feature.campus

import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import org.jsoup.nodes.Element

data class CampusLocationOption(
    val id: String,
    val value: String,
    val label: String,
) {
    val isOnCampus: Boolean
        get() = value.equals(ON_CAMPUS_VALUE, ignoreCase = true)
    val isFreeText: Boolean
        get() = value.equals(FREE_TEXT_VALUE, ignoreCase = true)

    companion object {
        const val ON_CAMPUS_VALUE = "oncampus"
        const val FREE_TEXT_VALUE = "other"
        const val FREE_TEXT_MAX_LENGTH = 20

        val defaults: List<CampusLocationOption> = listOf(
            CampusLocationOption("location_0", ON_CAMPUS_VALUE, "On campus"),
            CampusLocationOption("location_1", "On a walk", "On a walk"),
            CampusLocationOption("location_2", "At Raudbua", "At Raudbua"),
            CampusLocationOption("location_3", "On Jarstadheia", "On Jarstadheia"),
            CampusLocationOption("location_4", "On the island", "On the island"),
            CampusLocationOption("location_5", "In Flekke", "In Flekke"),
            CampusLocationOption("location_6", "In Dale", "In Dale"),
            CampusLocationOption("location_7", "In A building (after 10:30pm)", "In A building (after 10:30pm)"),
            CampusLocationOption("location_8", "In K building (after 10:30pm)", "In K building (after 10:30pm)"),
            CampusLocationOption(
                "location_9",
                "In Library/Study room (after 10:30pm)",
                "In Library/Study room (after 10:30pm)",
            ),
            CampusLocationOption("location_10", FREE_TEXT_VALUE, "Other"),
        )
    }
}

data class CampusStatus(
    val onCampus: Boolean,
    val location: String? = null,
    val options: List<CampusLocationOption> = CampusLocationOption.defaults,
    val selectedOptionId: String? = null,
) {
    val label: String
        get() = if (onCampus) {
            "On campus"
        } else {
            location?.takeIf { it.isNotBlank() } ?: "Off campus"
        }

    companion object {
        val defaultOptions: List<CampusLocationOption>
            get() = CampusLocationOption.defaults
    }
}

/**
 * Campus chrome parser. Matches iOS `W4CampusStatusParser`.
 *
 * B6: radios keep `value` and `label` apart — posting the label breaks
 * "On campus" (`status=on`, no location) and "Other" (free text).
 * B7: `div.location` may wrap as `(At Raudbua)` after a client-side write.
 */
object CampusStatusParser {
    fun parse(html: String): CampusStatus? {
        if (html.isBlank()) return null
        val doc = Jsoup.parse(html)
        return parse(doc)
    }

    private fun parse(document: Document): CampusStatus? {
        val statusEl = document.selectFirst(".status-dropdown .status")
        val dropdown = document.selectFirst(".status-dropdown")
        val (parsedOptions, checkedId) = parseOptions(document)
        if (dropdown == null && statusEl == null && parsedOptions.isEmpty()) return null

        val options = parsedOptions.ifEmpty { CampusLocationOption.defaults }
        val onCampus = resolveIsOnCampus(statusEl, options, checkedId)
        var location = statusEl?.selectFirst(".location")?.text()?.let { normalizedLocation(it) }
        if (onCampus) location = null
        return CampusStatus(
            onCampus = onCampus,
            location = location,
            options = options,
            selectedOptionId = if (parsedOptions.isEmpty()) null else checkedId,
        )
    }

    fun setStatusBody(option: CampusLocationOption, freeText: String? = null): Map<String, String>? {
        if (option.isOnCampus) return mapOf("status" to "on")
        val location = if (option.isFreeText) {
            val trimmed = freeText?.trim().orEmpty()
            if (trimmed.isEmpty()) return null
            trimmed.take(CampusLocationOption.FREE_TEXT_MAX_LENGTH)
        } else {
            option.value.trim()
        }
        if (location.isEmpty()) return null
        return mapOf("status" to "off", "location" to location)
    }

    fun setStatusBody(onCampus: Boolean, location: String?): Map<String, String> {
        if (onCampus) return mapOf("status" to "on")
        val trimmed = location?.trim().orEmpty()
        return if (trimmed.isEmpty()) mapOf("status" to "off") else mapOf("status" to "off", "location" to trimmed)
    }

    fun normalizedLocation(raw: String?): String? {
        val trimmed = raw?.trim().orEmpty()
        if (trimmed.isEmpty()) return null
        val unwrapped = stripWrappingParentheses(trimmed).trim()
        return unwrapped.ifEmpty { null }
    }

    private fun parseOptions(document: Document): Pair<List<CampusLocationOption>, String?> {
        var radios = document.select("#location input[type=radio]")
        if (radios.isEmpty()) radios = document.select("input[type=radio][name=location]")
        if (radios.isEmpty()) return emptyList<CampusLocationOption>() to null
        val labels = labelTexts(document)
        val options = mutableListOf<CampusLocationOption>()
        var checkedId: String? = null
        radios.forEachIndexed { index, radio ->
            val value = radio.attr("value").trim()
            if (value.isEmpty()) return@forEachIndexed
            val domId = radio.id().trim()
            val id = if (domId.isEmpty()) "location_$index" else domId
            val label = labels[domId]?.takeIf { it.isNotEmpty() } ?: fallbackLabel(value)
            options += CampusLocationOption(id = id, value = value, label = label)
            if (checkedId == null && radio.hasAttr("checked")) checkedId = id
        }
        return options to checkedId
    }

    private fun labelTexts(document: Document): Map<String, String> {
        val map = linkedMapOf<String, String>()
        for (label in document.select("label[for]")) {
            val key = label.attr("for")
            if (key.isEmpty() || map.containsKey(key)) continue
            map[key] = label.text().trim()
        }
        return map
    }

    private fun fallbackLabel(value: String): String = when {
        value.equals(CampusLocationOption.ON_CAMPUS_VALUE, ignoreCase = true) -> "On campus"
        value.equals(CampusLocationOption.FREE_TEXT_VALUE, ignoreCase = true) -> "Other"
        else -> value
    }

    private fun resolveIsOnCampus(
        statusElement: Element?,
        options: List<CampusLocationOption>,
        checkedId: String?,
    ): Boolean {
        if (statusElement != null) {
            if (statusElement.hasClass("oncampus")) return true
            if (statusElement.hasClass("offcampus")) return false
            val value = statusElement.selectFirst(".status-value")?.text()?.trim()?.lowercase().orEmpty()
            if (value.contains("off campus") || value.contains("offcampus")) return false
            if (value.contains("on campus") || value.contains("oncampus")) return true
        }
        options.firstOrNull { it.id == checkedId }?.let { return it.isOnCampus }
        return true
    }

    private fun stripWrappingParentheses(value: String): String {
        if (value.length < 2 || !value.startsWith("(") || !value.endsWith(")")) return value
        val inner = value.substring(1, value.length - 1)
        var depth = 0
        for (ch in inner) {
            when (ch) {
                '(' -> depth++
                ')' -> {
                    depth--
                    if (depth < 0) return value
                }
            }
        }
        return if (depth == 0) inner else value
    }
}
