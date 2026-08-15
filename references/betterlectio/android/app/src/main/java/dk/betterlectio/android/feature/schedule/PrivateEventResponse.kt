package dk.betterlectio.android.feature.schedule

/**
 * Detects Lectio private-event create/update acceptance from HTML.
 * iOS parity: LectioHTTPClient+PrivateEvents — still-on-form + validation error ⇒ reject.
 */
object PrivateEventResponse {

    /**
     * Returns true when Lectio accepted the save (redirected away or form without field errors).
     * Returns false when the form is re-rendered with validation errors.
     */
    fun isAccepted(responseHtml: String): Boolean {
        if (responseHtml.isBlank()) return false
        val stillOnForm = responseHtml.contains("m_Content_titelTextBox") ||
            responseHtml.contains("titelTextBox") ||
            responseHtml.contains("m\$Content\$titelTextBox")
        val hasFieldError = responseHtml.contains("field-validation-error", ignoreCase = true) ||
            responseHtml.contains("class=\"error\"") ||
            responseHtml.contains("class='error'") ||
            Regex("""class\s*=\s*["'][^"']*\berror\b[^"']*["']""", RegexOption.IGNORE_CASE)
                .containsMatchIn(responseHtml)
        if (stillOnForm && hasFieldError) return false
        return true
    }

    /**
     * Build field overrides for create/update postbacks (shared mapping).
     */
    fun fieldOverrides(
        title: String,
        startDate: String,
        startTime: String,
        endDate: String,
        endTime: String,
        note: String,
        titleField: String = "m\$Content\$titelTextBox\$tb",
        noteField: String = "m\$Content\$commentTextBox\$tb",
        startDateField: String = "m\$Content\$startdateCtrl\$_date\$tb",
        startTimeField: String = "m\$Content\$startdateCtrl\$startdateCtrl_time\$tb",
        endDateField: String = "m\$Content\$enddateCtrl\$_date\$tb",
        endTimeField: String = "m\$Content\$enddateCtrl\$enddateCtrl_time\$tb",
    ): Map<String, String> = mapOf(
        titleField to title,
        startDateField to startDate,
        startTimeField to startTime,
        endDateField to endDate,
        endTimeField to endTime,
        noteField to note,
    )
}
