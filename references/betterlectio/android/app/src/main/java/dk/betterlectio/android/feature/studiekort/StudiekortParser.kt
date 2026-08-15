package dk.betterlectio.android.feature.studiekort

import dk.betterlectio.android.feature.directory.AvatarUrls
import org.jsoup.Jsoup

/**
 * Parses Lectio studiekort HTML.
 * Primary: Flutter digitaltStudiekort.aspx field ids.
 * Fallback: elevforside / generic GetImage scraping.
 */
object StudiekortParser {
    data class ParsedCard(
        val name: String?,
        val classLabel: String?,
        val schoolName: String?,
        val photoUrl: String?,
        val qrUrl: String?,
        val pictureId: String?,
        val birthday: String? = null,
    )

    fun parse(html: String, gymId: Int, studentId: String): ParsedCard {
        val doc = Jsoup.parse(html)

        // Flutter digitaltStudiekort fields
        val digitalName = doc.getElementById("s_m_Content_Content_StudentName")?.text()?.trim()
        val digitalSchool = doc.getElementById("s_m_Content_Content_SchoolName")?.text()?.trim()
        val digitalPic = doc.getElementById("s_m_Content_Content_StudPic")
        val digitalBirthday = parseBirthdayFromElement(
            doc.getElementById("s_m_Content_Content_StudentBirthday"),
        )

        val name = digitalName
            ?: doc.selectFirst("#s_m_HeaderContent_MainTitle, .ls-person-name, h1")
                ?.text()?.trim()?.takeIf { it.isNotBlank() }
        val classLabel = extractClass(name.orEmpty())
            ?: doc.selectFirst(".ls-person-text")?.text()?.let { extractClass(it) }
        val schoolName = digitalSchool
            ?: doc.selectFirst(".ls-master-header-institutionname, .ls-subtext")
                ?.text()?.trim()?.takeIf { it.isNotBlank() }
        val birthday = digitalBirthday ?: parseBirthday(html)

        var photoUrl: String? = null
        var pictureId: String? = null
        if (digitalPic != null) {
            val src = digitalPic.attr("src")
            if (src.isNotBlank()) {
                photoUrl = absolutize(src, gymId)
                pictureId = Regex("""pictureid=(\d+)""", RegexOption.IGNORE_CASE)
                    .find(src)?.groupValues?.get(1)
            }
        }
        if (photoUrl == null) {
            doc.select("img[src*=GetImage], img[src*=pictureid]").forEach { img ->
                val src = img.attr("src")
                if (src.contains("studiekortqr", ignoreCase = true)) return@forEach
                if (src.contains("GetImage") || src.contains("pictureid")) {
                    photoUrl = absolutize(src, gymId)
                    pictureId = Regex("""pictureid=(\d+)""", RegexOption.IGNORE_CASE)
                        .find(src)?.groupValues?.get(1)
                }
            }
        }

        var qrUrl: String? = null
        doc.select("img[src*=studiekortqr], img[src*=qr], a[href*=studiekortqr] img").forEach { img ->
            val src = img.attr("src").ifBlank { img.parent()?.attr("href").orEmpty() }
            if (src.isNotBlank()) qrUrl = absolutize(src, gymId)
        }
        doc.select("a[href*=studiekortqr], img[src*=type=studiekortqr]").forEach { el ->
            val src = el.attr("src").ifBlank { el.attr("href") }
            if (src.isNotBlank()) qrUrl = absolutize(src, gymId)
        }

        // Flutter constructs QR with time=
        if (qrUrl == null && studentId.isNotBlank()) {
            val t = System.currentTimeMillis()
            qrUrl =
                "https://www.lectio.dk/lectio/$gymId/GetImage.aspx?studentid=$studentId&type=studiekortqr&time=$t"
        }
        // Lectio studiekort/elevforside often embeds a thumbnail GetImage URL without
        // fullsize=1 — always prefer the high-res variant when we have a picture id.
        if (pictureId != null) {
            photoUrl = AvatarUrls.fromPictureId(gymId, pictureId)
        }

        return ParsedCard(name, classLabel, schoolName, photoUrl, qrUrl, pictureId, birthday)
    }

    /**
     * iOS + Flutter: span#s_m_Content_Content_StudentBirthday
     * Flutter also strips to date before `(` when present.
     */
    fun parseBirthday(html: String): String? {
        val doc = Jsoup.parse(html)
        val span = doc.selectFirst(
            "#s_m_Content_Content_StudentBirthday, " +
                "span#s_m_Content_Content_StudentBirthday, " +
                "[id*=StudentBirthday], [id*=studentBirthday]",
        ) ?: return null
        return parseBirthdayFromElement(span)
    }

    private fun parseBirthdayFromElement(span: org.jsoup.nodes.Element?): String? {
        if (span == null) return null
        var text = span.text()
            .replace("Fødselsdag:", "", ignoreCase = true)
            .replace("Fødselsdag", "", ignoreCase = true)
            .trim()
        // Flutter: take part before `(` if present (age parenthesis)
        if ('(' in text) {
            text = text.substringBefore('(').trim()
        }
        return text.takeIf { it.isNotBlank() }
    }

    private fun extractClass(title: String): String? {
        // e.g. "Demo Elev - 3.x"
        val parts = title.split(" - ", "–").map { it.trim() }
        return parts.getOrNull(1)?.takeIf { it.isNotBlank() }
    }

    private fun absolutize(src: String, gymId: Int): String {
        if (src.startsWith("http")) return src
        if (src.startsWith("//")) return "https:$src"
        if (src.startsWith("/")) return "https://www.lectio.dk$src"
        return "https://www.lectio.dk/lectio/$gymId/$src"
    }
}
