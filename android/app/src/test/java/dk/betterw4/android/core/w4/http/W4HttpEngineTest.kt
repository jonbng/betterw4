package dk.betterw4.android.core.w4.http

import dk.betterw4.android.core.w4.model.FetchPriority
import dk.betterw4.android.core.w4.model.W4Credentials
import dk.betterw4.android.core.w4.model.W4Error
import dk.betterw4.android.core.w4.model.W4Request
import dk.betterw4.android.core.w4.session.InMemoryCredentialStore
import dk.betterw4.android.core.w4.session.SessionEvents
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class W4HttpEngineTest {

    private lateinit var server: MockWebServer
    private lateinit var store: InMemoryCredentialStore
    private lateinit var events: SessionEvents
    private lateinit var engine: W4HttpEngine

    private val creds = W4Credentials(
        autologinkey = "AUTO",
        sessionId = "SESS",
    ).seededIsLoggedIn()

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        store = InMemoryCredentialStore()
        events = SessionEvents()
        val client = OkHttpClient.Builder()
            .followRedirects(false)
            .followSslRedirects(false)
            .cookieJar(okhttp3.CookieJar.NO_COOKIES)
            .build()
        engine = W4HttpEngine(
            client = client,
            credentialStore = store,
            sessionEvents = events,
            limiter = PriorityRequestLimiter(minIntervalMs = 0),
        )
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun successful_get_returns_body_and_html_accept() = runBlocking {
        server.enqueue(MockResponse().setResponseCode(200).setBody("<html>hello w4</html>"))
        val result = engine.execute(
            W4Request(url = server.url("/ok"), priority = FetchPriority.Important),
            creds,
        )
        assertEquals(200, result.response.statusCode)
        assertTrue(result.response.body.contains("hello w4"))
        val recorded = server.takeRequest()
        assertEquals("text/html", recorded.getHeader("Accept"))
        assertEquals(W4UserAgent.VALUE, recorded.getHeader("User-Agent"))
    }

    @Test
    fun cookie_header_is_phpsessid_only() = runBlocking {
        server.enqueue(MockResponse().setResponseCode(200).setBody("ok"))
        engine.execute(
            W4Request(url = server.url("/cookie"), priority = FetchPriority.Important),
            creds,
        )
        val cookie = server.takeRequest().getHeader("Cookie")!!
        assertTrue(cookie.contains("PHPSESSID=SESS"))
        assertFalse(cookie.contains("autologinkeyV2"))
        assertFalse(cookie.contains("isloggedin3"))
    }

    @Test
    fun empty_phpsessid_omits_cookie_header() = runBlocking {
        server.enqueue(MockResponse().setResponseCode(200).setBody("ok"))
        engine.execute(
            W4Request(
                url = server.url("/anon"),
                priority = FetchPriority.Important,
                allowLoginPage = true,
            ),
            W4Credentials(sessionId = ""),
        )
        assertEquals(null, server.takeRequest().getHeader("Cookie"))
    }

    @Test
    fun redirect_to_site_login_is_session_expired() = runBlocking {
        server.enqueue(
            MockResponse()
                .setResponseCode(302)
                .addHeader("Location", "/index.php?r=site/login"),
        )
        try {
            engine.execute(
                W4Request(
                    url = server.url("/index.php?r=site/index"),
                    priority = FetchPriority.Important,
                    studentId = "s1",
                ),
                creds,
            )
            org.junit.Assert.fail("expected W4Error.SessionExpired")
        } catch (_: W4Error.SessionExpired) {
            // expected
        }
        assertEquals(1, server.requestCount)
    }

    @Test
    fun redirect_to_otp_is_followed_not_expired() = runBlocking {
        server.enqueue(
            MockResponse()
                .setResponseCode(302)
                .addHeader("Location", "/index.php?r=site/verify2fa"),
        )
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody("""<form action="/index.php?r=site/verify2fa"><input name="Verify2faForm[code]"></form>"""),
        )
        val result = engine.execute(
            W4Request(
                url = server.url("/index.php?r=site/login"),
                priority = FetchPriority.Important,
                allowLoginPage = true,
            ),
            creds,
        )
        assertEquals(200, result.response.statusCode)
        assertTrue(result.response.body.contains("Verify2faForm[code]"))
        assertEquals(2, server.requestCount)
    }

    @Test
    fun login_html_is_session_expired_unless_allowed() = runBlocking {
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody("""<input name="LoginForm[username]">"""),
        )
        try {
            engine.execute(
                W4Request(
                    url = server.url("/index.php?r=site/index"),
                    priority = FetchPriority.Important,
                    studentId = "s1",
                ),
                creds,
            )
            org.junit.Assert.fail("expected W4Error.SessionExpired")
        } catch (_: W4Error.SessionExpired) {
            // expected
        }
    }

    @Test
    fun login_html_allowed_during_native_auth() = runBlocking {
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody("""<input name="LoginForm[username]">"""),
        )
        val result = engine.execute(
            W4Request(
                url = server.url("/index.php?r=site/login"),
                priority = FetchPriority.Important,
                allowLoginPage = true,
            ),
            creds,
        )
        assertEquals(200, result.response.statusCode)
        assertTrue(result.response.body.contains("LoginForm[username]"))
    }

    @Test
    fun ajax_403_login_required_is_session_expired() = runBlocking {
        server.enqueue(
            MockResponse()
                .setResponseCode(403)
                .setBody("Login Required"),
        )
        try {
            engine.execute(
                W4Request(
                    url = server.url("/index.php?r=notifications/refresh"),
                    method = "POST",
                    body = ByteArray(0),
                    priority = FetchPriority.Important,
                    studentId = "s1",
                    ajax = true,
                ),
                creds,
            )
            org.junit.Assert.fail("expected W4Error.SessionExpired")
        } catch (_: W4Error.SessionExpired) {
            // expected
        }
        assertEquals("XMLHttpRequest", server.takeRequest().getHeader("X-Requested-With"))
    }

    @Test
    fun ajax_403_without_login_required_is_forbidden() = runBlocking {
        server.enqueue(
            MockResponse()
                .setResponseCode(403)
                .setBody("not authorized"),
        )
        try {
            engine.execute(
                W4Request(
                    url = server.url("/index.php?r=admissions/browse/admissions"),
                    priority = FetchPriority.Important,
                    studentId = "s1",
                    ajax = true,
                ),
                creds,
            )
            org.junit.Assert.fail("expected W4Error.Forbidden")
        } catch (_: W4Error.Forbidden) {
            // expected
        }
    }

    @Test
    fun ajax_409_is_server_conflict() = runBlocking {
        server.enqueue(
            MockResponse()
                .setResponseCode(409)
                .setBody("disk full"),
        )
        try {
            engine.execute(
                W4Request(
                    url = server.url("/index.php?r=site/setstatus"),
                    method = "POST",
                    body = "status=on".toByteArray(),
                    priority = FetchPriority.Important,
                    ajax = true,
                ),
                creds,
            )
            org.junit.Assert.fail("expected W4Error.ServerConflict")
        } catch (e: W4Error.ServerConflict) {
            assertEquals("disk full", e.body)
        }
    }

    @Test
    fun max_redirects_with_student_is_session_expired() = runBlocking {
        repeat(8) {
            server.enqueue(
                MockResponse()
                    .setResponseCode(302)
                    .addHeader("Location", server.url("/loop").toString()),
            )
        }
        try {
            engine.execute(
                W4Request(
                    url = server.url("/loop"),
                    priority = FetchPriority.Important,
                    studentId = "s1",
                ),
                creds,
            )
            org.junit.Assert.fail("expected W4Error.SessionExpired")
        } catch (_: W4Error.SessionExpired) {
            // expected
        }
    }
}
