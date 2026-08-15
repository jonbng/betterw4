package dk.betterlectio.android.feature.studiekort

import dk.betterlectio.android.core.model.Student
import org.junit.Assert.assertTrue
import org.junit.Test

class StudiekortRepositoryTest {

    @Test
    fun demo_qr_url_is_https_and_encodes_student() {
        val url = StudiekortRepository.demoQrUrl(Student.Demo)
        assertTrue(url.startsWith("https://"))
        assertTrue(url.contains("create-qr-code") || url.contains("qr"))
        assertTrue(url.contains("betterlectio") || url.contains("demo"))
    }

    @Test
    fun demo_photo_url_constant_is_https() {
        assertTrue(StudiekortRepository.DEMO_PHOTO_URL.startsWith("https://"))
    }
}
