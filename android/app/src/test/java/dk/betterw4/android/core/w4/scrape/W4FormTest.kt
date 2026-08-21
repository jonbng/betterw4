package dk.betterw4.android.core.w4.scrape

import org.junit.Assert.assertEquals
import org.junit.Test

class W4RepeatedFieldEncodingTest {
    @Test
    fun repeated_fields_keep_the_same_encoded_name() {
        val encoded = W4Form.encode(
            listOf(
                "StudentAbsenceForm[absences][]" to "CLASS_A_08:15",
                "StudentAbsenceForm[absences][]" to "CLASS_B_10:10",
            ),
        ).decodeToString()

        assertEquals(
            "StudentAbsenceForm%5Babsences%5D%5B%5D=CLASS_A_08%3A15&" +
                "StudentAbsenceForm%5Babsences%5D%5B%5D=CLASS_B_10%3A10",
            encoded,
        )
    }
}
