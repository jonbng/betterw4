package dk.betterlectio.android.core.lectio.http

import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UniLoginDetectorTest {
    @Test
    fun detects_broker_host() {
        assertTrue(
            UniLoginDetector.isUniLoginBroker(
                "https://broker.unilogin.dk/auth/realms/broker".toHttpUrl(),
            ),
        )
    }

    @Test
    fun ignores_lectio() {
        assertFalse(
            UniLoginDetector.isUniLoginBroker(
                "https://www.lectio.dk/lectio/94/forside.aspx".toHttpUrl(),
            ),
        )
    }
}
