package dk.betterw4.android.feature.trips

import org.jsoup.Jsoup

data class W4Trip(
    val name: String,
    val outgoing: String,
    val returning: String,
    val destination: String,
    val type: String,
    val participants: String,
    val status: String,
)

object W4TripsParser {
    fun parse(html: String): List<W4Trip> {
        val table = Jsoup.parse(html).selectFirst("#content_inner table") ?: return emptyList()
        return table.select("tbody tr").mapNotNull { row ->
            if (row.selectFirst("td.empty") != null) return@mapNotNull null
            val cells = row.select("td").map { it.text().trim() }
            if (cells.size < 4 || cells[0].isBlank()) return@mapNotNull null
            W4Trip(
                name = cells.getOrElse(0) { "" },
                outgoing = cells.getOrElse(1) { "" },
                returning = cells.getOrElse(2) { "" },
                destination = cells.getOrElse(3) { "" },
                type = cells.getOrElse(4) { "" },
                participants = cells.getOrElse(5) { "" },
                status = cells.getOrElse(6) { "" },
            )
        }
    }
}
