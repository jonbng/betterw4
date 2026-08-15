package dk.betterw4.android.feature.campus

import org.jsoup.Jsoup

data class CampusStatus(
    val onCampus: Boolean,
    val location: String? = null,
    val options: List<String> = defaultOptions,
) {
    val label: String
        get() = if (onCampus) {
            "On campus"
        } else {
            location?.takeIf { it.isNotBlank() } ?: "Off campus"
        }

    companion object {
        val defaultOptions = listOf(
            "On campus",
            "On a walk",
            "At Raudbua",
            "On Jarstadheia",
            "On the island",
            "In Flekke",
            "In Dale",
            "In A building (after 10:30pm)",
            "In K building (after 10:30pm)",
            "In Library/Study room (after 10:30pm)",
            "Other",
        )
    }
}

object CampusStatusParser {
    fun parse(html: String): CampusStatus {
        val doc = Jsoup.parse(html)
        val statusEl = doc.selectFirst(".status-dropdown .status")
        val onCampus = statusEl?.hasClass("oncampus") == true ||
            statusEl?.selectFirst(".status-value")?.text().orEmpty()
                .contains("on campus", ignoreCase = true)
        val location = statusEl?.selectFirst(".location")?.text()?.trim()?.ifBlank { null }
        val options = doc.select("#location input[type=radio]").mapNotNull { input ->
            val id = input.id()
            val label = if (id.isNotBlank()) {
                doc.selectFirst("label[for=$id]")?.text()?.trim()
            } else {
                null
            }
            val value = input.attr("value")
            when {
                !label.isNullOrBlank() -> label
                value.equals("oncampus", ignoreCase = true) -> "On campus"
                value.equals("other", ignoreCase = true) -> "Other"
                value.isNotBlank() -> value
                else -> null
            }
        }.filter { it.isNotBlank() }
        return CampusStatus(
            onCampus = onCampus,
            location = location,
            options = options.ifEmpty { CampusStatus.defaultOptions },
        )
    }
}
