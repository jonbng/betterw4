package dk.betterlectio.android.ui.auth

import dk.betterlectio.android.core.lectio.auth.MitIdAuthUrls
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MitIdAuthUrlsTest {

    @Test
    fun authSuccess_forside() {
        assertTrue(
            MitIdAuthUrls.isAuthSuccessUrl(
                "https://www.lectio.dk/lectio/504/forside.aspx",
            ),
        )
    }

    @Test
    fun authSuccess_uniloginCallback_withoutBroker() {
        assertTrue(
            MitIdAuthUrls.isAuthSuccessUrl(
                "https://www.lectio.dk/lectio/integration/unilogin.aspx?foo=1",
            ),
        )
    }

    @Test
    fun authSuccess_rejectsBrokerUnilogin() {
        assertFalse(
            MitIdAuthUrls.isAuthSuccessUrl(
                "https://broker.unilogin.dk/auth/realms/broker/protocol/...",
            ),
        )
        assertFalse(
            MitIdAuthUrls.isAuthSuccessUrl(
                "https://www.lectio.dk/lectio/integration/unilogin.aspx?return=broker.unilogin.dk",
            ),
        )
    }

    @Test
    fun authSuccess_rejectsUnrelatedLectio() {
        assertFalse(
            MitIdAuthUrls.isAuthSuccessUrl(
                "https://www.lectio.dk/lectio/504/login.aspx",
            ),
        )
    }

    @Test
    fun appSwitch_appswitchHost() {
        assertTrue(
            MitIdAuthUrls.isMitIdAppSwitchUrl(
                "https://appswitch.mitid.dk/launch?ticket=abc",
            ),
        )
        assertTrue(
            MitIdAuthUrls.isMitIdAppSwitchUrl(
                "http://appswitch.mitid.dk/x",
            ),
        )
        assertTrue(
            MitIdAuthUrls.isMitIdAppSwitchUrl(
                "https://appswitch.mitid.dk?ticket=abc&returnUrl=Chrome",
            ),
        )
        assertFalse(
            MitIdAuthUrls.isMitIdAppSwitchUrl(
                "https://appswitch.mitid.dk.evil.example/x",
            ),
        )
    }

    @Test
    fun appSwitch_customSchemes() {
        assertTrue(MitIdAuthUrls.isMitIdAppSwitchUrl("mitid://auth/continue"))
        assertTrue(MitIdAuthUrls.isMitIdAppSwitchUrl("mitiddk://callback"))
    }

    @Test
    fun appSwitch_intentUriWithMitid() {
        assertTrue(
            MitIdAuthUrls.isMitIdAppSwitchUrl(
                "intent://appswitch.mitid.dk/#Intent;scheme=https;package=dk.mitid.app.android;end",
            ),
        )
    }

    @Test
    fun appSwitch_rejectsNormalHttps() {
        assertFalse(
            MitIdAuthUrls.isMitIdAppSwitchUrl(
                "https://www.mitid.dk/login",
            ),
        )
        assertFalse(
            MitIdAuthUrls.isMitIdAppSwitchUrl(
                "https://www.lectio.dk/lectio/504/login.aspx",
            ),
        )
    }

    @Test
    fun externalApp_includesCustomSchemes() {
        assertTrue(MitIdAuthUrls.isExternalAppUrl("https://appswitch.mitid.dk/x"))
        assertTrue(MitIdAuthUrls.isExternalAppUrl("mitid://x"))
        assertTrue(MitIdAuthUrls.isExternalAppUrl("bankid://x"))
        assertFalse(MitIdAuthUrls.isExternalAppUrl("https://www.lectio.dk/x"))
        assertFalse(MitIdAuthUrls.isExternalAppUrl("about:blank"))
    }

    @Test
    fun uniloginIntegration_isStrictPath() {
        assertTrue(
            MitIdAuthUrls.isUniloginIntegrationCallback(
                "https://www.lectio.dk/lectio/integration/unilogin.aspx?x=1",
            ),
        )
        assertFalse(
            MitIdAuthUrls.isUniloginIntegrationCallback(
                "https://www.lectio.dk/lectio/504/login.aspx",
            ),
        )
    }

    @Test
    fun personIdFromUrl() {
        assertEquals(
            "12345",
            MitIdAuthUrls.personIdFromUrl("https://www.lectio.dk/lectio/1/forside.aspx?elevid=12345"),
        )
        assertEquals(
            "99",
            MitIdAuthUrls.personIdFromUrl("https://www.lectio.dk/x?laererid=99&foo=1"),
        )
        assertNull(MitIdAuthUrls.personIdFromUrl("https://www.lectio.dk/lectio/1/forside.aspx"))
    }
}
