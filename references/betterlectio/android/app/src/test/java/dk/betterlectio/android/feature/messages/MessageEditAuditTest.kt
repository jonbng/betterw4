package dk.betterlectio.android.feature.messages

import java.time.Instant
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

class MessageEditAuditTest {
    @Test
    fun extractsTerminalAuditAsCopenhagenTime() {
        val result = MessageEditAudit.extract(
            "<p>Hej <strong>verden</strong></p>" +
                "<div>Redigeret af Jonathan Arthur Hojer Bangert(k) (2x 17), d. 3/8-2026 09:54</div>",
        )

        assertEquals("<p>Hej <strong>verden</strong></p>", result.html)
        assertEquals(Instant.parse("2026-08-03T07:54:00Z"), result.editedAt)
    }

    @Test
    fun keepsMalformedAndNonTerminalAuditText() {
        val invalid = "<p>Hej</p><div>Redigeret af Elev, d. 31/2-2026 09:54</div>"
        assertEquals(invalid, MessageEditAudit.extract(invalid).html)
        assertNull(MessageEditAudit.extract(invalid).editedAt)

        val followed = "<p>Hej</p><div>Redigeret af Elev, d. 3/8-2026 09:54</div><p>Eftertekst</p>"
        assertEquals(followed, MessageEditAudit.extract(followed).html)
        assertNull(MessageEditAudit.extract(followed).editedAt)
    }

    @Test
    fun formatsRelativeTimeThroughSixDaysThenUsesAbsoluteTime() {
        val editedAt = Instant.parse("2026-08-03T07:54:00Z")
        assertEquals(
            MessageEditedTimeValue.JustNow,
            MessageEditedTimeFormatter.value(editedAt, editedAt.plusSeconds(30), Locale.US),
        )
        assertEquals(
            MessageEditedTimeValue.Minutes(5),
            MessageEditedTimeFormatter.value(editedAt, editedAt.plusSeconds(330), Locale.US),
        )
        val absolute = MessageEditedTimeFormatter.value(
            editedAt,
            editedAt.plusSeconds(7 * 86_400L),
            Locale.US,
        ) as MessageEditedTimeValue.Absolute
        assertFalse(absolute.value.contains("ago"))
    }
}
